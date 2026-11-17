import SwiftUI

/// The "Add widgets" sheet: the list on the left, a live preview and the size choice on the right.
struct WidgetPicker: View {
    @Environment(AppModel.self) private var app
    @Environment(\.theme) private var theme
    @State private var selected = "media.nowPlaying"
    @State private var size: TileSize = .tall

    private var spec: PanelSpec? { PanelCatalog.spec(for: selected) }

    var body: some View {
        DialogSheet(title: "Add widgets", fills: true,
                    cancel: DialogAction("Cancel") { app.overlays.dismissDialog() },
                    confirm: DialogAction("Add", enabled: spec.map(isAvailable) ?? false) {
                        if let spec { withAnimation(.snappy) { app.layout.add(spec, size: size) } }
                        app.overlays.dismissDialog()
                    }) {
            HStack(alignment: .top, spacing: 28) {
                list
                    .frame(width: 230)
                if let spec { detail(spec) }
            }
            .frame(maxHeight: .infinity)
        }
    }

    private var list: some View {
        ScrollView {
            VStack(spacing: 2) {
                ForEach(PanelCatalog.all) { s in
                    let isSelected = s.kind == selected
                    Button {
                        selected = s.kind
                        size = s.defaultSize
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: s.symbol).font(.system(size: 16)).frame(width: 22)
                                .foregroundStyle(isAvailable(s) ? theme.accent : theme.textDisabled)
                            Text(s.title).font(AppFont.body)
                            Spacer(minLength: 0)
                        }
                        .foregroundStyle(isAvailable(s) ? theme.textPrimary : theme.textDisabled)
                        .padding(.horizontal, 12)
                        .frame(height: 44)
                        // The selected row is a filled capsule, as in an iPadOS sidebar.
                        .background(Capsule().fill(isSelected ? theme.controlFill : .clear))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func detail(_ spec: PanelSpec) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(spec.title).font(AppFont.bodyLarge.weight(.semibold)).foregroundStyle(theme.textPrimary)
            Text(spec.summary).font(AppFont.body).foregroundStyle(theme.textSecondary).fixedSize(horizontal: false, vertical: true)
            if spec.sizes.count > 1 {
                SegmentedBar(items: spec.sizes.map { SegmentedBar<TileSize>.Item(id: $0, title: $0.title) },
                            selection: Binding(get: { size }, set: { if let s = $0 { size = s } }))
            }
            if !isAvailable(spec) {
                Banner(severity: .warning, title: "Not available on this PC",
                        message: "Update FluentDeck on the PC to get the “\(spec.requires ?? "")” panel.")
            }
            preview(spec)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    /// A live, scaled-down render of the real widget at the chosen size.
    private func preview(_ spec: PanelSpec) -> some View {
        GeometryReader { g in
            let cell: CGFloat = 150, gap: CGFloat = 12
            let span = size.span
            let natural = CGSize(width: CGFloat(span.columns) * cell + CGFloat(span.columns - 1) * gap,
                                 height: CGFloat(span.rows) * cell + CGFloat(span.rows - 1) * gap)
            let scale = min(1, g.size.width / natural.width, g.size.height / natural.height)
            let tile = TileInstance(kind: spec.kind, size: size, config: spec.defaultConfig)
            WidgetCard(tile: tile, spec: spec, ctx: app.context(for: tile, preview: true), preview: true)
                .frame(width: natural.width, height: natural.height)
                .allowsHitTesting(false)
                .scaleEffect(scale)
                .frame(width: g.size.width, height: g.size.height)
        }
    }

    private func isAvailable(_ spec: PanelSpec) -> Bool {
        spec.requires.map(app.connection.hostProvides) ?? true
    }
}
