import SwiftUI
import UniformTypeIdentifiers

/// The boards, one screen each: swipe sideways between them, or pick one in the switcher at the
/// top. Each board is a Control Center-style grid of modules under a standard toolbar: the PC on
/// the left, the boards in the middle, and add, customize and more on the right.
struct DashboardView: View {
    @Environment(AppModel.self) private var app

    /// The app in front on the PC, which can bring up a board set up for it.
    private var foregroundApp: String? {
        app.connection.store.box("apps").decoded(AppsState.self)?.foreground?.exe
    }

    var body: some View {
        NavigationStack {
            BoardPager()
                .background { AmbientBackground() }
                .navigationBarTitleDisplayMode(.inline)
                .toolbarBackground(.hidden, for: .navigationBar)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) { HostMenu() }
                    ToolbarItem(placement: .principal) { BoardSwitcher() }
                    ToolbarItemGroup(placement: .topBarTrailing) {
                        if app.editing {
                            Button("Done") { withAnimation(.snappy) { app.editing = false } }
                                .fontWeight(.semibold)
                        } else {
                            Button { app.showWidgetPicker() } label: { Label("Add widgets", systemImage: "plus") }
                            Button { withAnimation(.snappy) { app.editing = true } } label: { Label("Customize", systemImage: "pencil") }
                            if let board = app.layout.selectedBoard { BoardMenu(board: board) }
                        }
                    }
                }
        }
        .onChange(of: foregroundApp, initial: true) { _, exe in app.foregroundAppChanged(exe) }
    }
}

/// Lays the boards side by side and follows a sideways swipe from one to the next, like Home
/// Screen pages. Only the board showing is drawn, plus its neighbours while a swipe is under way.
private struct BoardPager: View {
    @Environment(AppModel.self) private var app
    @State private var drag: CGFloat = 0
    @State private var horizontal: Bool?
    @State private var settling = false
    private let gap: CGFloat = 24

    var body: some View {
        let boards = app.layout.boards
        let index = app.layout.selectedIndex ?? 0
        GeometryReader { g in
            let width = g.size.width
            ZStack {
                ForEach(Array(boards.enumerated()), id: \.element.id) { i, board in
                    if i == index || (abs(i - index) == 1 && (drag != 0 || settling)) {
                        BoardView(board: board)
                            .frame(width: width, height: g.size.height)
                            .offset(x: CGFloat(i - index) * (width + gap) + drag)
                    }
                }
            }
            .frame(width: width, height: g.size.height)
            .contentShape(Rectangle())
            .simultaneousGesture(swipe(width: width, index: index, count: boards.count))
        }
    }

    private func swipe(width: CGFloat, index: Int, count: Int) -> some Gesture {
        DragGesture(minimumDistance: 18, coordinateSpace: .global)
            .onChanged { value in
                if horizontal == nil {
                    // A slider being dragged, or rearranging widgets, keeps the board still.
                    let sideways = abs(value.translation.width) > abs(value.translation.height) * 1.3
                    horizontal = sideways && !TouchArbiter.sliderActive && !app.editing && count > 1
                    if horizontal == true { TouchArbiter.swipeBegan() }
                }
                guard horizontal == true else { return }
                var dx = value.translation.width
                if (dx > 0 && index == 0) || (dx < 0 && index == count - 1) { dx *= 0.25 } // rubber band at the ends
                drag = dx
            }
            .onEnded { value in
                defer { horizontal = nil }
                guard horizontal == true else { return }
                TouchArbiter.swipeEnded()
                let moved = value.translation.width, flung = value.predictedEndTranslation.width
                var target = index
                if (moved < -width * 0.22 || flung < -width * 0.5), index < count - 1 { target = index + 1 }
                if (moved > width * 0.22 || flung > width * 0.5), index > 0 { target = index - 1 }
                settle(at: target, from: index, width: width)
            }
    }

