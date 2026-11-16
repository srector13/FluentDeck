import SwiftUI
import Observation

// Windows-style MenuFlyout and ContentDialog, drawn by the app itself (iOS menus and alerts look iOS).

struct FlyoutItem: Identifiable {
    enum Kind {
        case action(title: String, symbol: String?, checked: Bool?, destructive: Bool, perform: () -> Void)
        case separator
        case header(String)
    }

    let id = UUID()
    let kind: Kind

    /// `checked: nil` → plain item; `true/false` → radio-style item with a check column.
    static func action(_ title: String, symbol: String? = nil, checked: Bool? = nil, destructive: Bool = false,
                       perform: @escaping () -> Void) -> FlyoutItem {
        FlyoutItem(kind: .action(title: title, symbol: symbol, checked: checked, destructive: destructive, perform: perform))
    }
    static var separator: FlyoutItem { FlyoutItem(kind: .separator) }
    static func header(_ title: String) -> FlyoutItem { FlyoutItem(kind: .header(title)) }
}

@MainActor
@Observable
final class OverlayCenter {
    struct Flyout {
        var anchor: CGRect
        var items: [FlyoutItem]
        var width: CGFloat
    }

    var flyout: Flyout?
    private(set) var dialog: AnyView?

    func showFlyout(anchor: CGRect, items: [FlyoutItem], width: CGFloat = 260) {
        guard !items.isEmpty else { return }
        withAnimation(.easeOut(duration: 0.15)) { flyout = Flyout(anchor: anchor, items: items, width: width) }
    }

    func dismissFlyout() {
        withAnimation(.easeOut(duration: 0.1)) { flyout = nil }
    }

    func present<V: View>(@ViewBuilder _ content: () -> V) {
        withAnimation(.easeOut(duration: 0.18)) { dialog = AnyView(content()) }
    }

    func dismissDialog() {
        withAnimation(.easeOut(duration: 0.12)) { dialog = nil }
    }
}

/// Renders the active flyout and dialog above everything. Place it last in the root ZStack.
struct OverlayHost: View {
    @Environment(OverlayCenter.self) private var overlays
    @Environment(\.fluent) private var theme

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                if let flyout = overlays.flyout {
                    Color.black.opacity(0.001)
                        .contentShape(Rectangle())
                        .onTapGesture { overlays.dismissFlyout() }
                    let size = CGSize(width: flyout.width, height: MenuFlyoutView.estimatedHeight(flyout.items))
                    let origin = Self.place(size, near: flyout.anchor, in: geo.size)
                    MenuFlyoutView(items: flyout.items) { overlays.dismissFlyout() }
                        .frame(width: size.width)
                        .offset(x: origin.x, y: origin.y)
                        .transition(.opacity.combined(with: .offset(y: origin.y > flyout.anchor.midY ? -6 : 6)))
                }
                if let dialog = overlays.dialog {
                    theme.smoke
                        .ignoresSafeArea()
                        .transition(.opacity)
                    dialog
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .padding(24)
                        .transition(.opacity.combined(with: .scale(scale: 1.04)))
                }
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
        }
    }

    /// Below the anchor, right-aligned to it; flips above when there's no room.
    static func place(_ size: CGSize, near anchor: CGRect, in bounds: CGSize) -> CGPoint {
        let margin: CGFloat = 8
        let x = min(max(anchor.maxX - size.width, margin), bounds.width - size.width - margin)
        var y = anchor.maxY + 4
        if y + size.height > bounds.height - margin {
            y = max(margin, anchor.minY - 4 - size.height)
        }
        return CGPoint(x: x, y: y)
    }
}

struct MenuFlyoutView: View {
    let items: [FlyoutItem]
    let dismiss: () -> Void
    @Environment(\.fluent) private var theme

    static let rowHeight: CGFloat = 44

    static func estimatedHeight(_ items: [FlyoutItem]) -> CGFloat {
        items.reduce(CGFloat(12)) { sum, item in
            switch item.kind {
            case .action: return sum + rowHeight
            case .separator: return sum + 9
            case .header: return sum + 30
            }
        }
    }

    private var hasChecks: Bool {
        items.contains { if case .action(_, _, let checked, _, _) = $0.kind { return checked != nil }; return false }
    }

