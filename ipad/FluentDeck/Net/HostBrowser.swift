import Foundation
import Network
import Observation

/// Finds PCs advertising `_fluentdeck._tcp` on the local network.
@MainActor
@Observable
final class HostBrowser {
    struct Found: Identifiable, Hashable {
        var id: String
        var name: String
        var endpoint: HostEndpoint?
        fileprivate var service: NWEndpoint
    }

    private(set) var hosts: [Found] = []
    private(set) var isBrowsing = false
    /// The user declined Local Network access (Settings → Privacy → Local Network).
    private(set) var permissionDenied = false

    @ObservationIgnored private var browser: NWBrowser?

    static let serviceType = "_fluentdeck._tcp"

    func start() {
        guard browser == nil else { return }
        let parameters = NWParameters()
        parameters.includePeerToPeer = false
        let b = NWBrowser(for: .bonjourWithTXTRecord(type: Self.serviceType, domain: nil), using: parameters)
        b.browseResultsChangedHandler = { [weak self] results, _ in
            Task { @MainActor in self?.update(results) }
        }
        b.stateUpdateHandler = { [weak self] state in
            Task { @MainActor in
                guard let self else { return }
                switch state {
                case .ready: self.isBrowsing = true; self.permissionDenied = false
                case .waiting(let error), .failed(let error):
                    self.isBrowsing = false
                    if case .dns(let code) = error, code == -65570 { self.permissionDenied = true } // kDNSServiceErr_PolicyDenied
                case .cancelled: self.isBrowsing = false
                default: break
                }
            }
        }
        b.start(queue: .main)
        browser = b
    }

    func stop() {
        browser?.cancel()
        browser = nil
        isBrowsing = false
    }

    private func update(_ results: Set<NWBrowser.Result>) {
        hosts = results.compactMap { result -> Found? in
            guard case let .service(name, _, _, _) = result.endpoint else { return nil }
            var txt: [String: String] = [:]
            if case let .bonjour(record) = result.metadata { txt = record.dictionary }
            let port = Int(txt["port"] ?? "") ?? 47610
            let ip = txt["ip"]?.split(separator: ",").first.map(String.init)
            let endpoint = ip.map { HostEndpoint(host: $0, port: port, hostId: txt["id"], name: name) }
            return Found(id: txt["id"] ?? name, name: name, endpoint: endpoint, service: result.endpoint)
        }
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// For hosts whose TXT record had no IP: resolve the service to a host/port.
    func resolve(_ found: Found) async -> HostEndpoint? {
        if let endpoint = found.endpoint { return endpoint }
        let service = found.service, id = found.id, name = found.name
        return await withCheckedContinuation { (continuation: CheckedContinuation<HostEndpoint?, Never>) in
            let connection = NWConnection(to: service, using: .tcp)
            let once = Once()
            let finish: @Sendable (HostEndpoint?) -> Void = { value in
                once.run {
                    connection.cancel()
                    continuation.resume(returning: value)
                }
            }
            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    if case let .hostPort(host, port)? = connection.currentPath?.remoteEndpoint {
                        var text = "\(host)"
                        if let pct = text.firstIndex(of: "%") { text = String(text[..<pct]) } // strip IPv6 scope
                        finish(HostEndpoint(host: text, port: Int(port.rawValue), hostId: id, name: name))
                    } else {
                        finish(nil)
                    }
                case .failed, .cancelled:
                    finish(nil)
                default:
                    break
                }
            }
            connection.start(queue: .main)
            DispatchQueue.main.asyncAfter(deadline: .now() + 5) { finish(nil) }
        }
    }
}

/// Runs its body at most once, from any thread.
private final class Once: @unchecked Sendable {
    private let lock = NSLock()
    private var done = false

    func run(_ body: () -> Void) {
        lock.lock()
        defer { lock.unlock() }
        guard !done else { return }
        done = true
        body()
    }
}
