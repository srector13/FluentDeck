import SwiftUI
import UIKit

// MARK: - Buttons

/// Capsule buttons in the iOS manner: a filled tint for the main action, a grey fill for the rest,
/// and a bare one for icons in a row.
struct PillButtonStyle: ButtonStyle {
    enum Kind { case standard, accent, subtle }
    var kind: Kind = .standard
    var compact = false
    var fill = false

    func makeBody(configuration: Configuration) -> some View {
        PillButtonBody(configuration: configuration, kind: kind, compact: compact, fill: fill)
    }
}

private struct PillButtonBody: View {
    let configuration: ButtonStyleConfiguration
    let kind: PillButtonStyle.Kind
    let compact: Bool
    let fill: Bool
    @Environment(\.theme) private var theme
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        let pressed = configuration.isPressed
        configuration.label
            .font(kind == .accent ? AppFont.bodyStrong : AppFont.body)
            .lineLimit(1)
            .foregroundStyle(kind == .accent ? theme.textOnAccent : theme.textPrimary)
            .padding(.horizontal, compact ? 8 : 18)
            .frame(minWidth: compact ? 36 : 44, maxWidth: fill ? .infinity : nil, minHeight: compact ? 36 : Metrics.touchTarget)
            .background(Capsule().fill(background(pressed)))
            .contentShape(Capsule())
            .opacity(isEnabled ? 1 : 0.4)
            .animation(.easeOut(duration: 0.1), value: pressed)
    }

    private func background(_ pressed: Bool) -> Color {
        switch kind {
        case .accent: return pressed ? theme.accentPressed : theme.accent
        case .standard: return pressed ? theme.controlFillSecondary : theme.controlFill
        case .subtle: return pressed ? theme.controlFill : .clear
        }
    }
}

/// Icon-only button with a 44 pt touch target.
struct IconButton: View {
    let symbol: String
    var size: CGFloat = 17
    var tint: Color?
    var label: String = ""
    let action: () -> Void
    @Environment(\.theme) private var theme

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size, weight: .regular))
                .foregroundStyle(tint ?? theme.textPrimary)
                .frame(width: Metrics.touchTarget - 4, height: Metrics.touchTarget - 4)
        }
        .buttonStyle(PillButtonStyle(kind: .subtle, compact: true))
        .accessibilityLabel(label.isEmpty ? symbol : label)
    }
}

// MARK: - Grouped cell

/// An opaque rounded cell, as in an iOS grouped list.
struct PlatterModifier: ViewModifier {
    var padding: CGFloat = Metrics.cardPadding
    @Environment(\.theme) private var theme

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(RoundedRectangle(cornerRadius: Metrics.controlRadius + 4, style: .continuous).fill(theme.cardFill))
    }
}

extension View {
    func platter(padding: CGFloat = Metrics.cardPadding) -> some View { modifier(PlatterModifier(padding: padding)) }
}

// MARK: - Progress

/// A determinate level: a soft rail with a tinted fill.
struct LevelBar: View {
    var value: Double
    var tint: Color?
    @Environment(\.theme) private var theme

    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule().fill(theme.trackFill)
                Capsule().fill(tint ?? theme.accent).frame(width: max(6, g.size.width * min(max(value, 0), 1)))
            }
        }
        .frame(height: 6)
        .animation(.easeOut(duration: 0.3), value: value)
    }
}

/// The system activity indicator.
struct Spinner: View {
    var size: CGFloat = 20

    var body: some View {
        ProgressView()
            .controlSize(size < 18 ? .small : .regular)
            .frame(width: size, height: size)
    }
}

/// A ring gauge for stats (CPU etc.), in the manner of the activity rings.
struct RingGauge: View {
    var value: Double
    var label: String
    var lineWidth: CGFloat = 8
    @Environment(\.theme) private var theme

    var body: some View {
        ZStack {
            Circle().stroke(theme.trackFill, lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: min(max(value, 0), 1))
                .stroke(theme.accent, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.easeOut(duration: 0.4), value: value)
            VStack(spacing: 0) {
                Text("\(Int((value * 100).rounded()))%")
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                Text(label).font(AppFont.caption).foregroundStyle(theme.textSecondary)
            }
            .foregroundStyle(theme.textPrimary)
        }
        .padding(lineWidth / 2)
    }
}

// MARK: - Banner and status dot

/// An inline notice: an icon in the severity's color, a title, and optionally a message.
struct Banner: View {
    enum Severity { case informational, success, warning, error }
    var severity: Severity = .informational
    var title: String
    var message: String? = nil
    var busy = false
    var onClose: (() -> Void)? = nil
    @Environment(\.theme) private var theme

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            if busy {
                Spinner(size: 16).padding(.top, 2)
            } else {
                Image(systemName: symbol)
                    .font(.system(size: 17))
                    .foregroundStyle(tint)
                    .padding(.top, 1)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(AppFont.bodyStrong)
                if let message { Text(message).font(AppFont.caption).foregroundStyle(theme.textSecondary) }
            }
            .foregroundStyle(theme.textPrimary)
            .frame(maxWidth: .infinity, alignment: .leading)
            if let onClose { IconButton(symbol: "xmark", size: 13, tint: theme.textSecondary, label: "Close", action: onClose).padding(-8) }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(RoundedRectangle(cornerRadius: Metrics.controlRadius + 4, style: .continuous).fill(.regularMaterial))
        .background(RoundedRectangle(cornerRadius: Metrics.controlRadius + 4, style: .continuous).fill(tint.opacity(0.18)))
    }

    private var symbol: String {
        switch severity {
        case .informational: return "info.circle.fill"
        case .success: return "checkmark.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .error: return "xmark.octagon.fill"
        }
    }

    private var tint: Color {
        switch severity {
        case .informational: return theme.accent
        case .success: return theme.success
        case .warning: return theme.caution
        case .error: return theme.critical
        }
    }
}

struct StatusDot: View {
    var color: Color
    var body: some View {
        Circle().fill(color).frame(width: 8, height: 8)
    }
}

// MARK: - Text field

/// A filled, rounded text field, like the ones in iOS search bars and forms.
struct TextBox: View {
    var placeholder: String
    @Binding var text: String
    var keyboard: UIKeyboardType = .default
    var contentType: UITextContentType? = nil
    var large = false
    var onSubmit: () -> Void = {}
    @Environment(\.theme) private var theme

    var body: some View {
        TextField(placeholder, text: $text)
            .keyboardType(keyboard)
            .textContentType(contentType)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .font(large ? AppFont.title : AppFont.body)
            .multilineTextAlignment(large ? .center : .leading)
            .foregroundStyle(theme.textPrimary)
            .padding(.horizontal, 14)
            .frame(height: large ? 64 : Metrics.touchTarget)
            .background(RoundedRectangle(cornerRadius: Metrics.controlRadius, style: .continuous).fill(theme.controlFill))
            .onSubmit(onSubmit)
    }
}

// MARK: - Section header & empty state

struct SectionHeader: View {
    var title: String
    @Environment(\.theme) private var theme
    var body: some View {
        Text(title)
            .font(.system(size: 20, weight: .semibold))
            .foregroundStyle(theme.textPrimary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 10)
    }
}

struct PanelEmptyState: View {
    var symbol: String
    var text: String
    @Environment(\.theme) private var theme
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: symbol).font(.system(size: 26, weight: .light))
            Text(text).font(AppFont.body).multilineTextAlignment(.center)
        }
        .foregroundStyle(theme.textTertiary)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
