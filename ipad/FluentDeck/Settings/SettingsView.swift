import SwiftUI

/// The app's settings, as a grouped list in a page sheet: the PC, how the board looks, the deck,
/// the clock and the screen.
struct SettingsView: View {
    @Environment(AppModel.self) private var app
    @Environment(AppSettings.self) private var settings
    @Environment(\.theme) private var theme

    var body: some View {
        @Bindable var settings = settings
        NavigationStack {
            Form {
                if let hostId = app.connection.hostId {
                    pcSection(hostId)
                }

                Section {
                    Picker("Background", selection: $settings.backdrop) {
                        ForEach(AppSettings.Backdrop.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .listRowSeparator(.hidden)
                    if settings.backdrop == .color {
                        SwatchRow(colors: AppSettings.backdropSwatches, selection: $settings.backdropHex, label: "Background color")
                        ColorPicker("Custom color", selection: colorBinding($settings.backdropHex), supportsOpacity: false)
                    }
                } header: {
                    Text("Background")
                } footer: {
                    Text(settings.backdrop == .artwork
                         ? "The board takes on the colours of whatever is playing on the PC."
                         : "The board sits on one colour. Darker colours keep text easy to read.")
                }

                Section {
                    SwatchRow(colors: AppSettings.accentSwatches, selection: $settings.accentHex, label: "Accent color")
                    ColorPicker("Custom color", selection: colorBinding($settings.accentHex), supportsOpacity: false)
                } header: {
                    Text("Accent color")
                } footer: {
                    Text("Used for buttons, switches, gauges and the selected tab.")
                }

                Section {
                    Toggle("Show key names", isOn: $settings.keyLabels)
                    Toggle("Light keys with the accent color", isOn: $settings.litKeysUseAccent)
                    Toggle("Haptic feedback", isOn: $settings.haptics)
                } header: {
                    Text("Deck")
                } footer: {
                    Text("A key lights up while what it controls is on, such as a muted mic. Lit keys are white unless you choose the accent color.")
                }

                Section {
                    Toggle("Switch boards with the app in front", isOn: $settings.autoSwitchBoards)
                } header: {
                    Text("Boards")
                } footer: {
                    Text("A board set to show for an app (⋯ → Show for Apps…) comes up when that app is in front on the PC, and the iPad goes back when you leave it.")
                }

                Section("Clock") {
                    Picker("Time format", selection: Binding(
                        get: { settings.clock24Hour.map { $0 ? 24 : 12 } ?? 0 },
                        set: { settings.clock24Hour = $0 == 0 ? nil : $0 == 24 })) {
                        Text("Automatic").tag(0)
                        Text("12-hour").tag(12)
                        Text("24-hour").tag(24)
                    }
                }

                Section {
                    Toggle("Keep screen awake", isOn: Binding(get: { app.keepAwake }, set: { app.keepAwake = $0 }))
                } footer: {
                    Text("While connected to a PC, the iPad doesn't lock itself.")
                }

                Section {
                    LabeledContent("Version", value: Self.version)
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { app.overlays.dismissDialog() }.fontWeight(.semibold)
                }
            }
        }
    }

    private func pcSection(_ hostId: String) -> some View {
        Section {
            LabeledContent("Name") {
                TextField(app.connection.reportedName, text: Binding(
                    get: { settings.pcName(for: hostId) ?? "" },
                    set: { settings.rename(pc: hostId, to: $0) }))
                    .multilineTextAlignment(.trailing)
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled()
                    .submitLabel(.done)
            }
            if let endpoint = app.connection.endpoint {
                LabeledContent("Address", value: "\(endpoint.host):\(endpoint.port)")
            }
            Button("Switch PC…") {
                app.overlays.dismissDialog()
                app.switchHost()
            }
        } header: {
            Text("This PC")
        } footer: {
            Text("The name is only used on this iPad. Leave it empty to use the PC's own name, “\(app.connection.reportedName)”.")
        }
    }

    private func colorBinding(_ hex: Binding<String>) -> Binding<Color> {
        Binding(get: { Color(hex: hex.wrappedValue) }, set: { hex.wrappedValue = $0.hexString })
    }

    static var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = info?["CFBundleVersion"] as? String ?? ""
        return build.isEmpty || build == short ? short : "\(short) (\(build))"
    }
}

/// A row of colour circles; the chosen one wears a ring. A colour picked elsewhere selects none.
struct SwatchRow: View {
    let colors: [String]
    @Binding var selection: String
    var label: String

    var body: some View {
        HStack(spacing: 0) {
            ForEach(colors, id: \.self) { hex in
                let chosen = hex.caseInsensitiveCompare(selection) == .orderedSame
                Button { selection = hex } label: {
                    Circle()
                        .fill(Color(hex: hex))
                        .overlay(Circle().strokeBorder(.white.opacity(hex == "#000000" ? 0.25 : 0), lineWidth: 1))
                        .frame(width: 28, height: 28)
                        .padding(4)
                        .overlay(Circle().strokeBorder(.white.opacity(chosen ? 0.9 : 0), lineWidth: 2))
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(label) \(hex)")
                .accessibilityAddTraits(chosen ? .isSelected : [])
            }
        }
    }
}

/// Renames the PC on this iPad.
struct RenamePCDialog: View {
    let hostId: String
    @Environment(AppModel.self) private var app
    @Environment(AppSettings.self) private var settings
    @Environment(\.theme) private var theme
    @State private var name = ""

    var body: some View {
        DialogSheet(title: "Rename PC",
                    cancel: DialogAction("Cancel") { app.overlays.dismissDialog() },
                    confirm: DialogAction("Save") { save() }) {
            TextBox(placeholder: app.connection.reportedName, text: $name) { save() }
            Text("Only this iPad uses this name. Leave it empty to use the PC's own name.")
                .font(AppFont.caption)
                .foregroundStyle(theme.textSecondary)
        }
        .onAppear { name = settings.pcName(for: hostId) ?? "" }
    }

    private func save() {
        settings.rename(pc: hostId, to: name)
        app.overlays.dismissDialog()
    }
}
