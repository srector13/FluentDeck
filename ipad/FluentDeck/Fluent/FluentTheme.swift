import SwiftUI

// "Onyx": Windows 11's dark quick settings controls, set straight on a true black ground.
// Nothing is boxed or ruled: space separates the widgets, and depth comes from soft fills and
// light (the cover art and lit keys glow) instead of borders. Text colors are the WinUI dark
// theme resources (e.g. TextFillColorSecondary = #C5FFFFFF); sizes are scaled up for touch.

enum Fluent {
    static let controlRadius: CGFloat = 10     // buttons, text boxes, info bars
    static let overlayRadius: CGFloat = 18     // flyouts, dialogs
    static let tileRadius: CGFloat = 24        // deck keys (smaller keys scale it down)
    static let artRadius: CGFloat = 22         // cover art
    static let panelRadius: CGFloat = 28       // a widget's outline while customizing
    static let cardPadding: CGFloat = 18
    static let gutter: CGFloat = 32            // between widgets: space does the dividing
    static let margin: CGFloat = 28            // screen edge; everything lines up on it
    static let touchTarget: CGFloat = 44
    static let rootSpace = "fluent.root"       // coordinate space flyouts anchor in
}

/// The Fluent type ramp (Segoe UI Variable isn't licensed for iOS; SF Pro at the same ramp reads very close).
enum FluentFont {
    static let caption = Font.system(size: 13)
    static let body = Font.system(size: 15)
    static let bodyStrong = Font.system(size: 15, weight: .semibold)
    static let bodyLarge = Font.system(size: 19)
    static let subtitle = Font.system(size: 22, weight: .semibold)
    static let title = Font.system(size: 30, weight: .semibold)
    static let titleLarge = Font.system(size: 42, weight: .semibold)
    static let display = Font.system(size: 64, weight: .semibold)
}

struct AccentPalette: Equatable {
    var base: Color
    var light1: Color, light2: Color, light3: Color
    var dark1: Color, dark2: Color, dark3: Color

    /// Windows 11 default blue.
    static let windowsBlue = AccentPalette(
        base: Color(hex: "#0078D4"),
        light1: Color(hex: "#0093F9"), light2: Color(hex: "#60CCFE"), light3: Color(hex: "#98ECFE"),
        dark1: Color(hex: "#005FB8"), dark2: Color(hex: "#004275"), dark3: Color(hex: "#001A68"))

    init(base: Color, light1: Color, light2: Color, light3: Color, dark1: Color, dark2: Color, dark3: Color) {
        self.base = base; self.light1 = light1; self.light2 = light2; self.light3 = light3
        self.dark1 = dark1; self.dark2 = dark2; self.dark3 = dark3
    }

    init(_ t: ThemeState) {
        self.init(base: Color(hex: t.accent),
                  light1: Color(hex: t.accentLight1), light2: Color(hex: t.accentLight2), light3: Color(hex: t.accentLight3),
                  dark1: Color(hex: t.accentDark1), dark2: Color(hex: t.accentDark2), dark3: Color(hex: t.accentDark3))
    }
}

struct FluentTheme: Equatable {
    var isDark: Bool
    var palette: AccentPalette

    static let `default` = FluentTheme(isDark: true, palette: .windowsBlue)

    private func pick(_ dark: Color, _ light: Color) -> Color { isDark ? dark : light }
    private static func white(_ a: Double) -> Color { Color(white: 1, opacity: a) }
    private static func black(_ a: Double) -> Color { Color(white: 0, opacity: a) }

    // Accent (AccentFillColorDefault uses Light2 in dark, Dark1 in light)
    var accent: Color { pick(palette.light2, palette.dark1) }
    var accentSecondary: Color { accent.opacity(0.9) }
    var accentTertiary: Color { accent.opacity(0.8) }
    var accentText: Color { pick(palette.light3, palette.dark2) }
    var textOnAccent: Color { pick(.black, .white) }

    // Text
    var textPrimary: Color { pick(.white, Self.black(0.894)) }
    var textSecondary: Color { pick(Self.white(0.786), Self.black(0.62)) }
    var textTertiary: Color { pick(Self.white(0.545), Self.black(0.447)) }
    var textDisabled: Color { pick(Self.white(0.363), Self.black(0.361)) }

    // Controls
    // Stronger than WinUI's: these sit on black, not on a flyout.
    var controlFill: Color { pick(Self.white(0.09), Self.white(0.70)) }
    var controlFillSecondary: Color { pick(Self.white(0.12), Color(white: 0.976, opacity: 0.5)) }
    var controlFillTertiary: Color { pick(Self.white(0.06), Color(white: 0.976, opacity: 0.3)) }
    /// A deck key: lit softly from above, with no outline.
    var tileFill: LinearGradient {
        LinearGradient(colors: [Color(white: 0.16), Color(white: 0.105)], startPoint: .top, endPoint: .bottom)
    }
    var controlFillInputActive: Color { pick(Color(white: 0.118, opacity: 0.7), .white) }
    var controlStrongFill: Color { pick(Self.white(0.545), Self.black(0.447)) }
    var controlSolidFill: Color { pick(Color(hex: "#454545"), .white) }
    var controlAltFill: Color { pick(Self.black(0.1), Self.black(0.024)) }
    var subtleFillSecondary: Color { pick(Self.white(0.061), Self.black(0.037)) }
    var subtleFillTertiary: Color { pick(Self.white(0.04), Self.black(0.024)) }

    // Strokes: only where an input needs an edge
    var controlStrongStroke: Color { pick(Self.white(0.545), Self.black(0.447)) }
    var divider: Color { pick(Self.white(0.084), Self.black(0.08)) }

    // Surfaces
    var cardFill: Color { pick(Color(hex: "#1C1C1C"), Self.white(0.70)) }
    var cardFillSecondary: Color { pick(Self.white(0.03), Color(white: 0.965, opacity: 0.5)) }
    var layerFill: Color { pick(Color(white: 0.227, opacity: 0.30), Self.white(0.5)) }
    var flyoutTint: Color { pick(Color(hex: "#2C2C2C").opacity(0.96), Color(hex: "#FCFCFC").opacity(0.96)) }
    var dialogFill: Color { pick(Color(hex: "#202020"), .white) }
    var dialogBody: Color { pick(Color(hex: "#262626"), .white) }
    var smoke: Color { Self.black(0.3) }

    // Status (InfoBar / InfoBadge)
    var success: Color { pick(Color(hex: "#6CCB5F"), Color(hex: "#0F7B0F")) }
    var caution: Color { pick(Color(hex: "#FCE100"), Color(hex: "#9D5D00")) }
    var critical: Color { pick(Color(hex: "#FF99A4"), Color(hex: "#C42B1C")) }
    var successBackground: Color { pick(Color(hex: "#393D1B"), Color(hex: "#DFF6DD")) }
    var cautionBackground: Color { pick(Color(hex: "#433519"), Color(hex: "#FFF4CE")) }
    var criticalBackground: Color { pick(Color(hex: "#442726"), Color(hex: "#FDE7E9")) }
    var attentionBackground: Color { pick(Self.white(0.035), Color(white: 0.965, opacity: 0.5)) }
}

private struct FluentThemeKey: EnvironmentKey {
    static let defaultValue = FluentTheme.default
}

extension EnvironmentValues {
    var fluent: FluentTheme {
        get { self[FluentThemeKey.self] }
        set { self[FluentThemeKey.self] = newValue }
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
