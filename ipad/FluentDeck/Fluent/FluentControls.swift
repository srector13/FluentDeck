import SwiftUI
import UIKit

// MARK: - Buttons

/// Standard, accent and subtle (icon-bar) buttons: soft fills with pressed states, no outlines.
struct FluentButtonStyle: ButtonStyle {
    enum Kind { case standard, accent, subtle }
    var kind: Kind = .standard
    var compact = false
    var fill = false

    func makeBody(configuration: Configuration) -> some View {
        FluentButtonBody(configuration: configuration, kind: kind, compact: compact, fill: fill)
    }
}

private struct FluentButtonBody: View {
    let configuration: ButtonStyleConfiguration
    let kind: FluentButtonStyle.Kind
    let compact: Bool
    let fill: Bool
    @Environment(\.fluent) private var theme
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        let pressed = configuration.isPressed
        let shape = RoundedRectangle(cornerRadius: Fluent.controlRadius, style: .continuous)
        configuration.label
            .font(FluentFont.body)
            .lineLimit(1)
            .foregroundStyle(foreground(pressed))
            .padding(.horizontal, compact ? 8 : 16)
            .frame(minWidth: compact ? 36 : 44, maxWidth: fill ? .infinity : nil, minHeight: compact ? 36 : Fluent.touchTarget)
            .background(shape.fill(background(pressed)))
            .contentShape(shape)
            .animation(.easeOut(duration: 0.08), value: pressed)
    }

    private func background(_ pressed: Bool) -> Color {
        switch kind {
        case .accent:
            return isEnabled ? (pressed ? theme.accentTertiary : theme.accent) : theme.controlFillTertiary
        case .standard:
            return isEnabled ? (pressed ? theme.controlFillTertiary : theme.controlFill) : theme.controlFillTertiary
        case .subtle:
            return pressed ? theme.subtleFillTertiary : .clear
        }
    }

    private func foreground(_ pressed: Bool) -> Color {
        guard isEnabled else { return theme.textDisabled }
        switch kind {
        case .accent: return pressed ? theme.textOnAccent.opacity(0.7) : theme.textOnAccent
        default: return pressed ? theme.textSecondary : theme.textPrimary
        }
    }
}

/// Icon-only subtle button with a 44 pt touch target.
struct FluentIconButton: View {
    let symbol: String
    var size: CGFloat = 17
    var tint: Color?
    var label: String = ""
    let action: () -> Void
    @Environment(\.fluent) private var theme

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size, weight: .regular))
                .foregroundStyle(tint ?? theme.textPrimary)
                .frame(width: Fluent.touchTarget - 4, height: Fluent.touchTarget - 4)
        }
        .buttonStyle(FluentButtonStyle(kind: .subtle, compact: true))
        .accessibilityLabel(label.isEmpty ? symbol : label)
    }
}

// MARK: - Toggle

/// WinUI ToggleSwitch.
struct FluentToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        FluentToggleBody(configuration: configuration)
    }
}

private struct FluentToggleBody: View {
    let configuration: ToggleStyleConfiguration
    @Environment(\.fluent) private var theme
    @GestureState private var pressed = false

    var body: some View {
        let on = configuration.isOn
        HStack(spacing: 12) {
            configuration.label.font(FluentFont.body).foregroundStyle(theme.textPrimary)
            Spacer(minLength: 8)
            ZStack(alignment: on ? .trailing : .leading) {
                Capsule().fill(on ? theme.accent : theme.controlAltFill)
                Capsule().strokeBorder(on ? Color.clear : theme.controlStrongStroke, lineWidth: 1)
                Capsule()
                    .fill(on ? theme.textOnAccent : theme.textSecondary)
                    .frame(width: pressed ? 20 : 15, height: 15)
                    .padding(.horizontal, 5)
            }
            .frame(width: 52, height: 26)
            .animation(.snappy(duration: 0.18), value: on)
            .animation(.snappy(duration: 0.12), value: pressed)
        }
        .frame(minHeight: Fluent.touchTarget)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .updating($pressed) { _, state, _ in state = true }
                .onEnded { _ in configuration.isOn.toggle() }
        )
    }
}

// MARK: - Card

struct FluentCardModifier: ViewModifier {
    var padding: CGFloat = Fluent.cardPadding
    @Environment(\.fluent) private var theme

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(RoundedRectangle(cornerRadius: Fluent.overlayRadius, style: .continuous).fill(theme.cardFill))
    }
}

extension View {
    func fluentCard(padding: CGFloat = Fluent.cardPadding) -> some View { modifier(FluentCardModifier(padding: padding)) }

    /// Records this view's frame in the root coordinate space (used to anchor flyouts).
    func readFrame(_ frame: Binding<CGRect>) -> some View {
        background(
            GeometryReader { g in
                let f = g.frame(in: .named(Fluent.rootSpace))
                Color.clear
                    .onAppear { frame.wrappedValue = f }
                    .onChange(of: f) { _, new in frame.wrappedValue = new }
            }
        )
    }
}

// MARK: - Progress

/// WinUI ProgressBar (determinate): thin rail, thicker rounded indicator.
struct FluentProgressBar: View {
    var value: Double
    var tint: Color?
    @Environment(\.fluent) private var theme

    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule().fill(theme.controlStrongFill.opacity(0.6)).frame(height: 1.5)
                Capsule().fill(tint ?? theme.accent).frame(width: max(4, g.size.width * min(max(value, 0), 1)), height: 4)
            }
            .frame(maxHeight: .infinity)
        }
        .frame(height: 6)
        .animation(.easeOut(duration: 0.3), value: value)
    }
}

