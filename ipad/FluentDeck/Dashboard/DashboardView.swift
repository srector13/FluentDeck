import SwiftUI
import UniformTypeIdentifiers

/// The widget board: board tabs on top, the grid of widgets, and the status line underneath.
/// Everything shares one left and right margin, and nothing is boxed in.
struct DashboardView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.fluent) private var theme

    var body: some View {
        let layout = app.layout
        VStack(spacing: 14) {
            BoardBar()

            if case .reconnecting = app.connection.phase {
                InfoBar(severity: .warning, title: "Reconnecting to \(app.connection.hostName)…", busy: true)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }

            GeometryReader { geo in
                let fit = DashboardGrid.fit(geo.size)
                ScrollView {
                    if let board = layout.selectedBoard {
                        if board.tiles.isEmpty {
                            EmptyBoard { app.showWidgetPicker() }
                                .padding(.top, 80)
                        } else {
                            DashboardGrid(columns: fit.columns, rowHeight: fit.rowHeight) {
                                ForEach(board.tiles) { tile in
                                    tileView(tile)
                                        .tileSize(tile.size)
                                }
                            }
                            .animation(.snappy(duration: 0.3), value: board.tiles)
                        }
                    }
                }
                .scrollIndicators(.hidden)
                .scrollBounceBehavior(.basedOnSize)
                .scrollClipDisabled() // glows spill past the grid's edge
            }

            CommandBar()
        }
        .padding(.horizontal, Fluent.margin)
        .padding(.top, 8)
        .padding(.bottom, 8)
        .animation(.snappy, value: app.connection.phase)
    }

    @ViewBuilder
    private func tileView(_ tile: TileInstance) -> some View {
        if let spec = PanelCatalog.spec(for: tile.kind) {
            let card = WidgetCard(
                tile: tile, spec: spec, ctx: app.context(for: tile), editing: app.editing,
                onResize: { size in withAnimation(.snappy) { app.layout.resize(tile.id, to: size) } },
                onRemove: { withAnimation(.snappy) { app.layout.remove(tile.id) } })
            if app.editing {
                card
                    .draggable(tile.id.uuidString) {
                        Image(systemName: spec.symbol)
                            .font(.system(size: 28))
                            .padding(24)
                            .background(RoundedRectangle(cornerRadius: 8).fill(theme.accent))
                            .foregroundStyle(theme.textOnAccent)
                    }
                    .dropDestination(for: String.self) { items, _ in
                        guard let first = items.first, let id = UUID(uuidString: first) else { return false }
                        withAnimation(.snappy) { app.layout.move(id, to: tile.id) }
                        return true
                    }
            } else {
                card
            }
        } else {
            // A widget from a newer app version or a removed panel — keep the slot removable.
            Text("Unknown widget “\(tile.kind)”")
                .font(FluentFont.caption)
                .foregroundStyle(theme.textTertiary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .fluentCard()
                .onLongPressGesture { app.layout.remove(tile.id) }
        }
    }
}

private struct EmptyBoard: View {
    let add: () -> Void
    @Environment(\.fluent) private var theme

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "square.grid.2x2").font(.system(size: 40, weight: .light)).foregroundStyle(theme.textTertiary)
            Text("This board is empty").font(FluentFont.subtitle).foregroundStyle(theme.textPrimary)
            Text("Pin widgets to build your controller.").font(FluentFont.body).foregroundStyle(theme.textSecondary)
            Button(action: add) { Label("Add widgets", systemImage: "plus") }
                .buttonStyle(FluentButtonStyle(kind: .accent))
                .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
    }
}

/// Board tabs (like Stream Deck profiles) and the PC this iPad is controlling.
private struct BoardBar: View {
    @Environment(AppModel.self) private var app
    @Environment(\.fluent) private var theme

    var body: some View {
        let layout = app.layout
        HStack(spacing: 4) {
            SelectorBar(
                items: layout.boards.map { SelectorBar<UUID>.Item(id: $0.id, title: $0.name) },
                selection: Binding(get: { layout.selectedBoardID }, set: { layout.selectedBoardID = $0 }),
                onLongPress: { id, frame in boardMenu(id, frame) })
                .padding(.leading, -20) // the first tab's label, not its touch target, starts on the margin
            FluentIconButton(symbol: "plus", size: 14, tint: theme.textSecondary, label: "New board") {
                withAnimation(.snappy) { layout.addBoard() }
            }
            Spacer(minLength: 8)
            Text(app.connection.hostName).font(FluentFont.body).foregroundStyle(theme.textPrimary).lineLimit(1)
            InfoBadge(color: app.connection.isConnected ? theme.success : theme.caution)
                .padding(.leading, 4)
        }
        .frame(height: 44)
    }

