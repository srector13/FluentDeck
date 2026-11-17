import SwiftUI

/// A module on the board: a widget on a translucent platter, as in Control Center. While
/// customizing, modules jiggle and carry a remove badge and an options menu, as widgets do on the
/// Home Screen.
struct WidgetCard: View {
    let tile: TileInstance
    let spec: PanelSpec
    let ctx: PanelContext
    var editing = false
    /// In the "Add widgets" picker: shown as it will look on the board, without the board's extras.
    var preview = false
    var onResize: (TileSize) -> Void = { _ in }
    var onRemove: () -> Void = {}

    @Environment(\.theme) private var theme

    private var available: Bool {
        guard let topic = spec.requires else { return true }
        return ctx.connection.hostProvides(topic)
    }

    private var hasDrawer: Bool {
        spec.drawer != nil && available && !preview && (spec.drawerSizes?.contains(tile.size) ?? true)
    }

    private var bare: Bool { spec.bare && available }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Metrics.panelRadius, style: .continuous)
        VStack(spacing: 0) {
            Group {
                if available {
                    spec.view(ctx)
                } else {
                    PanelEmptyState(symbol: "exclamationmark.triangle", text: "This PC doesn’t provide “\(spec.requires ?? "")”")
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            if hasDrawer, let drawer = spec.drawer {
                DrawerHandle(title: spec.title) {
                    ctx.overlays.openDrawer(title: spec.title) { drawer(ctx) }
                }
            }
        }
        .allowsHitTesting(!editing || spec.editsInPlace)
        .padding([.horizontal, .top], bare ? 0 : Metrics.cardPadding)
        .padding(.bottom, bare ? 0 : hasDrawer ? 4 : Metrics.cardPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background {
            if !bare {
                ZStack {
                    ModuleSurface()
                    if let background = spec.background, available { background(ctx).clipShape(shape) }
                }
            }
        }
        .contentShape(shape)
        .overlay(alignment: .topLeading) {
            if editing {
                Button(action: onRemove) {
                    Image(systemName: "minus")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.black)
                        .frame(width: 26, height: 26)
                        .background(Circle().fill(.white.opacity(0.92)))
                        .frame(width: Metrics.touchTarget, height: Metrics.touchTarget)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .offset(x: -14, y: -14)
                .accessibilityLabel("Remove \(spec.title)")
            }
        }
        .overlay(alignment: .topTrailing) {
            if editing {
                ActionMenu(items: menuItems) {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(theme.textPrimary)
                        .frame(width: 30, height: 30)
                        .background(Circle().fill(theme.controlSolidFill))
                        .frame(width: Metrics.touchTarget, height: Metrics.touchTarget)
                        .contentShape(Rectangle())
                }
                .offset(x: 6, y: -6)
                .accessibilityLabel("Options for \(spec.title)")
            }
        }
        .modifier(Jiggle(active: editing))
    }

    /// The grabber at the foot of a compact module. Tap it or flick it up for the widget's drawer.
    private struct DrawerHandle: View {
        let title: String
        let open: () -> Void
        @Environment(\.theme) private var theme

        var body: some View {
            Button(action: open) {
                Capsule()
                    .fill(theme.textTertiary)
                    .frame(width: 36, height: 5)
                    .frame(maxWidth: .infinity)
                    .frame(height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .simultaneousGesture(
                DragGesture(minimumDistance: 8).onEnded { drag in
                    if drag.translation.height < -12 { open() }
                }
            )
            .accessibilityLabel("More \(title) controls")
        }
    }

    /// The Home Screen's edit-mode wobble.
    private struct Jiggle: ViewModifier {
        let active: Bool
        @State private var tilted = false

        func body(content: Content) -> some View {
            content
                .rotationEffect(.degrees(active ? (tilted ? 0.5 : -0.5) : 0))
                .animation(active ? .easeInOut(duration: 0.13).repeatForever(autoreverses: true) : .easeOut(duration: 0.15), value: tilted)
                .animation(.easeOut(duration: 0.15), value: active)
                .onChange(of: active, initial: true) { _, on in tilted = on }
        }
    }

    private func menuItems() -> [ActionItem] {
        var items: [ActionItem] = [.header(spec.title)]
        if spec.sizes.count > 1 {
            items += spec.sizes.map { size in
                ActionItem.action(size.title, checked: size == tile.size) { onResize(size) }
            }
        }
        let extra = spec.menu(ctx)
        if !extra.isEmpty {
            items.append(.separator)
            items += extra
        }
        items.append(.separator)
        items.append(.action("Remove widget", symbol: "minus.circle", destructive: true) { onRemove() })
        return items
    }
}