/// WinUI ProgressRing (indeterminate).
struct FluentProgressRing: View {
    var size: CGFloat = 20
    var lineWidth: CGFloat = 2.5
    @Environment(\.fluent) private var theme
    @State private var spinning = false

    var body: some View {
        Circle()
            .trim(from: 0, to: 0.28)
            .stroke(theme.accent, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
            .frame(width: size, height: size)
            .rotationEffect(.degrees(spinning ? 360 : 0))
            .animation(.linear(duration: 0.9).repeatForever(autoreverses: false), value: spinning)
            .onAppear { spinning = true }
    }
}

/// A gauge ring for stats (CPU etc.).
struct FluentRingGauge: View {
    var value: Double
    var label: String
    var lineWidth: CGFloat = 6
    @Environment(\.fluent) private var theme

    var body: some View {
        ZStack {
            Circle().stroke(theme.controlStrongFill.opacity(0.25), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: min(max(value, 0), 1))
                .stroke(theme.accent, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.easeOut(duration: 0.4), value: value)
            VStack(spacing: 0) {
                Text("\(Int((value * 100).rounded()))%")
                    .font(FluentFont.bodyStrong)
                    .monospacedDigit()
                    .contentTransition(.numericText())
                Text(label).font(FluentFont.caption).foregroundStyle(theme.textSecondary)
            }
            .foregroundStyle(theme.textPrimary)
        }
    }
}

// MARK: - InfoBar / InfoBadge

/// WinUI InfoBar.
struct InfoBar: View {
    enum Severity { case informational, success, warning, error }
    var severity: Severity = .informational
    var title: String
    var message: String? = nil
    var busy = false
    var onClose: (() -> Void)? = nil
    @Environment(\.fluent) private var theme

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            if busy {
                FluentProgressRing(size: 16, lineWidth: 2).padding(.top, 2)
            } else {
                Image(systemName: symbol)
                    .font(.system(size: 16))
                    .foregroundStyle(iconColor)
                    .padding(.top, 1)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(FluentFont.bodyStrong)
                if let message { Text(message).font(FluentFont.body).foregroundStyle(theme.textSecondary) }
            }
            .foregroundStyle(theme.textPrimary)
            .frame(maxWidth: .infinity, alignment: .leading)
            if let onClose { FluentIconButton(symbol: "xmark", size: 13, label: "Close", action: onClose) .padding(-8) }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(RoundedRectangle(cornerRadius: Fluent.controlRadius, style: .continuous).fill(background))
    }

    private var symbol: String {
        switch severity {
        case .informational: return "info.circle.fill"
        case .success: return "checkmark.circle.fill"
        case .warning: return "exclamationmark.circle.fill"
        case .error: return "xmark.circle.fill"
        }
    }

    private var iconColor: Color {
        switch severity {
        case .informational: return theme.accent
        case .success: return theme.success
        case .warning: return theme.caution
        case .error: return theme.critical
        }
    }

    private var background: Color {
        switch severity {
        case .informational: return theme.attentionBackground
        case .success: return theme.successBackground
        case .warning: return theme.cautionBackground
        case .error: return theme.criticalBackground
        }
    }
}

/// WinUI InfoBadge dot.
struct InfoBadge: View {
    var color: Color
    var body: some View {
        Circle().fill(color).frame(width: 8, height: 8)
    }
}

// MARK: - TextBox

/// WinUI TextBox: filled field with the accent bottom border while focused.
struct FluentTextBox: View {
    var placeholder: String
    @Binding var text: String
    var keyboard: UIKeyboardType = .default
    var contentType: UITextContentType? = nil
    var large = false
    var onSubmit: () -> Void = {}
    @Environment(\.fluent) private var theme
    @FocusState private var focused: Bool

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Fluent.controlRadius, style: .continuous)
        TextField(placeholder, text: $text)
            .focused($focused)
            .keyboardType(keyboard)
            .textContentType(contentType)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .font(large ? FluentFont.title : FluentFont.body)
            .multilineTextAlignment(large ? .center : .leading)
            .foregroundStyle(theme.textPrimary)
            .padding(.horizontal, 12)
            .frame(height: large ? 64 : Fluent.touchTarget)
            .background(shape.fill(focused ? theme.controlFillInputActive : theme.controlFill))
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(focused ? theme.accent : theme.controlStrongStroke)
                    .frame(height: focused ? 2 : 1)
            }
            .clipShape(shape)
            .onSubmit(onSubmit)
    }
}

// MARK: - Section header & empty state

struct FluentSectionHeader: View {
    var title: String
    @Environment(\.fluent) private var theme
    var body: some View {
        Text(title)
            .font(FluentFont.bodyStrong)
            .foregroundStyle(theme.textPrimary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 8)
    }
}

struct PanelEmptyState: View {
    var symbol: String
    var text: String
    @Environment(\.fluent) private var theme
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: symbol).font(.system(size: 26, weight: .light))
            Text(text).font(FluentFont.body).multilineTextAlignment(.center)
        }
        .foregroundStyle(theme.textTertiary)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
