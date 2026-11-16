import SwiftUI
import Observation
import UIKit

/// App-wide state: the connection, discovery, layout, overlays and preferences.
@MainActor
@Observable
final class AppModel {
    let connection = HostConnection()
    let browser = HostBrowser()
    let layout = LayoutStore()
    let overlays = OverlayCenter()

    var editing = false
    /// The user chose "Switch PC…" — show the connect screen even though a PC is configured.
    var choosingHost = false

    var keepAwake: Bool {
        didSet { UserDefaults.standard.set(keepAwake, forKey: "fluentdeck.keepAwake"); updateIdleTimer() }
    }
    private(set) var savedHosts: [HostEndpoint] {
        didSet { if let data = try? JSONEncoder().encode(savedHosts) { UserDefaults.standard.set(data, forKey: "fluentdeck.hosts") } }
    }

    init() {
        let defaults = UserDefaults.standard
        keepAwake = defaults.object(forKey: "fluentdeck.keepAwake") as? Bool ?? true
        savedHosts = (defaults.data(forKey: "fluentdeck.hosts")).flatMap { try? JSONDecoder().decode([HostEndpoint].self, from: $0) } ?? []

        connection.onConnected = { [weak self] endpoint in
            guard let self else { return }
            self.remember(endpoint)
            self.choosingHost = false
            self.browser.stop()
            self.updateIdleTimer()
        }

        if let board = LaunchOptions.board, layout.boards.indices.contains(board) {
            layout.selectedBoardID = layout.boards[board].id
        }

        if let forced = LaunchOptions.connect {
            connection.connect(to: savedHosts.first { $0.host == forced.host && $0.port == forced.port } ?? forced)
        } else if let last = savedHosts.first {
            connection.connect(to: last)
        } else {
            browser.start()
        }
    }

    // MARK: theme

    /// Always dark, on true black. The accent is the PC's own once connected.
    var theme: FluentTheme {
        let pc = connection.store.box("theme").decoded(ThemeState.self)
        return FluentTheme(isDark: true, palette: pc.map { AccentPalette($0) } ?? .windowsBlue)
    }

    // MARK: hosts

    var showsDashboard: Bool {
        guard !choosingHost else { return false }
        switch connection.phase {
        case .connected, .reconnecting: return true
        default: return false
        }
    }

    func connect(_ endpoint: HostEndpoint) {
        choosingHost = false
        connection.connect(to: endpoint)
    }

    private func remember(_ endpoint: HostEndpoint) {
        var hosts = savedHosts.filter { $0.id != endpoint.id && !($0.host == endpoint.host && $0.port == endpoint.port) }
        hosts.insert(endpoint, at: 0) // most recent first; it auto-connects next launch
        savedHosts = Array(hosts.prefix(8))
    }

    func forget(_ endpoint: HostEndpoint) {
        if let id = endpoint.hostId { Keychain.deleteToken(for: id) }
        savedHosts.removeAll { $0.id == endpoint.id }
    }

    func forgetCurrentHost() {
        if let ep = connection.endpoint { forget(ep) }
        connection.disconnect()
        browser.start()
    }

    func switchHost() {
        choosingHost = true
        browser.start()
    }

    func cancelConnect() {
        connection.disconnect()
        browser.start()
    }

    // MARK: lifecycle

    func scenePhaseChanged(_ phase: ScenePhase) {
        switch phase {
        case .active:
            connection.resume()
            if !connection.isConnected { browser.start() }
            updateIdleTimer()
        case .background:
            browser.stop()
        default:
            break
        }
    }

    private func updateIdleTimer() {
        UIApplication.shared.isIdleTimerDisabled = keepAwake && connection.isConnected
    }

    // MARK: panels

    func context(for tile: TileInstance, preview: Bool = false) -> PanelContext {
        PanelContext(
            instance: tile,
            connection: connection,
            overlays: overlays,
            editing: editing && !preview,
            updateConfig: { [weak self] key, value in
                guard !preview else { return }
                self?.layout.setConfig(tile.id, key, value)
            })
    }

    func showWidgetPicker() {
        overlays.present { WidgetPicker() }
    }

    func promptRename(_ board: Board) {
        overlays.present { RenameBoardDialog(board: board) }
    }
}

private struct RenameBoardDialog: View {
    let board: Board
    @Environment(AppModel.self) private var app
    @State private var name = ""

    var body: some View {
        ContentDialog(title: "Rename board") {
            FluentTextBox(placeholder: "Board name", text: $name) { save() }
        } footer: {
            DialogButton(title: "Save", accent: true, enabled: !name.trimmingCharacters(in: .whitespaces).isEmpty) { save() }
            DialogButton(title: "Cancel") { app.overlays.dismissDialog() }
        }
        .onAppear { name = board.name }
    }

    private func save() {
        app.layout.rename(board.id, to: name)
        app.overlays.dismissDialog()
    }
}
