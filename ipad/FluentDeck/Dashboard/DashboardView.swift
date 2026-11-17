import SwiftUI
import UniformTypeIdentifiers

/// The boards, in the system tab bar. Each board is a Control Center-style grid of modules under
/// a standard toolbar: the PC on the left; add, customize and more on the right.
struct DashboardView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        let layout = app.layout
        TabView(selection: Binding(
            get: { layout.selectedBoardID ?? layout.boards.first?.id ?? UUID() },
            set: { layout.selectedBoardID = $0 })) {
            ForEach(layout.boards) { board in
                NavigationStack {
                    BoardView(board: board)
                }
                .tabItem { Label(board.name, systemImage: board.symbol ?? "square.grid.2x2.fill") }
                .tag(board.id)
            }
        }
    }
}

/// One board: its grid of modules and its toolbar.
private struct BoardView: View {
    let board: Board
    @Environment(AppModel.self) private var app
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(spacing: 10) {
            if case .reconnecting = app.connection.phase {
                Banner(severity: .warning, title: "Reconnecting to \(app.connection.hostName)…", busy: true)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }

            GeometryReader { geo in
                let fit = DashboardGrid.fit(geo.size, spans: board.tiles.map(\.size))
                ScrollView {
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
                .scrollIndicators(.hidden)
                .scrollBounceBehavior(.basedOnSize)
                .scrollClipDisabled()
            }
        }
        .padding(.horizontal, Metrics.margin)
        .padding(.top, 6)
        .padding(.bottom, 12)
        .background { AmbientBackground() }
        .animation(.snappy, value: app.connection.phase)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) { HostMenu() }
            ToolbarItemGroup(placement: .topBarTrailing) {
                if app.editing {
                    Button("Done") { withAnimation(.snappy) { app.editing = false } }
                        .fontWeight(.semibold)
                } else {
                    Button { app.showWidgetPicker() } label: { Label("Add widgets", systemImage: "plus") }
                    Button { withAnimation(.snappy) { app.editing = true } } label: { Label("Customize", systemImage: "pencil") }
                    BoardMenu(board: board)
                }
            }
        }
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
                            .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(theme.accent))
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
                .font(AppFont.caption)
                .foregroundStyle(theme.textTertiary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .platter()
                .onLongPressGesture { app.layout.remove(tile.id) }
        }
    }
}

private struct EmptyBoard: View {
    let add: () -> Void
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "square.grid.2x2").font(.system(size: 40, weight: .light)).foregroundStyle(theme.textTertiary)
            Text("This board is empty").font(AppFont.subtitle).foregroundStyle(theme.textPrimary)
            Text("Add widgets to build your controller.").font(AppFont.body).foregroundStyle(theme.textSecondary)
            Button(action: add) { Label("Add widgets", systemImage: "plus") }
                .buttonStyle(PillButtonStyle(kind: .accent))
                .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
    }
}

/// The PC this iPad is controlling: its name and connection state, with the connection's actions.
private struct HostMenu: View {
    @Environment(AppModel.self) private var app
    @Environment(\.theme) private var theme

    var body: some View {
        Menu {
            Section(status) {
                Button { app.switchHost() } label: { Label("Switch PC…", systemImage: "arrow.left.arrow.right") }
                Button(role: .destructive) { app.forgetCurrentHost() } label: {
                    Label("Forget \(app.connection.hostName)", systemImage: "xmark.circle")
                }
            }
        } label: {
            HStack(spacing: 7) {
                StatusDot(color: app.connection.isConnected ? theme.success : theme.caution)
                Text(app.connection.hostName)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(theme.textPrimary)
                    .lineLimit(1)
            }
        }
        .accessibilityLabel("\(app.connection.hostName), \(app.connection.isConnected ? "connected" : "reconnecting")")
    }

    /// The PC's battery and load, when it reports them.
    private var status: String {
        guard let s = app.connection.store.box("system").decoded(SystemState.self) else {
            return app.connection.isConnected ? "Connected" : "Reconnecting…"
        }
        var parts = ["CPU \(Int(s.cpu.rounded()))%", String(format: "Memory %.1f of %.0f GB", s.memoryUsedGb, s.memoryTotalGb)]
        if let b = s.battery { parts.append("Battery \(b.percent)%\(b.charging ? ", charging" : "")") }
        return parts.joined(separator: " · ")
    }
}

/// Board actions and app settings, under the toolbar's "more" button.
private struct BoardMenu: View {
    let board: Board
    @Environment(AppModel.self) private var app

    var body: some View {
        let layout = app.layout
        Menu {
            Section("This board") {
                Button { app.promptRename(board) } label: { Label("Rename…", systemImage: "pencil") }
                Button { withAnimation(.snappy) { layout.moveBoard(board.id, by: -1) } } label: { Label("Move left", systemImage: "arrow.left") }
                Button { withAnimation(.snappy) { layout.moveBoard(board.id, by: 1) } } label: { Label("Move right", systemImage: "arrow.right") }
                if layout.boards.count > 1 {
                    Button(role: .destructive) { withAnimation(.snappy) { layout.deleteBoard(board.id) } } label: {
                        Label("Delete board", systemImage: "trash")
                    }
                }
            }
            Section {
                Button { withAnimation(.snappy) { layout.addBoard() } } label: { Label("New board", systemImage: "plus.rectangle.on.rectangle") }
            }
            Section {
                Toggle("Keep screen awake", isOn: Binding(get: { app.keepAwake }, set: { app.keepAwake = $0 }))
            }
        } label: {
            Label("More", systemImage: "ellipsis.circle")
        }
    }
}

/// The app's mark: a tinted tile with a 3×2 grid of deck keys (matches the PC tray icon).
struct AppGlyph: View {
    var size: CGFloat
    @Environment(\.theme) private var theme

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.24, style: .continuous)
            .fill(theme.accent)
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
