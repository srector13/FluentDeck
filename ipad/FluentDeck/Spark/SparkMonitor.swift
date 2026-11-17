import Foundation
import Observation

/// How the AI server is doing, as last measured.
struct SparkSnapshot: Equatable {
    struct GPU: Equatable {
        var utilization: Double?   // 0…100
        var temperature: Double?   // °C
        var power: Double?         // W
        var memoryUsedGB: Double?
        var memoryTotalGB: Double?
    }

    var online: Bool
    var model: String?
    var contextLength: Int?
    var running: Double = 0
    var waiting: Double = 0
    /// Share of the KV cache in use, 0…1.
    var kvCache: Double?
    /// Tokens per second over the last few seconds.
    var generationRate: Double = 0
    var promptRate: Double = 0
    /// Average time to first token and per-request latency of requests that finished recently.
    var timeToFirstToken: Double?
    var requestLatency: Double?
    var requestsServed: Double?
    /// Generation tokens per second, oldest first (about three minutes).
    var history: [Double] = []
    var gpu: GPU?
    var error: String?
    var lastSeen: Date?
}

/// Watches a vLLM server: /health, /v1/models and its Prometheus /metrics, plus an optional GPU
/// exporter (NVIDIA DCGM or nvidia_gpu_exporter). The iPad asks it directly over the network
/// (Tailscale works); the PC isn't involved. Polls only while a Spark widget is on screen.
@MainActor
@Observable
final class SparkMonitor {
    static let shared = SparkMonitor()

    private(set) var snapshot: SparkSnapshot?

    /// Where the server and the GPU exporter are, and the API key if vLLM was started with one.
    @ObservationIgnored var configuration: () -> (server: URL?, gpu: URL?, apiKey: String?) = { (nil, nil, nil) }

    @ObservationIgnored private var watchers = 0
    @ObservationIgnored private var loop: Task<Void, Never>?
    @ObservationIgnored private var previous: (at: Date, values: [String: Double])?
    @ObservationIgnored private var modelCheckedAt: Date?
    @ObservationIgnored private var lastServer: URL?
    private let interval: UInt64 = 3_000_000_000

    /// Keep polling while the caller's task runs (a widget's `.task`).
    func watch() async {
        watchers += 1
        if loop == nil {
            loop = Task { [weak self] in
                while let self, self.watchers > 0, !Task.isCancelled {
                    await self.refresh()
                    try? await Task.sleep(nanoseconds: self.interval)
                }
                self?.loop = nil
            }
        }
        while !Task.isCancelled { try? await Task.sleep(nanoseconds: 1_000_000_000) }
        watchers -= 1
    }

    /// Measure now (also when Settings changes the address).
    func refresh() async {
        let config = configuration()
        guard let server = config.server else {
            snapshot = nil
            previous = nil
            return
        }
        if server != lastServer {
            lastServer = server
            previous = nil
            modelCheckedAt = nil
            snapshot = nil
        }
        var next = snapshot ?? SparkSnapshot(online: false)

        async let metricsText = Self.fetchText(server.appending(path: "metrics"), key: nil)
        async let healthy = Self.fetchStatus(server.appending(path: "health"))
        var gpuText: String?
        if let gpu = config.gpu { gpuText = try? await Self.fetchText(gpu, key: nil) }

        do {
            let text = try await metricsText
            let values = Prometheus.parse(text)
            apply(values, to: &next)
            next.online = true
            next.error = nil
            next.lastSeen = .now
        } catch {
            // Metrics can be off (or blocked) while the server still answers.
            let ok = await healthy
            next.online = ok
            next.error = ok ? "Online, but /metrics didn't answer." : Self.describe(error)
            if !ok { next.running = 0; next.waiting = 0; next.generationRate = 0; next.promptRate = 0 }
        }

        if next.online, modelCheckedAt.map({ Date.now.timeIntervalSince($0) > 60 }) ?? true {
            modelCheckedAt = .now
            if let info = try? await Self.model(server.appending(path: "v1/models"), key: config.apiKey) {
                next.model = info.id
                next.contextLength = info.maxModelLen
            }
        }

        next.gpu = gpuText.map { GPUMetrics.parse(Prometheus.parse($0)) }
        next.history.append(next.online ? next.generationRate : 0)
        if next.history.count > 60 { next.history.removeFirst(next.history.count - 60) }
        snapshot = next
    }

