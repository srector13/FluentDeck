import SwiftUI

/// Places a widget on the board. There is no panel: a widget's controls sit straight on the black,
/// and the space around them is what sets it apart. While customizing, each widget gets a soft
/// backdrop, a dashed outline and an options button.
struct WidgetCard: View {
    let tile: TileInstance
    let spec: PanelSpec
    let ctx: PanelContext
    var editing = false
    /// In the "Add widgets" picker: shown on a black swatch, as it will look on the board.
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
        // The outline sits in the gutter, so it never touches the widget's own edges.
        let outset = -Fluent.gutter * 0.4
        Group {
            if available {
                spec.view(ctx)
            } else {
                PanelEmptyState(symbol: "exclamationmark.triangle", text: "This PC doesn’t provide “\(spec.requires ?? "")”")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .allowsHitTesting(!editing)
        .background {
            if let background = spec.background, available { background(ctx) }
        }
        .padding(preview ? Fluent.cardPadding : 0)
        .background {
            if preview {
                shape.fill(Color.black)
            } else if editing {
                shape.fill(theme.controlFillTertiary).padding(outset)
            }
        }
        .overlay {
            if editing {
                shape.strokeBorder(theme.accent.opacity(0.7), style: StrokeStyle(lineWidth: 1.5, lineCap: .round, dash: [2, 7]))
                    .padding(outset)
            }
        }
        .contentShape(Rectangle())
        .overlay(alignment: .topTrailing) {
            if editing {
                FlyoutButton(width: 240, items: menuItems) {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(theme.textPrimary)
                        .frame(width: 28, height: 28)
                }
                .background(Circle().fill(theme.controlSolidFill))
                .offset(x: -outset * 0.4, y: outset * 0.4)
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
