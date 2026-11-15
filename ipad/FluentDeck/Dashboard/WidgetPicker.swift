import SwiftUI

/// The Windows 11 "Pin widgets" dialog: list on the left, live preview and size choice on the right.
struct WidgetPicker: View {
    @Environment(AppModel.self) private var app
    @Environment(\.fluent) private var theme
    @State private var selected = "media.nowPlaying"
    @State private var size: TileSize = .large

    private var spec: PanelSpec? { PanelCatalog.spec(for: selected) }

    var body: some View {
        ContentDialog(title: "Add widgets", maxWidth: 820) {
            HStack(alignment: .top, spacing: 20) {
                list
                    .frame(width: 230)
                Rectangle().fill(theme.divider).frame(width: 1)
                if let spec { detail(spec) }
            }
            .frame(height: 440)
        } footer: {
            DialogButton(title: "Pin", accent: true, enabled: spec.map(isAvailable) ?? false) {
                if let spec { withAnimation(.snappy) { app.layout.add(spec, size: size) } }
                app.overlays.dismissDialog()
            }
            DialogButton(title: "Cancel") { app.overlays.dismissDialog() }
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
                            Text(s.title).font(FluentFont.body)
                            Spacer(minLength: 0)
                        }
                        .foregroundStyle(isAvailable(s) ? theme.textPrimary : theme.textDisabled)
                        .padding(.horizontal, 12)
                        .frame(height: 44)
                        .background(RoundedRectangle(cornerRadius: Fluent.controlRadius).fill(isSelected ? theme.subtleFillSecondary : .clear))
                        .overlay(alignment: .leading) {
                            // NavigationView selection pill
                            if isSelected { Capsule().fill(theme.accent).frame(width: 3, height: 16) }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func detail(_ spec: PanelSpec) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(spec.title).font(FluentFont.bodyLarge.weight(.semibold)).foregroundStyle(theme.textPrimary)
            Text(spec.summary).font(FluentFont.body).foregroundStyle(theme.textSecondary).fixedSize(horizontal: false, vertical: true)
            if spec.sizes.count > 1 {
                SelectorBar(items: spec.sizes.map { SelectorBar<TileSize>.Item(id: $0, title: $0.title) },
                            selection: Binding(get: { size }, set: { if let s = $0 { size = s } }))
                    .padding(.leading, -12)
            }
            if !isAvailable(spec) {
                InfoBar(severity: .warning, title: "Not available on this PC",
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
