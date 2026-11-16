import SwiftUI

/// The panel around every widget: a quick settings flyout surface with a hairline border.
/// There is no header. While customizing, each panel shows a dashed outline and an options button.
struct WidgetCard: View {
    let tile: TileInstance
    let spec: PanelSpec
    let ctx: PanelContext
    var editing = false
    var preview = false
    var onResize: (TileSize) -> Void = { _ in }
    var onRemove: () -> Void = {}

    @Environment(\.fluent) private var theme

    private var available: Bool {
        guard let topic = spec.requires else { return true }
        return ctx.connection.hostProvides(topic)
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Fluent.panelRadius, style: .continuous)
        let bare = spec.chromeless && !preview
        Group {
            if available {
                spec.view(ctx)
            } else {
                PanelEmptyState(symbol: "exclamationmark.triangle", text: "This PC doesn’t provide “\(spec.requires ?? "")”")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .allowsHitTesting(!editing)
        .padding(bare ? 6 : Fluent.cardPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background {
            if !bare {
                ZStack {
                    shape.fill(theme.cardFill)
                    if let background = spec.background, available { background(ctx).clipShape(shape) }
                }
            }
        }
        .overlay {
            if editing {
                shape.strokeBorder(theme.accent, style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
            } else if !bare {
                shape.strokeBorder(theme.cardStroke, lineWidth: 1)
            }
        }
        .clipShape(shape)
        .contentShape(shape)
        .overlay(alignment: .topTrailing) {
            if editing {
                FlyoutButton(width: 240, items: menuItems) {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(theme.textPrimary)
                        .frame(width: 28, height: 28)
                }
                .background(Circle().fill(theme.controlSolidFill))
                .padding(8)
                .accessibilityLabel("Options for \(spec.title)")
            }
        }
    }

    private func menuItems() -> [FlyoutItem] {
        var items: [FlyoutItem] = [.header(spec.title)]
        if spec.sizes.count > 1 {
            items += spec.sizes.map { size in
                FlyoutItem.action(size.title, checked: size == tile.size) { onResize(size) }
            }
        }
        let extra = spec.menu(ctx)
        if !extra.isEmpty {
            items.append(.separator)
            items += extra
        }
        items.append(.separator)
        items.append(.action("Unpin widget", symbol: "pin.slash", destructive: true) { onRemove() })
        return items
    }
}
