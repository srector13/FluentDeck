import SwiftUI

@main
struct FluentDeckApp: App {
    @State private var app: AppModel
    @Environment(\.scenePhase) private var scenePhase

    init() {
        LaunchOptions.applyReset()
        _app = State(initialValue: AppModel())
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(app)
                .environment(app.connection)
                .environment(app.overlays)
                .environment(app.planner)
                .environment(app.settings)
        }
        .onChange(of: scenePhase) { _, phase in app.scenePhaseChanged(phase) }
    }
}

struct RootView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        let theme = app.theme
        ZStack {
            Color.black.ignoresSafeArea()

            if app.showsDashboard {
                DashboardView()
                    .transition(.opacity)
            } else {
                ConnectView()
                    .transition(.opacity)
            }

            if let toast = app.connection.toast {
                VStack {
                    Spacer()
                    Banner(severity: .error, title: toast, onClose: { app.connection.toast = nil })
                        .frame(maxWidth: 520)
                        .shadow(color: .black.opacity(0.3), radius: 16, y: 8)
                        .padding(24)
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            if app.connection.isPairing && !app.choosingHost {
                PairingDialog()
                    .transition(.opacity)
            }
        }
        .appScope(app, theme: theme)
        .statusBarHidden(app.showsDashboard)
        .persistentSystemOverlays(app.showsDashboard ? .hidden : .automatic)
        .animation(.snappy(duration: 0.25), value: app.showsDashboard)
        .animation(.snappy(duration: 0.25), value: app.connection.toast)
        .animation(.easeOut(duration: 0.18), value: app.connection.isPairing)
        .overlaySheets(app.overlays) { sheet in sheet.appScope(app, theme: theme) }
    }
}

extension View {
    /// Everything a screen of the app, or a sheet over it, reads from the environment.
    func appScope(_ app: AppModel, theme: Theme) -> some View {
        self
            .environment(app)
            .environment(app.connection)
            .environment(app.overlays)
            .environment(app.planner)
            .environment(app.settings)
            .environment(\.theme, theme)
            .preferredColorScheme(.dark)
            .tint(theme.accent)
    }
}

/// The ground the board sits on, as chosen in Settings: black washed with the colours of whatever
/// is playing (the way Control Center sits on a blurred wallpaper), or one colour with a soft fall
/// of light from the top. The modules' translucent platters pick it up either way.
struct AmbientBackground: View {
    @Environment(HostConnection.self) private var connection
    @Environment(AppSettings.self) private var settings

    var body: some View {
        ZStack {
            switch settings.backdrop {
            case .artwork:
                let media = connection.store.box("media").decoded(MediaState.self)
                LinearGradient(colors: [Color(hex: "#1A1D29"), Color(hex: "#08080A")], startPoint: .topLeading, endPoint: .bottomTrailing)
                RemoteImage(path: media?.hasSession == true ? media?.artwork : nil)
                    .blur(radius: 110)
                    .saturation(1.5)
                    .opacity(0.55)
                Color.black.opacity(0.25)
            case .color:
                let color = Color(hex: settings.backdropHex)
                color
                LinearGradient(colors: [.white.opacity(0.06), .black.opacity(0.28)], startPoint: .top, endPoint: .bottom)
            }
        }
        .animation(.easeInOut(duration: 0.4), value: settings.backdrop)
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}
