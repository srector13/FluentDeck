import SwiftUI

/// "Connect to your PC" — laid out like a Windows 11 Settings page (title, SettingsCards, expander).
struct ConnectView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.fluent) private var theme
    @State private var address = ""
    @State private var port = "47610"
    @State private var resolving: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 14) {
                    AppGlyph(size: 44)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Connect to your PC").font(FluentFont.title).foregroundStyle(theme.textPrimary)
                        Text("Run FluentDeck on your Windows PC, then choose it below.")
                            .font(FluentFont.body).foregroundStyle(theme.textSecondary)
                    }
                }
                .padding(.bottom, 18)

                status

                HStack {
                    FluentSectionHeader(title: "PCs on this network")
                    if app.browser.isBrowsing { FluentProgressRing(size: 14, lineWidth: 2).padding(.top, 8) }
                }
                if app.browser.permissionDenied {
                    InfoBar(severity: .warning, title: "Local Network access is off",
                            message: "Turn on Settings → Privacy & Security → Local Network → FluentDeck so the iPad can find your PC.")
                }
                if app.browser.hosts.isEmpty {
                    SettingsCard(symbol: "antenna.radiowaves.left.and.right", title: "Looking for PCs…",
                                 subtitle: "Make sure FluentDeck is running on the PC and both devices are on the same Wi-Fi.") { EmptyView() }
                } else {
                    ForEach(app.browser.hosts) { found in
                        Button { Task { await connect(found) } } label: {
                            SettingsCard(symbol: "laptopcomputer", title: found.name,
                                         subtitle: found.endpoint.map { "\($0.host):\($0.port)" } ?? "Tap to connect") {
                                if resolving == found.id { FluentProgressRing(size: 16) } else { Chevron() }
                            }
                        }
                        .buttonStyle(CardButtonStyle())
                    }
                }

                let recent = app.savedHosts.filter { saved in !app.browser.hosts.contains { $0.id == saved.id } }
                if !recent.isEmpty {
                    FluentSectionHeader(title: "Recent")
                    ForEach(recent) { host in
                        HStack(spacing: 6) {
                            Button { app.connect(host) } label: {
                                SettingsCard(symbol: "clock.arrow.circlepath", title: host.name, subtitle: "\(host.host):\(host.port)") { Chevron() }
                            }
                            .buttonStyle(CardButtonStyle())
                            FlyoutButton(width: 200, items: { [FlyoutItem.action("Forget", symbol: "trash", destructive: true) { app.forget(host) }] }) {
                                Image(systemName: "ellipsis").frame(width: 28, height: 28)
                            }
                            .accessibilityLabel("More options for \(host.name)")
                        }
                    }
                }

                FluentSectionHeader(title: "Add a PC manually")
                VStack(alignment: .leading, spacing: 12) {
                    Text("Use the address shown in the FluentDeck tray menu on the PC. For the DevHost on a Mac, use its IP (or 127.0.0.1 in the Simulator).")
                        .font(FluentFont.caption).foregroundStyle(theme.textSecondary)
                    HStack(spacing: 10) {
                        FluentTextBox(placeholder: "192.168.1.20", text: $address, keyboard: .numbersAndPunctuation, onSubmit: manualConnect)
                        FluentTextBox(placeholder: "Port", text: $port, keyboard: .numberPad).frame(width: 100)
                        Button("Connect", action: manualConnect)
                            .buttonStyle(FluentButtonStyle(kind: .accent))
                            .disabled(address.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
                .fluentCard()

                if app.connection.endpoint != nil && app.choosingHost {
                    Button("Back to \(app.connection.hostName)") { app.choosingHost = false }
                        .buttonStyle(FluentButtonStyle(kind: .standard))
                        .padding(.top, 12)
                }
            }
            .frame(maxWidth: 720)
            .padding(.horizontal, 32)
            .padding(.vertical, 48)
            .frame(maxWidth: .infinity)
        }
        .scrollIndicators(.hidden)
        .onAppear { app.browser.start() }
    }

    @ViewBuilder
    private var status: some View {
        switch app.connection.phase {
        case .connecting:
            InfoBar(severity: .informational, title: "Connecting to \(app.connection.hostName)…", busy: true,
                    onClose: { app.cancelConnect() })
                .padding(.bottom, 8)
        case .failed(let message):
            HStack(alignment: .top, spacing: 8) {
                InfoBar(severity: .error, title: "Couldn’t connect", message: message)
                Button("Retry") { app.connection.retry() }.buttonStyle(FluentButtonStyle(kind: .standard))
            }
            .padding(.bottom, 8)
        default:
            EmptyView()
        }
    }

    private func connect(_ found: HostBrowser.Found) async {
        resolving = found.id
        defer { resolving = nil }
        if let endpoint = await app.browser.resolve(found) {
            app.connect(endpoint)
        } else {
            app.connection.report(HostError.action("Couldn’t resolve \(found.name). Try adding it manually."))
        }
    }

    private func manualConnect() {
        let host = address.trimmingCharacters(in: .whitespaces)
        guard !host.isEmpty else { return }
        app.connect(HostEndpoint(host: host, port: Int(port) ?? 47610, hostId: nil, name: host))
    }
}

/// WinUI SettingsCard: icon, header, description, trailing content.
struct SettingsCard<Trailing: View>: View {
    var symbol: String
    var title: String
    var subtitle: String?
    @ViewBuilder var trailing: () -> Trailing
    @Environment(\.fluent) private var theme

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: symbol).font(.system(size: 20)).foregroundStyle(theme.textPrimary).frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(FluentFont.body).foregroundStyle(theme.textPrimary)
                if let subtitle { Text(subtitle).font(FluentFont.caption).foregroundStyle(theme.textSecondary) }
            }
            Spacer(minLength: 8)
            trailing()
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 68)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Fluent.controlRadius).fill(theme.cardFill))
        .overlay(RoundedRectangle(cornerRadius: Fluent.controlRadius).strokeBorder(theme.cardStroke, lineWidth: 1))
    }
}

private struct Chevron: View {
    @Environment(\.fluent) private var theme
    var body: some View {
        Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(theme.textSecondary)
    }
}

/// Pressed state for clickable SettingsCards.
private struct CardButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.75 : 1)
            .scaleEffect(configuration.isPressed ? 0.995 : 1)
            .animation(.easeOut(duration: 0.08), value: configuration.isPressed)
    }
}