    /// Slide the rest of the way, then make the new board the current one where it already sits.
    private func settle(at target: Int, from index: Int, width: CGFloat) {
        guard target != index, app.layout.boards.indices.contains(target) else {
            withAnimation(.snappy(duration: 0.25)) { drag = 0 }
            return
        }
        settling = true
        let id = app.layout.boards[target].id
        withAnimation(.snappy(duration: 0.3)) {
            drag = target > index ? -(width + gap) : width + gap
        } completion: {
            var still = Transaction()
            still.disablesAnimations = true
            withTransaction(still) {
                app.layout.selectedBoardID = id
                drag = 0
                settling = false
            }
        }
    }
}

/// Settles which gesture a touch belongs to between a board swipe and the controls on a board.
@MainActor
enum TouchArbiter {
    /// A slider is being dragged: a sideways drag is the slider's, not a swipe between boards.
    static var sliderActive = false
    private static var swipedAt: Date?
    private static var swiping = false

    static func swipeBegan() { swiping = true }
    static func swipeEnded() { swiping = false; swipedAt = .now }

    /// A board swipe is under way or just ended, so a key under the finger shouldn't fire.
    static var swipeInProgress: Bool {
        swiping || (swipedAt.map { Date.now.timeIntervalSince($0) < 0.35 } ?? false)
    }
}

/// The boards by name, the one showing on a lighter pill, like the iPadOS tab bar. Tap one to
/// go there.
private struct BoardSwitcher: View {
    @Environment(AppModel.self) private var app
    @Environment(\.theme) private var theme
    @Namespace private var pill

    var body: some View {
        let layout = app.layout
        let current = layout.selectedBoard?.id
        HStack(spacing: 2) {
            ForEach(layout.boards) { board in
                let on = board.id == current
                Button {
                    withAnimation(.snappy(duration: 0.3)) { layout.selectedBoardID = board.id }
                } label: {
                    Text(board.name)
                        .font(.system(size: 16, weight: on ? .semibold : .medium))
                        .foregroundStyle(on ? theme.accent : theme.textPrimary)
                        .lineLimit(1)
                        .padding(.horizontal, 16)
                        .frame(height: 36)
                        .background {
                            if on {
                                Capsule().fill(theme.controlFillSecondary).matchedGeometryEffect(id: "pill", in: pill)
                            }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(board.name)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .padding(3)
        .modifier(SwitcherSurface())
    }
}

/// iPadOS 26 puts toolbar items on glass itself; before that the switcher brings its own.
private struct SwitcherSurface: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content
        } else {
            content.background(Capsule().fill(.ultraThinMaterial))
        }
    }
}

/// One board: its grid of modules.
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
                let spans = board.tiles.map(\.size)
                let fit = DashboardGrid.fit(geo.size, spans: spans)
                let height = DashboardGrid(columns: fit.columns, rowHeight: fit.rowHeight).place(width: geo.size.width, spans: spans).height
                if board.tiles.isEmpty {
                    EmptyBoard { app.showWidgetPicker() }
                        .padding(.top, 80)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                } else if height > geo.size.height + 1 {
                    // Only a board with more rows than the screen scrolls: a scroll view would
                    // otherwise claim sideways drags meant for swiping between boards.
                    ScrollView { grid(fit) }
                        .scrollIndicators(.hidden)
                        .scrollClipDisabled()
                } else {
                    grid(fit).frame(maxHeight: .infinity, alignment: .top)
                }
            }
        }
        .padding(.horizontal, Metrics.margin)
        .padding(.top, 6)
        .padding(.bottom, 12)
        .animation(.snappy, value: app.connection.phase)
    }

    private func grid(_ fit: (columns: Int, rowHeight: CGFloat)) -> some View {
        DashboardGrid(columns: fit.columns, rowHeight: fit.rowHeight) {
            ForEach(board.tiles) { tile in
                tileView(tile)
                    .tileSize(tile.size)
            }
        }
        .animation(.snappy(duration: 0.3), value: board.tiles)
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
                Button { app.promptRenamePC() } label: { Label("Rename…", systemImage: "pencil") }
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
                if app.connection.hostProvides("apps") {
                    Button { app.promptBoardApps(board) } label: {
                        Label(board.apps?.isEmpty == false ? "Show for Apps (\(board.apps!.count))…" : "Show for Apps…", systemImage: "macwindow.badge.plus")
                    }
                }
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
                Button { app.showSettings() } label: { Label("Settings…", systemImage: "gearshape") }
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
