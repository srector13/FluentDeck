import SwiftUI
import UniformTypeIdentifiers

/// The widget board: title bar, board tabs, and the tile grid.
struct DashboardView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.fluent) private var theme

    var body: some View {
        let layout = app.layout
        VStack(spacing: 0) {
            TitleBar()
                .padding(.horizontal, 20)
                .padding(.top, 8)

            HStack(spacing: 4) {
                SelectorBar(
                    items: layout.boards.map { SelectorBar<UUID>.Item(id: $0.id, title: $0.name) },
                    selection: Binding(get: { layout.selectedBoardID }, set: { layout.selectedBoardID = $0 }),
                    onLongPress: { id, frame in boardMenu(id, frame) })
                FluentIconButton(symbol: "plus", size: 14, tint: theme.textSecondary, label: "New board") {
                    withAnimation(.snappy) { layout.addBoard() }
                }
                Spacer()
            }
            .padding(.horizontal, 12)

            if case .reconnecting = app.connection.phase {
                InfoBar(severity: .warning, title: "Reconnecting to \(app.connection.hostName)…", busy: true)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }

            ScrollView {
                if let board = layout.selectedBoard {
                    if board.tiles.isEmpty {
                        EmptyBoard { app.showWidgetPicker() }
                            .padding(.top, 80)
                    } else {
                        DashboardGrid {
                            ForEach(board.tiles) { tile in
                                tileView(tile)
                                    .tileSize(tile.size)
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                        .animation(.snappy(duration: 0.3), value: board.tiles)
                    }
                }
            }
            .scrollIndicators(.hidden)
        }
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

/// App title bar: identity, connection state, and the board actions.
struct TitleBar: View {
    @Environment(AppModel.self) private var app
    @Environment(\.fluent) private var theme

    var body: some View {
        HStack(spacing: 10) {
            AppGlyph(size: 22)
            Text("FluentDeck").font(FluentFont.caption.weight(.semibold)).foregroundStyle(theme.textPrimary)
            Text(app.connection.hostName).font(FluentFont.caption).foregroundStyle(theme.textSecondary).lineLimit(1)
            InfoBadge(color: app.connection.isConnected ? theme.success : theme.caution)
            Spacer()
            if app.editing {
                Button { withAnimation(.snappy) { app.editing = false } } label: { Text("Done") }
                    .buttonStyle(FluentButtonStyle(kind: .accent, compact: true))
            } else {
                Button { app.showWidgetPicker() } label: { Label("Add widgets", systemImage: "plus") }
                    .buttonStyle(FluentButtonStyle(kind: .subtle, compact: true))
                Button { withAnimation(.snappy) { app.editing = true } } label: { Label("Customize", systemImage: "square.and.pencil") }
                    .buttonStyle(FluentButtonStyle(kind: .subtle, compact: true))
            }
            FlyoutButton(width: 280, items: settingsItems) {
                Image(systemName: "gearshape").font(.system(size: 16)).frame(width: 30, height: 30)
            }
            .accessibilityLabel("Settings")
        }
        .frame(height: 48)
    }

    private func settingsItems() -> [FlyoutItem] {
        [
            .header("Theme"),
            .action("Match my PC", checked: app.themeMode == .followPC) { app.themeMode = .followPC },
            .action("Light", checked: app.themeMode == .light) { app.themeMode = .light },
            .action("Dark", checked: app.themeMode == .dark) { app.themeMode = .dark },
            .separator,
            .action("Keep screen awake", checked: app.keepAwake) { app.keepAwake.toggle() },
            .separator,
            .action("Switch PC…", symbol: "arrow.left.arrow.right") { app.switchHost() },
            .action("Forget \(app.connection.hostName)", symbol: "xmark.circle", destructive: true) { app.forgetCurrentHost() },
        ]
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
