import Foundation
import Observation
import UIKit

enum HostError: LocalizedError {
    case notConnected
    case timeout
    case action(String)

    var errorDescription: String? {
        switch self {
        case .notConnected: return "Not connected to the PC."
        case .timeout: return "The PC didn't respond in time."
        case .action(let message): return message
        }
    }
}

/// One WebSocket to one PC: handshake, pairing, subscriptions, invokes, and automatic reconnects.
@MainActor
@Observable
final class HostConnection {
    enum Phase: Equatable {
        case idle
        case connecting
        case needsPairing(reason: String?)
        case connected
        case reconnecting(attempt: Int)
        case failed(String)
    }

    private(set) var phase: Phase = .idle
    private(set) var endpoint: HostEndpoint?
    /// The name the PC gives itself.
    private(set) var reportedName = ""
    /// The name this iPad calls a PC by, if the user renamed it (looked up by host id).
    @ObservationIgnored var localName: (@MainActor (String?) -> String?)?
    /// What to call the PC on screen.
    var hostName: String { localName?(hostId) ?? reportedName }
    private(set) var hostId: String?
    private(set) var panels: [PanelDescriptor] = []
    /// Last action error, shown briefly as an Banner toast.
    var toast: String?

    /// Called after a successful welcome with the endpoint (now carrying its hostId).
    @ObservationIgnored var onConnected: ((HostEndpoint) -> Void)?

    let store = TopicStore()
    private let session = URLSession(configuration: .default)
    @ObservationIgnored private var task: URLSessionWebSocketTask?
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var pending: [String: CheckedContinuation<JSON?, Error>] = [:]
    @ObservationIgnored private var nextId = 0
    @ObservationIgnored private var wantConnection = false
    @ObservationIgnored private var everConnected = false
    @ObservationIgnored private var attempt = 0
    @ObservationIgnored private var sentToken = false
    @ObservationIgnored private var heartbeat: Task<Void, Never>?
    @ObservationIgnored private var toastTask: Task<Void, Never>?

    var isConnected: Bool { phase == .connected }
    var isPairing: Bool { if case .needsPairing = phase { return true }; return false }
    var token: String? { hostId.flatMap(Keychain.token(for:)) }

    func hostProvides(_ panel: String) -> Bool { panels.contains { $0.id == panel } }

    // MARK: lifecycle

    func connect(to endpoint: HostEndpoint) {
        disconnect()
        self.endpoint = endpoint
        reportedName = endpoint.name
        hostId = endpoint.hostId
        wantConnection = true
        everConnected = false
        attempt = 0
        openSocket()
    }

    func disconnect() {
        wantConnection = false
        generation += 1
        heartbeat?.cancel()
        task?.cancel(with: .normalClosure, reason: nil)
        task = nil
        failPending(HostError.notConnected)
        panels = []
        store.clearAll()
        phase = .idle
    }

    /// Call when the app returns to the foreground: sockets don't survive suspension.
    func resume() {
        guard wantConnection, endpoint != nil else { return }
        switch phase {
        case .connected, .connecting, .needsPairing: return
        default:
            attempt = 0
            openSocket()
        }
    }

    func retry() {
        guard let endpoint else { return }
        connect(to: endpoint)
    }

    private func openSocket() {
        guard let url = endpoint?.webSocketURL else { phase = .failed("That address isn't valid."); return }
        generation += 1
        let gen = generation
        heartbeat?.cancel()
        task?.cancel(with: .goingAway, reason: nil)
        sentToken = false
        phase = everConnected ? .reconnecting(attempt: max(attempt, 1)) : .connecting

        var request = URLRequest(url: url)
        request.timeoutInterval = 8
        let t = session.webSocketTask(with: request)
        t.maximumMessageSize = 4 * 1024 * 1024
        task = t
        t.resume()
        Task { await receiveLoop(t, generation: gen) }
    }

    private func receiveLoop(_ t: URLSessionWebSocketTask, generation gen: Int) async {
        do {
            while gen == generation {
                let message = try await t.receive()
                guard gen == generation else { return }
                switch message {
                case .string(let text): handle(Data(text.utf8))
                case .data(let data): handle(data)
                @unknown default: break
                }
            }
        } catch {
            guard gen == generation else { return }
            connectionLost(error)
        }
    }

    private func connectionLost(_ error: Error) {
        heartbeat?.cancel()
        failPending(HostError.notConnected)
        guard wantConnection else { phase = .idle; return }

        if !everConnected && attempt >= 2 {
            phase = .failed("Couldn't reach \(hostName.isEmpty ? "the PC" : hostName). Make sure FluentDeck is running and both devices are on the same network.")
            return
        }
        attempt += 1
        phase = everConnected ? .reconnecting(attempt: attempt) : .connecting
        let delay = min(15.0, 0.5 * pow(2.0, Double(min(attempt, 5))))
        let gen = generation
        Task {
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard gen == self.generation, self.wantConnection else { return }
            self.openSocket()
        }
    }

