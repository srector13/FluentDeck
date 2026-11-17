import SwiftUI

// ─────────────────────────────────────────────────────────────────────────────
// Adding a widget panel
//
//   1. (If it needs the PC) add a PanelProvider on the host and register it —
//      it shows up in the welcome message automatically.
//   2. Write a SwiftUI view that takes a `PanelContext`, reads state with
//      `ctx.state("topic", as: MyState.self)` and calls `ctx.run("topic", "action")`.
//   3. Give it a `static let spec = PanelSpec(...)` and add it to `PanelCatalog.all`.
//
// Sizing, the options menu, persistence, boards, drag-to-reorder, theming and the
// "Add widgets" picker all come for free. Give the spec a `drawer` and compact sizes get a
// handle that slides the rest of the controls up over the board.
// ─────────────────────────────────────────────────────────────────────────────

/// Widget sizes, as spans of grid cells. A landscape board is 6 × 4 cells, so a tall Now Playing,
/// a huge deck, a medium clock and a banner mixer fill it exactly.
enum TileSize: String, Codable, CaseIterable, Identifiable {
    case small, medium, large, tall, banner, wide, huge

    var id: String { rawValue }

    var span: (columns: Int, rows: Int) {
        switch self {
        case .small: return (1, 1)
        case .medium: return (2, 1)
        case .large: return (2, 2)
        case .tall: return (2, 3)
        case .banner: return (4, 1)
        case .wide: return (4, 2)
        case .huge: return (4, 3)
        }
    }

    var title: String {
        switch self {
        case .small: return "Small"
        case .medium: return "Medium"
        case .large: return "Large"
        case .tall: return "Tall"
        case .banner: return "Banner"
        case .wide: return "Wide"
        case .huge: return "Extra large"
        }
    }
}

/// One placed widget.
struct TileInstance: Codable, Identifiable, Hashable {
    var id = UUID()
    var kind: String
    var size: TileSize
    var config: [String: String] = [:]
}

/// Everything a panel view needs.
@MainActor
struct PanelContext {
    let instance: TileInstance
    let connection: HostConnection
    let overlays: OverlayCenter
    /// The board is being customized. A panel that sets `editsInPlace` can offer its own editing.
    var editing = false
    var updateConfig: (String, String?) -> Void = { _, _ in }

    var size: TileSize { instance.size }
    var config: [String: String] { instance.config }

    /// Typed host state for a topic (re-renders the caller when it changes).
    func state<T: Decodable>(_ topic: String, as type: T.Type) -> T? {
        connection.store.box(topic).decoded(type)
    }

    func box(_ topic: String) -> TopicBox { connection.store.box(topic) }

    /// Invoke an action; errors show as a toast.
    func run(_ panel: String, _ action: String, _ args: [String: JSON] = [:]) {
        connection.run(panel, action, args)
    }

    /// Fire-and-forget for continuous controls.
    func send(_ panel: String, _ action: String, _ args: [String: JSON] = [:]) {
        connection.send(panel, action, args)
    }
}

/// Describes a widget type to the dashboard and the "Add widgets" picker.
struct PanelSpec: Identifiable {
    var id: String { kind }

    /// Stable identifier persisted in layouts, e.g. "media.nowPlaying".
    let kind: String
    let title: String
    let summary: String
    let symbol: String
    /// Host topic this panel needs; nil for client-only panels (e.g. Clock).
    var requires: String? = nil
    let sizes: [TileSize]
    let defaultSize: TileSize
    var defaultConfig: [String: String] = [:]
    /// Extra items for the widget's ⋯ menu.
    var menu: @MainActor (PanelContext) -> [ActionItem] = { _ in [] }
    /// Optional layer behind the widget's content. It isn't clipped, so it can spill onto the board.
    var background: (@MainActor (PanelContext) -> AnyView)? = nil
    /// Stays interactive while the board is customized, to edit its own content (the deck's keys).
    var editsInPlace = false
    /// The rest of the widget's controls, shown in a drawer that slides up from a handle under it.
    var drawer: (@MainActor (PanelContext) -> AnyView)? = nil
    /// Sizes that get the drawer handle; nil means every size. Sizes that already show everything
    /// leave it out.
    var drawerSizes: [TileSize]? = nil
    let view: @MainActor (PanelContext) -> AnyView
}

@MainActor
enum PanelCatalog {
    /// Every widget the app knows about, in picker order.
    static let all: [PanelSpec] = [
        NowPlayingPanel.spec,
        VolumeMixerPanel.spec,
        DeckPanel.spec,
        SystemPanel.spec,
        CalendarPanel.spec,
        RemindersPanel.spec,
        ClockPanel.spec,
    ]

    static func spec(for kind: String) -> PanelSpec? { all.first { $0.kind == kind } }
}
