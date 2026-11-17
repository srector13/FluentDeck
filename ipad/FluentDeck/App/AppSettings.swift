import SwiftUI
import Observation
import UIKit

/// Preferences the user sets in Settings, kept on the iPad.
@MainActor
@Observable
final class AppSettings {
    /// What the board sits on: the colours of the cover art that's playing, or one colour.
    enum Backdrop: String, CaseIterable, Identifiable {
        case artwork, color
        var id: String { rawValue }
        var title: String { self == .artwork ? "Artwork" : "Color" }
    }

    /// Tints offered as swatches: the iOS system colours in dark mode, then graphite.
    static let accentSwatches = ["#0A84FF", "#5E5CE6", "#BF5AF2", "#FF375F", "#FF453A", "#FF9F0A",
                                 "#FFD60A", "#30D158", "#66D4CF", "#64D2FF", "#8E8E93"]
    /// Backdrop swatches: deep tones that keep white text readable.
    static let backdropSwatches = ["#000000", "#1C1C1E", "#0B1A33", "#1B1036", "#2A0F1F", "#0E2A1F", "#2B1D0E", "#132A2E"]

    var backdrop: Backdrop { didSet { save("backdrop", backdrop.rawValue) } }
    var backdropHex: String { didSet { save("backdropColor", backdropHex) } }
    var accentHex: String { didSet { save("accent", accentHex) } }
    /// Show each deck key's name under its symbol.
    var keyLabels: Bool { didSet { save("keyLabels", keyLabels) } }
    /// Lit keys fill with the accent colour instead of white.
    var litKeysUseAccent: Bool { didSet { save("litKeysUseAccent", litKeysUseAccent) } }
    /// Bring up a board when one of its apps comes to the front on the PC.
    var autoSwitchBoards: Bool { didSet { save("autoSwitchBoards", autoSwitchBoards) } }
    /// A tap of feedback when a key is pressed.
    var haptics: Bool { didSet { save("haptics", haptics) } }
    /// nil follows the iPad's region; true and false force 24- or 12-hour time.
    var clock24Hour: Bool? { didSet { save("clock24Hour", clock24Hour) } }
    /// The names given to PCs on this iPad, by host id.
    private(set) var pcNames: [String: String] { didSet { save("pcNames", pcNames) } }

    private static let prefix = "fluentdeck.settings."

    init() {
        let d = UserDefaults.standard
        func value<T>(_ key: String) -> T? { d.object(forKey: Self.prefix + key) as? T }
        backdrop = Backdrop(rawValue: value("backdrop") ?? "") ?? .artwork
        backdropHex = value("backdropColor") ?? "#0B1A33"
        accentHex = value("accent") ?? "#0A84FF"
        keyLabels = value("keyLabels") ?? true
        haptics = value("haptics") ?? true
        litKeysUseAccent = value("litKeysUseAccent") ?? false
        autoSwitchBoards = value("autoSwitchBoards") ?? true
        clock24Hour = value("clock24Hour")
        pcNames = value("pcNames") ?? [:]
    }

    private func save(_ key: String, _ value: Any?) {
        if let value { UserDefaults.standard.set(value, forKey: Self.prefix + key) }
        else { UserDefaults.standard.removeObject(forKey: Self.prefix + key) }
    }

    var theme: Theme { Theme(accentHex: accentHex) }

    var uses24Hour: Bool {
        clock24Hour ?? !(DateFormatter.dateFormat(fromTemplate: "j", options: 0, locale: .current) ?? "").contains("a")
    }

    // MARK: PC names

    func pcName(for hostId: String?) -> String? {
        hostId.flatMap { pcNames[$0] }
    }

    /// Call the PC something else on this iPad. An empty name goes back to the PC's own.
    func rename(pc hostId: String, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        pcNames[hostId] = trimmed.isEmpty ? nil : trimmed
    }
}

extension Color {
    /// "#RRGGBB" for a colour picked in a ColorPicker.
    var hexString: String {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(self).getRed(&r, green: &g, blue: &b, alpha: &a)
        func byte(_ v: CGFloat) -> Int { Int((min(max(v, 0), 1) * 255).rounded()) }
        return String(format: "#%02X%02X%02X", byte(r), byte(g), byte(b))
    }
}
