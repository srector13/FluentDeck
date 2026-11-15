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
        }
        .onChange(of: scenePhase) { _, phase in app.scenePhaseChanged(phase) }
    }
}

struct RootView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let theme = app.theme(system: colorScheme)
        ZStack {
            MicaBackground()

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
                    InfoBar(severity: .error, title: toast, onClose: { app.connection.toast = nil })
                        .frame(maxWidth: 520)
                        .shadow(color: .black.opacity(0.25), radius: 12, y: 6)
                        .padding(24)
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            if app.connection.isPairing && !app.choosingHost {
                PairingDialog()
                    .transition(.opacity)
            }

            OverlayHost()
        }
        .coordinateSpace(name: Fluent.rootSpace)
        .environment(\.fluent, theme)
        .preferredColorScheme(theme.isDark ? .dark : .light)
        .tint(theme.accent)
        .statusBarHidden(app.showsDashboard)
        .persistentSystemOverlays(app.showsDashboard ? .hidden : .automatic)
        .animation(.snappy(duration: 0.25), value: app.showsDashboard)
        .animation(.snappy(duration: 0.25), value: app.connection.toast)
        .animation(.easeOut(duration: 0.18), value: app.connection.isPairing)
    }
}