    private func boardMenu(_ id: UUID, _ frame: CGRect) {
        let layout = app.layout
        guard let board = layout.boards.first(where: { $0.id == id }) else { return }
        app.overlays.showFlyout(anchor: frame, items: [
            .action("Rename…", symbol: "pencil") { app.promptRename(board) },
            .action("Move left", symbol: "arrow.left") { withAnimation(.snappy) { layout.moveBoard(id, by: -1) } },
            .action("Move right", symbol: "arrow.right") { withAnimation(.snappy) { layout.moveBoard(id, by: 1) } },
            .separator,
            .action("Delete board", symbol: "trash", destructive: true) { withAnimation(.snappy) { layout.deleteBoard(id) } },
        ], width: 220)
    }
}

/// The quick settings footer, without the strip: the PC's battery and load on the left, board
/// actions on the right.
private struct CommandBar: View {
    @Environment(AppModel.self) private var app
    @Environment(\.fluent) private var theme

    var body: some View {
        HStack(spacing: 0) {
            SystemStatus()
            Spacer(minLength: 8)
            if app.editing {
                Button { withAnimation(.snappy) { app.editing = false } } label: { Text("Done") }
                    .buttonStyle(FluentButtonStyle(kind: .accent))
                    .padding(.trailing, 8)
            } else {
                FluentIconButton(symbol: "plus", label: "Add widgets") { app.showWidgetPicker() }
                FluentIconButton(symbol: "pencil", label: "Customize") { withAnimation(.snappy) { app.editing = true } }
            }
            FlyoutButton(width: 280, items: settingsItems) {
                Image(systemName: "gearshape").font(.system(size: 17)).frame(width: 40, height: 40)
            }
            .accessibilityLabel("Settings")
        }
        .padding(.trailing, -16) // the gear's glyph, not its touch target, meets the margin
        .frame(height: 44)
    }

    private func settingsItems() -> [FlyoutItem] {
        [
            .action("Keep screen awake", checked: app.keepAwake) { app.keepAwake.toggle() },
            .separator,
            .action("Switch PC…", symbol: "arrow.left.arrow.right") { app.switchHost() },
            .action("Forget \(app.connection.hostName)", symbol: "xmark.circle", destructive: true) { app.forgetCurrentHost() },
        ]
    }
}

/// Battery, CPU and memory of the PC, when it reports them.
private struct SystemStatus: View {
    @Environment(AppModel.self) private var app
    @Environment(\.fluent) private var theme

    var body: some View {
        if let s = app.connection.store.box("system").decoded(SystemState.self) {
            HStack(spacing: 22) {
                if let b = s.battery {
                    HStack(spacing: 7) {
                        Image(systemName: Self.batterySymbol(b)).font(.system(size: 17))
                        Text("\(b.percent)%")
                    }
                    .foregroundStyle(b.percent <= 15 && !b.charging ? theme.critical : theme.textPrimary)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(b.charging ? "Battery \(b.percent) percent, charging" : "Battery \(b.percent) percent")
                }
                stat("CPU", "\(Int(s.cpu.rounded()))%")
                stat("Memory", String(format: "%.1f of %.0f GB", s.memoryUsedGb, s.memoryTotalGb))
            }
            .font(FluentFont.caption)
            .monospacedDigit()
            .lineLimit(1)
        }
    }

    private func stat(_ title: String, _ value: String) -> some View {
        HStack(spacing: 6) {
            Text(title).foregroundStyle(theme.textSecondary)
            Text(value).foregroundStyle(theme.textPrimary)
        }
    }

    static func batterySymbol(_ b: BatteryState) -> String {
        if b.charging { return "battery.100percent.bolt" }
        if b.percent < 13 { return "battery.0percent" }
        if b.percent < 38 { return "battery.25percent" }
        if b.percent < 63 { return "battery.50percent" }
        if b.percent < 88 { return "battery.75percent" }
        return "battery.100percent"
    }
}

/// The app's mark: an accent tile with a 3×2 grid of deck keys (matches the PC tray icon).
struct AppGlyph: View {
    var size: CGFloat
    @Environment(\.fluent) private var theme

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.24, style: .continuous)
            .fill(theme.palette.base)
            .frame(width: size, height: size)
            .overlay {
                Grid(horizontalSpacing: size * 0.07, verticalSpacing: size * 0.07) {
                    GridRow { key(lit: true); key(lit: false); key(lit: false) }
                    GridRow { key(lit: false); key(lit: false); key(lit: false) }
                }
            }
    }

    private func key(lit: Bool) -> some View {
        RoundedRectangle(cornerRadius: size * 0.05)
            .fill(.white.opacity(lit ? 1 : 0.7))
            .frame(width: size * 0.18, height: size * 0.18)
    }
}