    var body: some View {
        VStack(spacing: 0) {
            ForEach(items) { item in
                switch item.kind {
                case let .action(title, symbol, checked, destructive, perform):
                    Button {
                        dismiss()
                        perform()
                    } label: {
                        HStack(spacing: 12) {
                            if hasChecks {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 13, weight: .semibold))
                                    .opacity(checked == true ? 1 : 0)
                                    .frame(width: 16)
                            }
                            if let symbol {
                                Image(systemName: symbol).font(.system(size: 16)).frame(width: 20)
                            }
                            Text(title).font(FluentFont.body).lineLimit(1)
                            Spacer(minLength: 0)
                        }
                        .foregroundStyle(destructive ? theme.critical : theme.textPrimary)
                        .padding(.horizontal, 12)
                        .frame(height: Self.rowHeight)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(MenuRowStyle())
                case .separator:
                    Rectangle().fill(theme.divider).frame(height: 1).padding(.vertical, 4)
                case .header(let title):
                    Text(title)
                        .font(FluentFont.caption.weight(.semibold))
                        .foregroundStyle(theme.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 12)
                        .frame(height: 30)
                }
            }
        }
        .padding(4)
        .padding(2)
        .background(theme.flyoutTint, in: RoundedRectangle(cornerRadius: Fluent.overlayRadius, style: .continuous))
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: Fluent.overlayRadius, style: .continuous))
        .shadow(color: .black.opacity(0.5), radius: 24, y: 10)
    }
}

private struct MenuRowStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        MenuRowBody(configuration: configuration)
    }
}

private struct MenuRowBody: View {
    let configuration: ButtonStyleConfiguration
    @Environment(\.fluent) private var theme
    var body: some View {
        configuration.label
            .background(RoundedRectangle(cornerRadius: Fluent.overlayRadius - 6, style: .continuous).fill(configuration.isPressed ? theme.subtleFillSecondary : .clear))
    }
}

/// A button that opens a MenuFlyout anchored to itself.
struct FlyoutButton<Label: View>: View {
    var width: CGFloat = 260
    var style = FluentButtonStyle(kind: .subtle, compact: true)
    let items: () -> [FlyoutItem]
    @ViewBuilder let label: () -> Label

    @Environment(OverlayCenter.self) private var overlays
    @State private var frame: CGRect = .zero

    var body: some View {
        Button {
            overlays.showFlyout(anchor: frame, items: items(), width: width)
        } label: {
            label()
        }
        .buttonStyle(style)
        .readFrame($frame)
    }
}

/// A dialog in the WinUI ContentDialog arrangement (title, content, equal-width footer buttons), as one seamless surface.
struct ContentDialog<Content: View, Footer: View>: View {
    var title: String
    var maxWidth: CGFloat = 480
    @ViewBuilder var content: () -> Content
    @ViewBuilder var footer: () -> Footer
    @Environment(\.fluent) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 14) {
                Text(title).font(FluentFont.subtitle).foregroundStyle(theme.textPrimary)
                content()
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 8) { footer() }
                .padding([.horizontal, .bottom], 24)
                .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: maxWidth)
        .background(theme.dialogBody)
        .clipShape(RoundedRectangle(cornerRadius: Fluent.overlayRadius + 4, style: .continuous))
        .shadow(color: .black.opacity(0.5), radius: 40, y: 16)
    }
}

/// Footer button for ContentDialog (fills its share of the footer).
struct DialogButton: View {
    var title: String
    var accent = false
    var enabled = true
    let action: () -> Void

    var body: some View {
        Button(action: action) { Text(title).frame(maxWidth: .infinity) }
            .buttonStyle(FluentButtonStyle(kind: accent ? .accent : .standard, fill: true))
            .disabled(!enabled)
    }
}

// MARK: - SelectorBar

/// WinUI SelectorBar: text items with the accent pill under the selection.
struct SelectorBar<ID: Hashable>: View {
    struct Item: Identifiable { var id: ID; var title: String }
    let items: [Item]
    @Binding var selection: ID?
    var onLongPress: ((ID, CGRect) -> Void)? = nil

    @Environment(\.fluent) private var theme
    @State private var frames: [ID: CGRect] = [:]
    @Namespace private var pill

    var body: some View {
        HStack(spacing: 4) {
            ForEach(items) { item in
                let selected = item.id == selection
                Button {
                    withAnimation(.snappy(duration: 0.25)) { selection = item.id }
                } label: {
                    Text(item.title)
                        .font(selected ? FluentFont.bodyStrong : FluentFont.body)
                        .foregroundStyle(selected ? theme.textPrimary : theme.textSecondary)
                        .padding(.horizontal, 12)
                        .frame(minHeight: 40)
                        .overlay(alignment: .bottom) {
                            if selected {
                                Capsule().fill(theme.accent)
                                    .frame(width: 18, height: 3)
                                    .matchedGeometryEffect(id: "pill", in: pill)
                                    .offset(y: -2)
                            }
                        }
                }
                .buttonStyle(FluentButtonStyle(kind: .subtle, compact: true))
                .background(
                    GeometryReader { g in
                        Color.clear.onAppear { frames[item.id] = g.frame(in: .named(Fluent.rootSpace)) }
                            .onChange(of: g.frame(in: .named(Fluent.rootSpace))) { _, f in frames[item.id] = f }
                    }
                )
                .simultaneousGesture(LongPressGesture(minimumDuration: 0.45).onEnded { _ in
                    onLongPress?(item.id, frames[item.id] ?? .zero)
                })
            }
        }
    }
}
