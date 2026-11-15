import SwiftUI

/// The chrome around every widget: Windows 11 widget header (icon + title + ⋯ menu) on a card.
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
        let shape = RoundedRectangle(cornerRadius: Fluent.overlayRadius, style: .circular)
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: spec.symbol)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(theme.accent)
                Text(spec.title)
                    .font(FluentFont.caption)
                    .foregroundStyle(theme.textSecondary)
                    .lineLimit(1)
                Spacer(minLength: 0)
                if !preview {
                    FlyoutButton(width: 240, items: menuItems) {
                        Image(systemName: "ellipsis")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(theme.textSecondary)
                            .frame(width: 30, height: 24)
                    }
                    .padding(.trailing, -6)
                    .accessibilityLabel("More options for \(spec.title)")
                }
            }
            .frame(height: 24)

            Group {
                if available {
                    spec.view(ctx)
                } else {
                    PanelEmptyState(symbol: "exclamationmark.triangle", text: "This PC doesn’t provide “\(spec.requires ?? "")”")
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .allowsHitTesting(!editing)
        }
        .padding(Fluent.cardPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background {
            ZStack {
                shape.fill(theme.cardFill)
                if let background = spec.background, available { background(ctx).clipShape(shape) }
            }
        }
        .overlay {
            if editing {
                shape.strokeBorder(theme.accent, style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
            } else {
                shape.strokeBorder(theme.cardStroke, lineWidth: 1)
            }
        }
        .clipShape(shape)
        .contentShape(shape)
    }

    private func menuItems() -> [FlyoutItem] {
        var items: [FlyoutItem] = []
        if spec.sizes.count > 1 {
            items += spec.sizes.map { size in
                FlyoutItem.action(size.title, checked: size == tile.size) { onResize(size) }
            }
        }
        let extra = spec.menu(ctx)
        if !extra.isEmpty {
            if !items.isEmpty { items.append(.separator) }
            items += extra
        }
        if !items.isEmpty { items.append(.separator) }
        items.append(.action("Unpin widget", symbol: "pin.slash", destructive: true) { onRemove() })
        return items
    }
}
