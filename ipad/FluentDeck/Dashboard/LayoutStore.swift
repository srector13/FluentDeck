import Foundation
import Observation

/// A board is one page of widgets (like Stream Deck profiles). Boards are tabs in the SegmentedBar.
struct Board: Codable, Identifiable, Hashable {
    var id = UUID()
    var name: String
    var tiles: [TileInstance]
    /// SF Symbol shown with the board's name in the tab bar.
    var symbol: String?
    /// Apps on the PC (lower-case exe names) that bring this board up when they come to the front.
    var apps: [String]?
}

/// Persists boards and widget placement in UserDefaults.
@MainActor
@Observable
final class LayoutStore {
    var boards: [Board] { didSet { save() } }
    var selectedBoardID: UUID? { didSet { save() } }

    nonisolated static let storageKey = "fluentdeck.layout.v2"
    private let key = LayoutStore.storageKey

    private struct Snapshot: Codable {
        var boards: [Board]
        var selected: UUID?
    }

    init() {
        if let data = UserDefaults.standard.data(forKey: key),
           let snap = try? JSONDecoder().decode(Snapshot.self, from: data), !snap.boards.isEmpty {
            boards = snap.boards
            selectedBoardID = snap.selected ?? snap.boards.first?.id
        } else {
            // Each fills a 6 × 4 landscape board exactly (see DashboardGrid.fit).
            let home = Board(name: "Home", tiles: [
                TileInstance(kind: NowPlayingPanel.spec.kind, size: .tall),
                TileInstance(kind: DeckPanel.spec.kind, size: .huge, config: ["page": "main"]),
                TileInstance(kind: ClockPanel.spec.kind, size: .medium),
                TileInstance(kind: VolumeMixerPanel.spec.kind, size: .medium),
                TileInstance(kind: CalendarPanel.spec.kind, size: .medium),
            ], symbol: "house.fill")
            let dev = Board(name: "Dev", tiles: [
                TileInstance(kind: DeckPanel.spec.kind, size: .huge, config: ["page": "dev"]),
                TileInstance(kind: VolumeMixerPanel.spec.kind, size: .large),
                TileInstance(kind: NowPlayingPanel.spec.kind, size: .medium),
                TileInstance(kind: DesktopsPanel.spec.kind, size: .medium),
                TileInstance(kind: RemindersPanel.spec.kind, size: .medium),
                TileInstance(kind: SystemPanel.spec.kind, size: .medium),
            ], symbol: "hammer.fill")
            let desk = Board(name: "Desk", tiles: [
                TileInstance(kind: TimerPanel.spec.kind, size: .large, config: ["minutes": "25"]),
                TileInstance(kind: WeatherPanel.spec.kind, size: .large),
                TileInstance(kind: NetworkPanel.spec.kind, size: .large),
                TileInstance(kind: ClipboardPanel.spec.kind, size: .medium),
                TileInstance(kind: DesktopsPanel.spec.kind, size: .medium),
                TileInstance(kind: ClockPanel.spec.kind, size: .medium),
                TileInstance(kind: RemindersPanel.spec.kind, size: .medium),
                TileInstance(kind: CalendarPanel.spec.kind, size: .medium),
                TileInstance(kind: SystemPanel.spec.kind, size: .medium),
            ], symbol: "sun.max.fill")
            boards = [home, dev, desk]
            selectedBoardID = home.id
        }
    }

    private func save() {
        let snap = Snapshot(boards: boards, selected: selectedBoardID)
        if let data = try? JSONEncoder().encode(snap) { UserDefaults.standard.set(data, forKey: key) }
    }

    var selectedIndex: Int? { boards.firstIndex { $0.id == selectedBoardID } ?? (boards.isEmpty ? nil : 0) }
    var selectedBoard: Board? { selectedIndex.map { boards[$0] } }

    // MARK: tiles (on the selected board)

    func add(_ spec: PanelSpec, size: TileSize) {
        guard let b = selectedIndex else { return }
        boards[b].tiles.append(TileInstance(kind: spec.kind, size: size, config: spec.defaultConfig))
    }

    func remove(_ tile: UUID) {
        guard let b = selectedIndex else { return }
        boards[b].tiles.removeAll { $0.id == tile }
    }

    func resize(_ tile: UUID, to size: TileSize) {
        mutate(tile) { $0.size = size }
    }

    func setConfig(_ tile: UUID, _ key: String, _ value: String?) {
        mutate(tile) { $0.config[key] = value }
    }

    /// Drag-and-drop reorder: move `tile` to where `target` is.
    func move(_ tile: UUID, to target: UUID) {
        guard let b = selectedIndex, tile != target,
              let from = boards[b].tiles.firstIndex(where: { $0.id == tile }),
              let to = boards[b].tiles.firstIndex(where: { $0.id == target }) else { return }
        let item = boards[b].tiles.remove(at: from)
        boards[b].tiles.insert(item, at: to)
    }

    /// Change a tile wherever it is: a widget on a board that isn't showing can still update
    /// itself (a timer running out, say).
    private func mutate(_ tile: UUID, _ change: (inout TileInstance) -> Void) {
        for b in boards.indices {
            if let i = boards[b].tiles.firstIndex(where: { $0.id == tile }) {
                change(&boards[b].tiles[i])
                return
            }
        }
    }

    // MARK: boards

    func addBoard() {
        var n = boards.count + 1
        while boards.contains(where: { $0.name == "Board \(n)" }) { n += 1 }
        let board = Board(name: "Board \(n)", tiles: [], symbol: "square.grid.2x2.fill")
        boards.append(board)
        selectedBoardID = board.id
    }

    func rename(_ board: UUID, to name: String) {
        guard let i = boards.firstIndex(where: { $0.id == board }) else { return }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { boards[i].name = trimmed }
    }

    func deleteBoard(_ board: UUID) {
        guard boards.count > 1, let i = boards.firstIndex(where: { $0.id == board }) else { return }
        boards.remove(at: i)
        if selectedBoardID == board { selectedBoardID = boards[max(0, i - 1)].id }
    }

    /// The apps that bring this board up; an empty list turns that off.
    func setApps(_ board: UUID, _ apps: [String]) {
        guard let i = boards.firstIndex(where: { $0.id == board }) else { return }
        boards[i].apps = apps.isEmpty ? nil : apps
    }

    func moveBoard(_ board: UUID, by offset: Int) {
        guard let i = boards.firstIndex(where: { $0.id == board }) else { return }
        let j = i + offset
        guard boards.indices.contains(j) else { return }
        boards.swapAt(i, j)
    }
}
