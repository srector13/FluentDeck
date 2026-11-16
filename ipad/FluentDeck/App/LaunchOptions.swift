import Foundation

/// Launch arguments for UI tests and screenshots. Each is read from the launch-argument
/// domain of UserDefaults, so `-FluentDeckConnect 127.0.0.1:47610` sets "FluentDeckConnect".
///
/// | Argument | Effect |
/// |---|---|
/// | `-FluentDeckReset YES` | start with no saved PCs, tokens, layout or preferences |
/// | `-FluentDeckConnect host[:port]` | connect to this PC at launch (e.g. the DevHost on 127.0.0.1) |
/// | `-FluentDeckPairCode 123456` | answer the pairing prompt with this code |
/// | `-FluentDeckBoard N` | open board N (0-based) |
enum LaunchOptions {
    private static var args: UserDefaults { .standard }

    static var reset: Bool { args.bool(forKey: "FluentDeckReset") }
    static var pairCode: String? { args.string(forKey: "FluentDeckPairCode").flatMap { $0.isEmpty ? nil : $0 } }
    static var board: Int? { args.object(forKey: "FluentDeckBoard") == nil ? nil : args.integer(forKey: "FluentDeckBoard") }

    static var connect: HostEndpoint? {
        guard let raw = args.string(forKey: "FluentDeckConnect"), !raw.isEmpty else { return nil }
        var host = raw
        var port = 47610
        if let colon = raw.lastIndex(of: ":"), !raw.hasPrefix("["), let p = Int(raw[raw.index(after: colon)...]) {
            host = String(raw[..<colon])
            port = p
        }
        return HostEndpoint(host: host, port: port, hostId: nil, name: host)
    }

    /// Clears persisted state. Call before any store reads UserDefaults.
    static func applyReset() {
        guard reset else { return }
        let defaults = UserDefaults.standard
        if let saved = defaults.data(forKey: "fluentdeck.hosts"),
           let hosts = try? JSONDecoder().decode([HostEndpoint].self, from: saved) {
            hosts.compactMap(\.hostId).forEach(Keychain.deleteToken(for:))
        }
        for key in ["fluentdeck.hosts", LayoutStore.storageKey, "fluentdeck.keepAwake"] {
            defaults.removeObject(forKey: key)
        }
    }
}
