import SwiftUI

// iOS in dark mode, laid out like Control Center: translucent modules on a dark ground, round
// toggle buttons and thick pill sliders. Navigation, menus, sheets and switches are the system's
// own. Colors are the iOS dark system palette.

enum Metrics {
    static let controlRadius: CGFloat = 12     // fields, list rows, banners
    static let artRadius: CGFloat = 16         // cover art
    static let panelRadius: CGFloat = 30       // a module's platter
    static let cardPadding: CGFloat = 16       // inside a module
    static let gutter: CGFloat = 14            // between modules, as in Control Center
    static let margin: CGFloat = 20            // screen edge
    static let touchTarget: CGFloat = 44
}

/// The type ramp, in SF. Large numerals use the rounded design, as iOS does for time and counts.
enum AppFont {
    static let caption = Font.system(size: 13)
    static let body = Font.system(size: 16)
    static let bodyStrong = Font.system(size: 16, weight: .semibold)
    static let bodyLarge = Font.system(size: 20)
    static let subtitle = Font.system(size: 22, weight: .bold)
    static let title = Font.system(size: 28, weight: .bold)
    static let titleLarge = Font.system(size: 42, weight: .semibold, design: .rounded)
    static let display = Font.system(size: 64, weight: .semibold, design: .rounded)
}

struct Theme: Equatable {
    /// The tint: iOS system blue in dark mode.
    var accent = Color(hex: "#0A84FF")

    static let `default` = Theme()

    private static func white(_ a: Double) -> Color { Color(white: 1, opacity: a) }

    var accentPressed: Color { accent.opacity(0.75) }
    var textOnAccent: Color { .white }

    // Labels (iOS label, secondaryLabel, tertiaryLabel, quaternaryLabel)
    var textPrimary: Color { .white }
    var textSecondary: Color { Color(hex: "#EBEBF5").opacity(0.6) }
    var textTertiary: Color { Color(hex: "#EBEBF5").opacity(0.3) }
    var textDisabled: Color { Color(hex: "#EBEBF5").opacity(0.18) }

    // Fills (iOS system fills, a little stronger because they sit on translucent modules)
    var controlFill: Color { Self.white(0.12) }
    var controlFillSecondary: Color { Self.white(0.18) }
    var controlFillTertiary: Color { Self.white(0.07) }
    /// An opaque chip: badges that sit on top of other content.
    var controlSolidFill: Color { Color(hex: "#3A3A3C") }
    /// A round control that is off, as in Control Center.
    var tileFill: Color { Self.white(0.16) }
    /// The rail of a slider or progress bar.
    var trackFill: Color { Self.white(0.14) }
    var divider: Color { Self.white(0.12) }

    // Surfaces
    /// An opaque grouped cell (iOS secondarySystemBackground), for screens without a backdrop.
    var cardFill: Color { Color(hex: "#1C1C1E") }
    var smoke: Color { Color(white: 0, opacity: 0.45) }

    // Status (iOS green, yellow, red in dark mode)
    var success: Color { Color(hex: "#30D158") }
    var caution: Color { Color(hex: "#FFD60A") }
    var critical: Color { Color(hex: "#FF453A") }
}

private struct ThemeKey: EnvironmentKey {
    static let defaultValue = Theme.default
}

extension EnvironmentValues {
    var theme: Theme {
        get { self[ThemeKey.self] }
        set { self[ThemeKey.self] = newValue }
    }
}

extension Color {
    /// "#RRGGBB" or "#AARRGGBB".
    init(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("#") { s.removeFirst() }
        var v: UInt64 = 0
        Scanner(string: s).scanHexInt64(&v)
        let a, r, g, b: Double
        if s.count == 8 {
            a = Double((v >> 24) & 0xFF) / 255; r = Double((v >> 16) & 0xFF) / 255
            g = Double((v >> 8) & 0xFF) / 255; b = Double(v & 0xFF) / 255
        } else {
            a = 1; r = Double((v >> 16) & 0xFF) / 255; g = Double((v >> 8) & 0xFF) / 255; b = Double(v & 0xFF) / 255
        }
        self.init(.sRGB, red: r, green: g, blue: b, opacity: a)
    }
}