    /// Turn the counters into rates and recent averages since the last poll.
    private func apply(_ v: [String: Double], to s: inout SparkSnapshot) {
        func value(_ names: String...) -> Double? { names.lazy.compactMap { v[$0] }.first }
        s.running = value("vllm:num_requests_running") ?? 0
        s.waiting = value("vllm:num_requests_waiting") ?? 0
        s.kvCache = value("vllm:kv_cache_usage_perc", "vllm:gpu_cache_usage_perc")
        s.requestsServed = value("vllm:request_success_total")

        let now = Date.now
        if let prev = previous {
            let dt = max(0.5, now.timeIntervalSince(prev.at))
            func rate(_ name: String) -> Double? {
                guard let a = prev.values[name], let b = v[name], b >= a else { return nil }
                return (b - a) / dt
            }
            func average(_ base: String) -> Double? {
                guard let s0 = prev.values[base + "_sum"], let s1 = v[base + "_sum"],
                      let c0 = prev.values[base + "_count"], let c1 = v[base + "_count"], c1 > c0 else { return nil }
                return (s1 - s0) / (c1 - c0)
            }
            s.generationRate = rate("vllm:generation_tokens_total") ?? 0
            s.promptRate = rate("vllm:prompt_tokens_total") ?? 0
            if let t = average("vllm:time_to_first_token_seconds") { s.timeToFirstToken = t }
            if let t = average("vllm:e2e_request_latency_seconds") { s.requestLatency = t }
        }
        previous = (now, v)
    }

    // MARK: requests

    private static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 4
        config.waitsForConnectivity = false
        return URLSession(configuration: config)
    }()

    private static func fetchText(_ url: URL, key: String?) async throws -> String {
        var request = URLRequest(url: url)
        if let key, !key.isEmpty { request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization") }
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        return String(decoding: data, as: UTF8.self)
    }

    private static func fetchStatus(_ url: URL) async -> Bool {
        guard let (_, response) = try? await session.data(from: url) else { return false }
        return (response as? HTTPURLResponse)?.statusCode == 200
    }

    private struct Models: Decodable {
        struct Model: Decodable {
            var id: String
            var maxModelLen: Int?
            enum CodingKeys: String, CodingKey { case id, maxModelLen = "max_model_len" }
        }
        var data: [Model]
    }

    private static func model(_ url: URL, key: String?) async throws -> (id: String, maxModelLen: Int?)? {
        let text = try await fetchText(url, key: key)
        guard let first = try JSONDecoder().decode(Models.self, from: Data(text.utf8)).data.first else { return nil }
        return (first.id, first.maxModelLen)
    }

    private static func describe(_ error: Error) -> String {
        switch (error as? URLError)?.code {
        case .timedOut?: return "Not answering. Is the Spark on and Tailscale connected?"
        case .cannotConnectToHost?: return "Nothing is listening at that address. Is vLLM running?"
        case .notConnectedToInternet?, .networkConnectionLost?: return "This iPad is offline."
        case .badServerResponse?: return "The server answered with an error."
        default: return "Can't reach the Spark."
        }
    }

    /// "100.64.1.2" → http://100.64.1.2:8000; a scheme, port or path given is kept.
    static func url(from text: String, defaultPort: Int) -> URL? {
        var t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return nil }
        if !t.contains("://") { t = "http://" + t }
        guard var parts = URLComponents(string: t), parts.host?.isEmpty == false else { return nil }
        if parts.port == nil && (parts.path.isEmpty || parts.path == "/") { parts.port = defaultPort }
        if parts.path == "/" { parts.path = "" }
        return parts.url
    }
}

/// The Prometheus text format, summed over label sets: `name{labels} value [timestamp]`.
enum Prometheus {
    static func parse(_ text: String) -> [String: Double] {
        var values: [String: Double] = [:]
        for raw in text.split(whereSeparator: \.isNewline) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty, !line.hasPrefix("#") else { continue }
            let name: Substring
            let rest: Substring
            if let brace = line.firstIndex(of: "{"), let close = line[brace...].firstIndex(of: "}") {
                name = line[..<brace]
                rest = line[line.index(after: close)...]
            } else if let space = line.firstIndex(of: " ") {
                name = line[..<space]
                rest = line[space...]
            } else { continue }
            guard let field = rest.split(separator: " ", omittingEmptySubsequences: true).first,
                  let value = Double(field), value.isFinite else { continue }
            values[String(name), default: 0] += value
        }
        return values
    }
}

/// GPU figures from whichever exporter is running.
enum GPUMetrics {
    static func parse(_ v: [String: Double]) -> SparkSnapshot.GPU {
        func value(_ names: String...) -> Double? { names.lazy.compactMap { v[$0] }.first }
        var gpu = SparkSnapshot.GPU()
        gpu.utilization = value("DCGM_FI_DEV_GPU_UTIL") ?? value("nvidia_smi_utilization_gpu_ratio").map { $0 * 100 }
        gpu.temperature = value("DCGM_FI_DEV_GPU_TEMP", "nvidia_smi_temperature_gpu")
        gpu.power = value("DCGM_FI_DEV_POWER_USAGE", "nvidia_smi_power_draw_watts")
        if let used = value("DCGM_FI_DEV_FB_USED") {
            gpu.memoryUsedGB = used / 1024
            if let free = value("DCGM_FI_DEV_FB_FREE") { gpu.memoryTotalGB = (used + free) / 1024 }
        } else if let used = value("nvidia_smi_memory_used_bytes") {
            gpu.memoryUsedGB = used / 1_073_741_824
            gpu.memoryTotalGB = value("nvidia_smi_memory_total_bytes").map { $0 / 1_073_741_824 }
        }
        return gpu
    }
}
