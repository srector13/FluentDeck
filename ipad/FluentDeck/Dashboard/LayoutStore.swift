import Foundation
import Observation

/// A board is one page of widgets (like Stream Deck profiles). Boards are tabs in the SelectorBar.
struct Board: Codable, Identifiable, Hashable {
    var id = UUID()
    var name: String
    var tiles: [TileInstance]
}

/// Persists boards and widget placement in UserDefaults.
@MainActor
@Observable
final class LayoutStore {
    var boards: [Board] { didSet { save() } }
    var selectedBoardID: UUID? { didSet { save() } }

    private let key = "fluentdeck.layout.v1"

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
            let home = Board(name: "Home", tiles: [
                TileInstance(kind: NowPlayingPanel.spec.kind, size: .large),
                TileInstance(kind: VolumeMixerPanel.spec.kind, size: .large),
                TileInstance(kind: SystemPanel.spec.kind, size: .medium),
                TileInstance(kind: ClockPanel.spec.kind, size: .small),
                TileInstance(kind: VolumeMixerPanel.spec.kind, size: .small),
                TileInstance(kind: DeckPanel.spec.kind, size: .wide, config: ["page": "main"]),
            ])
            let dev = Board(name: "Dev", tiles: [
                TileInstance(kind: DeckPanel.spec.kind, size: .wide, config: ["page": "dev"]),
                TileInstance(kind: SystemPanel.spec.kind, size: .large),
                TileInstance(kind: NowPlayingPanel.spec.kind, size: .medium),
                TileInstance(kind: ClockPanel.spec.kind, size: .small),
            ])
            boards = [home, dev]
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

    private func mutate(_ tile: UUID, _ change: (inout TileInstance) -> Void) {
        guard let b = selectedIndex, let i = boards[b].tiles.firstIndex(where: { $0.id == tile }) else { return }
        change(&boards[b].tiles[i])
    }

    // MARK: boards

    func addBoard() {
        var n = boards.count + 1
        while boards.contains(where: { $0.name == "Board \(n)" }) { n += 1 }
        let board = Board(name: "Board \(n)", tiles: [])
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

    func moveBoard(_ board: UUID, by offset: Int) {
        guard let i = boards.firstIndex(where: { $0.id == board }) else { return }
        let j = i + offset
        guard boards.indices.contains(j) else { return }
        boards.swapAt(i, j)
    }
}