    // MARK: messages

    private func handle(_ data: Data) {
        guard let msg = try? JSON.parse(data), let type = msg["type"]?.string else { return }
        switch type {
        case "server":
            if let id = msg["hostId"]?.string { hostId = id }
            if let name = msg["name"]?.string { reportedName = name }
            if let token {
                sentToken = true
                send(["type": "hello", "token": .string(token), "client": clientInfo])
            } else if let code = LaunchOptions.pairCode {
                send(["type": "pair", "code": .string(code), "client": clientInfo]) // UI tests and screenshots
            } else {
                phase = .needsPairing(reason: nil)
            }

        case "authError":
            let reason = msg["reason"]?.string
            if msg["needsPairing"]?.bool == true {
                if sentToken, let hostId { Keychain.deleteToken(for: hostId) } // revoked on the PC
                sentToken = false
                phase = .needsPairing(reason: reason)
            } else {
                phase = .failed(reason ?? "The PC refused the connection.")
            }

        case "paired":
            let id = msg["hostId"]?.string ?? hostId
            if let id, let token = msg["token"]?.string {
                hostId = id
                Keychain.setToken(token, for: id)
            }

        case "welcome":
            if let list = try? msg["panels"]?.decode([PanelDescriptor].self) { panels = list }
            if let name = msg["name"]?.string { reportedName = name }
            everConnected = true
            attempt = 0
            phase = .connected
            send(["type": "subscribe", "topics": .array(panels.map { .string($0.id) })])
            startHeartbeat()
            if var ep = endpoint {
                ep.hostId = hostId
                ep.name = reportedName
                endpoint = ep
                onConnected?(ep)
            }

        case "state":
            if let topic = msg["topic"]?.string, let value = msg["data"] { store.box(topic).set(value) }

        case "result":
            guard let id = msg["id"]?.string, let continuation = pending.removeValue(forKey: id) else { return }
            if msg["ok"]?.bool == true {
                continuation.resume(returning: msg["data"])
            } else {
                continuation.resume(throwing: HostError.action(msg["error"]?.string ?? "That didn't work."))
            }

        default:
            break // pong, error
        }
    }

    func pair(code: String) {
        let digits = code.filter(\.isNumber)
        guard task != nil else { retry(); return }
        send(["type": "pair", "code": .string(digits), "client": clientInfo])
    }

    private var clientInfo: JSON {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
        return ["name": .string(UIDevice.current.name), "version": .string(version)]
    }

    private func send(_ message: JSON) {
        task?.send(.string(message.serialized())) { _ in }
    }

    private func startHeartbeat() {
        heartbeat?.cancel()
        let gen = generation
        heartbeat = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 10_000_000_000)
                guard let self, gen == self.generation, let t = self.task else { return }
                t.sendPing { error in
                    guard error != nil else { return }
                    Task { @MainActor in
                        if gen == self.generation { self.connectionLost(error!) }
                    }
                }
            }
        }
    }

    private func failPending(_ error: Error) {
        let waiting = pending
        pending = [:]
        waiting.values.forEach { $0.resume(throwing: error) }
    }

    // MARK: actions

    /// Call a host panel action and wait for its result.
    @discardableResult
    func invoke(_ panel: String, _ action: String, _ args: [String: JSON] = [:]) async throws -> JSON? {
        guard isConnected else { throw HostError.notConnected }
        nextId += 1
        let id = "i\(nextId)"
        let message: JSON = ["type": "invoke", "id": .string(id), "panel": .string(panel), "action": .string(action), "args": .object(args)]
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<JSON?, Error>) in
            pending[id] = continuation
            send(message)
            Task { [weak self] in
                try? await Task.sleep(nanoseconds: 12_000_000_000)
                guard let self, let c = self.pending.removeValue(forKey: id) else { return }
                c.resume(throwing: HostError.timeout)
            }
        }
    }

    /// Fire-and-forget (slider drags). Errors are ignored; the next state update corrects the UI.
    func send(_ panel: String, _ action: String, _ args: [String: JSON] = [:]) {
        guard isConnected else { return }
        send(["type": "invoke", "panel": .string(panel), "action": .string(action), "args": .object(args)])
    }

    /// Invoke and surface any error as a toast.
    func run(_ panel: String, _ action: String, _ args: [String: JSON] = [:]) {
        Task {
            do { try await invoke(panel, action, args) } catch { report(error) }
        }
    }

    func report(_ error: Error) {
        toast = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        toastTask?.cancel()
        toastTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 3_500_000_000)
            if !Task.isCancelled { self?.toast = nil }
        }
    }

    /// Authenticated request for an /assets path (album art, app icons).
    func assetRequest(_ path: String) -> URLRequest? {
        guard let url = endpoint?.assetURL(path), let token else { return nil }
        var r = URLRequest(url: url)
        r.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        return r
    }
}
