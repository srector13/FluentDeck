import PhotosUI
import SwiftUI
import UIKit

// Editing deck keys from the iPad: what a key is called, what it does when pressed, and how it
// looks. The PC keeps the keys in deck.json and must allow editing (its tray menu), because a key
// can launch any program.

/// A key as the host stores it: returned by the deck's `getButton`, accepted by `saveButton`.
struct DeckKeyDraft: Codable, Equatable {
    var label = ""
    var symbol: String?
    var symbolOn: String?
    /// A program on the PC (its Windows icon is used) or an image under the host's data folder.
    var icon: String?
    var style: String?
    var state: DeckBinding?
    /// The deck.json action, kept as JSON so fields this editor doesn't show survive a save.
    var action: JSON?
}

/// An installed app the PC offers for a key that opens something.
struct DeckAppInfo: Codable, Identifiable, Hashable {
    var name: String
    var path: String
    var icon: String?
    var id: String { path }
}

@MainActor
enum DeckEditing {
    /// The host is new enough to edit keys at all.
    static func supported(_ ctx: PanelContext) -> Bool {
        ctx.connection.panels.first { $0.id == "deck" }?.actions.contains("saveButton") ?? false
    }

    static func canEdit(_ ctx: PanelContext, _ deck: DeckState) -> Bool {
        blocked(ctx, deck) == nil
    }

    /// Why keys can't be edited right now, or nil if they can.
    static func blocked(_ ctx: PanelContext, _ deck: DeckState) -> String? {
        if !supported(ctx) { return "Update FluentDeck on the PC to edit keys from here." }
        if deck.editable != true {
            return "Editing keys is turned off on this PC. Turn on “Allow editing keys from the iPad” in its FluentDeck tray menu."
        }
        if deck.error != nil { return "deck.json has an error. Fix it on the PC before editing keys here." }
        return nil
    }

    /// Open the editor for a key, or for a new key when `buttonId` is nil.
    static func editKey(_ ctx: PanelContext, pageId: String, buttonId: String?) {
        ctx.overlays.present(size: .page) { DeckKeyEditor(ctx: ctx, pageId: pageId, buttonId: buttonId) }
    }

    static func addPage(_ ctx: PanelContext) {
        Task {
            do {
                let result = try await ctx.connection.invoke("deck", "addPage")
                if let id = result?["pageId"]?.string { ctx.updateConfig("page", id) }
            } catch {
                ctx.connection.report(error)
            }
        }
    }

    static func describe(_ error: Error) -> String {
        (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    }
}

/// What pressing a key does, as the editor groups it.
enum DeckKeyKind: String, CaseIterable, Identifiable {
    case app, hotkey, link, text, control, desktop
    /// A sequence or an action this editor has no form for. It is kept as it is.
    case other

    var id: String { rawValue }

    var title: String {
        switch self {
        case .app: return "Open app"
        case .hotkey: return "Hotkey"
        case .link: return "Link"
        case .text: return "Type text"
        case .control: return "PC control"
        case .desktop: return "Desktop"
        case .other: return "Custom"
        }
    }
}

/// A ready-made key that drives one of the host's panels, with the state that lights it up.
struct DeckControlPreset: Identifiable {
    let panel: String
    let action: String
    let title: String
    let symbol: String
    var symbolOn: String? = nil
    var state: DeckBinding? = nil

    var id: String { "\(panel).\(action)" }

    static let all: [DeckControlPreset] = [
        DeckControlPreset(panel: "media", action: "playPause", title: "Play or pause", symbol: "play.fill", symbolOn: "pause.fill",
                          state: DeckBinding(topic: "media", path: "status", equals: .string("playing"))),
        DeckControlPreset(panel: "media", action: "next", title: "Next track", symbol: "forward.fill"),
        DeckControlPreset(panel: "media", action: "previous", title: "Previous track", symbol: "backward.fill"),
        DeckControlPreset(panel: "audio", action: "toggleMute", title: "Mute sound", symbol: "speaker.wave.2", symbolOn: "speaker.slash",
                          state: DeckBinding(topic: "audio", path: "output.muted", equals: .bool(true))),
        DeckControlPreset(panel: "audio", action: "toggleMicMute", title: "Mute microphone", symbol: "mic", symbolOn: "mic.slash",
                          state: DeckBinding(topic: "audio", path: "input.muted", equals: .bool(true))),
        DeckControlPreset(panel: "system", action: "lock", title: "Lock the PC", symbol: "lock"),
        DeckControlPreset(panel: "system", action: "sleep", title: "Sleep", symbol: "moon"),
        DeckControlPreset(panel: "system", action: "displayOff", title: "Turn the screen off", symbol: "display"),
    ]
}

/// Where a desktop key goes: a numbered desktop, or the next or previous one.
enum DeckDesktopTarget: Hashable {
    case index(Int)
    case next, previous

    var symbol: String {
        switch self {
        case .index(let n): return n <= 50 ? "\(n).square" : "rectangle.split.3x1"
        case .next: return "arrow.right.square"
        case .previous: return "arrow.left.square"
        }
    }

    func title(_ desktops: [DesktopsState.Desktop]) -> String {
        switch self {
        case .index(let n): return desktops.first { $0.index == n }?.name ?? "Desktop \(n)"
        case .next: return "Next desktop"
        case .previous: return "Previous desktop"
        }
    }

    /// The deck.json action, and for a numbered desktop the binding that lights the key while
    /// that desktop is showing.
    var action: JSON {
        switch self {
        case .index(let n):
            return .object(["type": "builtin", "panel": "desktops", "action": "switch", "args": .object(["index": .number(Double(n))])])
        case .next: return .object(["type": "builtin", "panel": "desktops", "action": "next"])
        case .previous: return .object(["type": "builtin", "panel": "desktops", "action": "previous"])
        }
    }

    var state: DeckBinding? {
        if case .index(let n) = self { return DeckBinding(topic: "desktops", path: "current", equals: .number(Double(n))) }
        return nil
    }

    init?(action: JSON?) {
        guard action?["panel"]?.string == "desktops" else { return nil }
        switch action?["action"]?.string {
        case "next": self = .next
        case "previous": self = .previous
        case "switch":
            guard let n = action?["args"]?["index"]?.double else { return nil }
            self = .index(Int(n))
        default: return nil
        }
    }
}

/// Builds hotkey strings the host understands: "Win+Shift+S", or steps separated by spaces.
enum DeckHotkey {
    static let modifiers = ["Ctrl", "Shift", "Alt", "Win"]
    static let specialKeys = ["Esc", "Tab", "Enter", "Space", "Backspace", "Delete", "Up", "Down", "Left", "Right",
                              "Home", "End", "PgUp", "PgDn", "PrtSc",
                              "F1", "F2", "F3", "F4", "F5", "F6", "F7", "F8", "F9", "F10", "F11", "F12"]

    private static func isModifier(_ part: String) -> Bool {
        modifiers.contains { $0.caseInsensitiveCompare(part) == .orderedSame }
    }

    /// The earlier steps, and the last step split into its modifiers and its key.
    private static func parts(_ text: String) -> (earlier: [String], modifiers: [String], key: String) {
        var steps = text.split(separator: " ").map(String.init)
        let last = steps.popLast() ?? ""
        let pieces = last.split(separator: "+").map(String.init)
        let held = modifiers.filter { name in pieces.contains { $0.caseInsensitiveCompare(name) == .orderedSame } }
        let key = pieces.last { !isModifier($0) } ?? ""
        return (steps, held, key)
    }

    private static func join(_ earlier: [String], _ held: [String], _ key: String) -> String {
        let step = (held + (key.isEmpty ? [] : [key])).joined(separator: "+")
        return (earlier + (step.isEmpty ? [] : [step])).joined(separator: " ")
    }

    static func holds(_ text: String, _ modifier: String) -> Bool {
        parts(text).modifiers.contains(modifier)
    }

    /// Add or remove a modifier on the last step.
    static func toggling(_ text: String, _ modifier: String) -> String {
        let p = parts(text)
        let held = modifiers.filter { ($0 == modifier) != p.modifiers.contains($0) }
        return join(p.earlier, held, p.key)
    }

    /// Replace the key of the last step.
    static func settingKey(_ text: String, _ key: String) -> String {
        let p = parts(text)
        return join(p.earlier, p.modifiers, key)
    }
}

enum DeckSymbols {
    /// A starter set; any SF Symbol name can be typed in.
    static let all = [
        "app", "star", "heart", "bolt", "flame", "sparkles", "house", "gearshape", "folder", "doc.text",
        "note.text", "calendar", "clock", "timer", "bell", "envelope", "message", "phone", "video", "camera",
        "photo", "mic", "mic.slash", "speaker.wave.2", "speaker.slash", "headphones", "music.note", "play.fill", "pause.fill", "forward.fill",
        "backward.fill", "record.circle", "tv", "display", "laptopcomputer", "keyboard", "printer", "gamecontroller", "globe", "link",
        "magnifyingglass", "cart", "creditcard", "lock", "lock.open", "key", "person", "person.2", "moon", "sun.max",
        "lightbulb", "power", "wifi", "terminal", "chevron.left.forwardslash.chevron.right", "hammer", "paintbrush", "scissors", "pencil", "trash",
        "square.and.arrow.up", "arrow.clockwise", "rectangle.on.rectangle", "macwindow", "square.grid.2x2", "list.bullet", "chart.bar", "map", "airplane", "cup.and.saucer",
    ]
}

enum DeckIconImage {
    /// A square picture small enough to send to the PC in one message: centre-cropped to 256 px.
    static func encode(_ image: UIImage, side: CGFloat = 256) -> Data? {
        guard image.size.width > 0, image.size.height > 0 else { return nil }
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        let square = UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format).image { _ in
            let scale = max(side / image.size.width, side / image.size.height)
            let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
            image.draw(in: CGRect(x: (side - size.width) / 2, y: (side - size.height) / 2, width: size.width, height: size.height))
        }
        if let png = square.pngData(), png.count <= 120_000 { return png }
        return square.jpegData(compressionQuality: 0.8)
    }

    /// A picture fills the key; a program's icon sits on it.
    static func isPicture(_ path: String?) -> Bool {
        guard let path = path?.lowercased() else { return false }
        return path.hasSuffix(".png") || path.hasSuffix(".jpg") || path.hasSuffix(".jpeg")
    }
}

// MARK: - Editor

/// The key editor: a live preview on the left, the key's label, action and icon on the right.
struct DeckKeyEditor: View {
    let ctx: PanelContext
    let pageId: String
    /// nil adds a key to the page.
    let buttonId: String?

    @Environment(\.theme) private var theme

    @State private var loaded = false
    @State private var busy = false
    @State private var problem: String?
    @State private var original = DeckKeyDraft()
    @State private var originalKind = DeckKeyKind.app
    @State private var index = 0
    @State private var count = 0

    @State private var label = ""
    @State private var kind = DeckKeyKind.app
    @State private var target = ""
    @State private var keys = ""
    @State private var link = ""
    @State private var text = ""
    @State private var controlID: String?
    @State private var desktop: DeckDesktopTarget?
    @State private var accent = false

    @State private var symbol = "app"
    @State private var useImage = false
    @State private var icon: String?
    @State private var iconAsset: String?
    @State private var photo: PhotosPickerItem?

    @State private var apps: [DeckAppInfo]?
    @State private var search = ""

    private struct ButtonInfo: Decodable {
        var index: Int
        var count: Int
        var button: DeckKeyDraft
        var iconAsset: String?
    }

    private struct AppList: Decodable {
        var apps: [DeckAppInfo]
    }

    var body: some View {
        DialogSheet(title: buttonId == nil ? "Add key" : "Edit key", fills: true,
                    cancel: DialogAction("Cancel") { ctx.overlays.dismissDialog() },
                    confirm: DialogAction("Save", enabled: loaded && !busy) { save() }) {
            if loaded {
                HStack(alignment: .top, spacing: 28) {
                    side.frame(width: 150)
                    ScrollView { form }
                        .scrollIndicators(.hidden)
                        .frame(maxHeight: .infinity)
                }
            } else {
                Spinner().frame(maxWidth: .infinity, minHeight: 200)
            }
        }
        .task { await load() }
        .onChange(of: photo) { _, item in
            if let item { Task { await upload(item) } }
        }
    }

    // MARK: layout

    private var side: some View {
        VStack(spacing: 16) {
            DeckKeyPreview(symbol: symbol, iconAsset: useImage ? iconAsset : nil,
                           fill: useImage && DeckIconImage.isPicture(icon), label: label, lit: accent)
            if buttonId != nil {
                HStack(spacing: 4) {
                    IconButton(symbol: "arrow.left", label: "Move earlier") { move(-1) }
                        .disabled(busy || index <= 0)
                    IconButton(symbol: "arrow.right", label: "Move later") { move(1) }
                        .disabled(busy || index >= count - 1)
                }
                Button(action: delete) { Label("Delete key", systemImage: "trash") }
                    .buttonStyle(PillButtonStyle(kind: .subtle, compact: true))
                    .disabled(busy)
            }
        }
    }

    private var form: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let problem { Banner(severity: .error, title: problem) }

            heading("Label")
            TextBox(placeholder: "Name shown under the key", text: $label)

            heading("When pressed")
            SegmentedBar(items: kinds.map { SegmentedBar<DeckKeyKind>.Item(id: $0, title: $0.title) },
                         selection: Binding(get: { kind }, set: { if let new = $0 { kind = new } }))
            actionFields

            heading("Icon")
            SegmentedBar(items: [SegmentedBar<Bool>.Item(id: false, title: "Symbol"), SegmentedBar<Bool>.Item(id: true, title: "Image")],
                        selection: Binding(get: { useImage }, set: { if let new = $0 { useImage = new } }))
                .frame(maxWidth: 260)
            if useImage { imageFields } else { symbolFields }

            Toggle("Always lit", isOn: $accent)
                .font(AppFont.body)
                .foregroundStyle(theme.textPrimary)
                .padding(.top, 4)
        }
        .padding(.trailing, 2)
    }

    /// Kinds the user can pick. "Custom" only appears for a key that already is one.
    private var kinds: [DeckKeyKind] {
        var list: [DeckKeyKind] = [.app, .hotkey, .link, .text]
        if !presets.isEmpty { list.append(.control) }
        if ctx.connection.hostProvides("desktops") { list.append(.desktop) }
        if originalKind == .other { list.append(.other) }
        return list
    }

    /// Controls this PC actually offers.
    private var presets: [DeckControlPreset] {
        DeckControlPreset.all.filter { preset in
            ctx.connection.panels.first { $0.id == preset.panel }?.actions.contains(preset.action) ?? false
        }
    }

    private func heading(_ title: String) -> some View {
        Text(title)
            .font(AppFont.caption.weight(.semibold))
            .foregroundStyle(theme.textSecondary)
            .padding(.top, 8)
    }

    private func note(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12))
            .foregroundStyle(theme.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder
    private var actionFields: some View {
        switch kind {
        case .app: appFields
        case .hotkey: hotkeyFields
        case .link:
            TextBox(placeholder: "https://… or an app link such as spotify:", text: $link, keyboard: .URL)
        case .text:
            TextBox(placeholder: "Text to type on the PC", text: $text)
        case .control: controlFields
        case .desktop: desktopFields
        case .other:
            note("This key runs a multi-step or custom action. Change its steps in deck.json on the PC. Its label and icon can be changed here.")
        }
    }

    private var appFields: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextBox(placeholder: "Search apps on the PC", text: $search)
            if let apps {
                if apps.isEmpty {
                    note("The PC didn’t list any apps. Enter a path or command below.")
                } else {
                    ScrollView {
                        LazyVStack(spacing: 2) {
                            ForEach(matches(apps)) { app in
                                DeckAppRow(app: app, selected: app.path == target) { choose(app) }
                            }
                        }
                    }
                    .frame(height: 180)
                }
            } else {
                Spinner(size: 18).frame(maxWidth: .infinity, minHeight: 60)
            }
            TextBox(placeholder: "Or a path or command, e.g. wt.exe", text: $target)
        }
        .task { await loadApps() }
    }

    private var hotkeyFields: some View {
        VStack(alignment: .leading, spacing: 8) {
            let columns = [GridItem(.adaptive(minimum: 88), spacing: 6)]
            LazyVGrid(columns: columns, alignment: .leading, spacing: 6) {
                ForEach(DeckHotkey.modifiers, id: \.self) { modifier in
                    DeckChip(title: modifier, on: DeckHotkey.holds(keys, modifier)) { keys = DeckHotkey.toggling(keys, modifier) }
                }
            }
            TextBox(placeholder: "Win+Shift+S", text: $keys)
            LazyVGrid(columns: columns, alignment: .leading, spacing: 6) {
                ForEach(DeckHotkey.specialKeys, id: \.self) { key in
                    DeckChip(title: key, on: false) { keys = DeckHotkey.settingKey(keys, key) }
                }
            }
            note("Type a letter or number after the modifiers. For several steps, separate them with a space: Ctrl+K Ctrl+S.")
        }
    }

    private var controlFields: some View {
        VStack(spacing: 2) {
            ForEach(presets) { preset in
                Button { choose(preset) } label: {
                    HStack(spacing: 12) {
                        Image(systemName: preset.symbol).font(.system(size: 16)).frame(width: 26)
                        Text(preset.title).font(AppFont.body)
                        Spacer(minLength: 0)
                    }
                    .foregroundStyle(theme.textPrimary)
                    .padding(.horizontal, 10)
                    .frame(height: 44)
                    .background(RoundedRectangle(cornerRadius: Metrics.controlRadius, style: .continuous)
                        .fill(preset.id == controlID ? theme.controlFill : Color.clear))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    /// The PC's desktops by name, then next and previous. A numbered desktop's key lights up while
    /// that desktop is showing.
    private var desktopFields: some View {
        let desktops = ctx.connection.store.box("desktops").decoded(DesktopsState.self)?.desktops ?? []
        let targets = desktops.map { DeckDesktopTarget.index($0.index) } + [.previous, .next]
        return VStack(alignment: .leading, spacing: 2) {
            ForEach(targets, id: \.self) { target in
                Button { choose(target, desktops) } label: {
                    HStack(spacing: 12) {
                        Image(systemName: target.symbol).font(.system(size: 16)).frame(width: 26)
                        Text(target.title(desktops)).font(AppFont.body)
                        Spacer(minLength: 0)
                        if target == desktop { Image(systemName: "checkmark").font(.system(size: 14, weight: .semibold)).foregroundStyle(theme.accent) }
                    }
                    .foregroundStyle(theme.textPrimary)
                    .padding(.horizontal, 10)
                    .frame(height: 44)
                    .background(RoundedRectangle(cornerRadius: Metrics.controlRadius, style: .continuous)
                        .fill(target == desktop ? theme.controlFill : Color.clear))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            note("Switches desktops with Ctrl+Win+Left/Right, as many times as it takes. It works even when a full-screen remote desktop (Omnissa, RDP) has the keyboard. Add desktops on the PC with Win+Ctrl+D or Task View.")
                .padding(.top, 6)
        }
    }

    private var symbolFields: some View {
        VStack(alignment: .leading, spacing: 8) {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 44), spacing: 4)], spacing: 4) {
                ForEach(DeckSymbols.all, id: \.self) { name in
                    Button { symbol = name } label: {
                        Image(systemName: name)
                            .font(.system(size: 18))
                            .foregroundStyle(name == symbol ? theme.textOnAccent : theme.textPrimary)
                            .frame(width: 44, height: 44)
                            .background(Circle().fill(name == symbol ? theme.accent : theme.controlFillTertiary))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(name)
                }
            }
            TextBox(placeholder: "Or any SF Symbol name", text: $symbol)
        }
    }

    private var imageFields: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                if kind == .app, !target.trimmingCharacters(in: .whitespaces).isEmpty {
                    Button("Use the app’s icon") { useAppIcon() }
                        .buttonStyle(PillButtonStyle())
                }
                PhotosPicker(selection: $photo, matching: .images) {
                    Label("Choose a photo…", systemImage: "photo")
                }
                .buttonStyle(PillButtonStyle())
                .disabled(busy)
            }
            if icon == nil {
                note("Pick a photo to fill the key, or use the icon of the app it opens.")
            } else if iconAsset == nil {
                note("The icon will appear once the key is saved.")
            }
        }
    }

    // MARK: choices

    private func matches(_ apps: [DeckAppInfo]) -> [DeckAppInfo] {
        let query = search.trimmingCharacters(in: .whitespaces)
        return query.isEmpty ? apps : apps.filter { $0.name.localizedCaseInsensitiveContains(query) }
    }

    private func choose(_ app: DeckAppInfo) {
        target = app.path
        icon = app.path
        iconAsset = app.icon
        useImage = app.icon != nil
        if label.trimmingCharacters(in: .whitespaces).isEmpty { label = app.name }
    }

    private func choose(_ preset: DeckControlPreset) {
        controlID = preset.id
        symbol = preset.symbol
        useImage = false
        if label.trimmingCharacters(in: .whitespaces).isEmpty { label = preset.title }
    }

    private func choose(_ target: DeckDesktopTarget, _ desktops: [DesktopsState.Desktop]) {
        let previousTitle = desktop?.title(desktops)
        desktop = target
        symbol = target.symbol
        useImage = false
        let current = label.trimmingCharacters(in: .whitespaces)
        if current.isEmpty || current == previousTitle { label = target.title(desktops) }
    }

    private func useAppIcon() {
        let path = target.trimmingCharacters(in: .whitespaces)
        icon = path
        iconAsset = apps?.first { $0.path == path }?.icon
    }

    // MARK: host

    private func load() async {
        guard !loaded else { return }
        if let buttonId {
            do {
                let result = try await ctx.connection.invoke("deck", "getButton", ["buttonId": .string(buttonId)])
                guard let info = try result?.decode(ButtonInfo.self) else { throw HostError.action("The PC didn’t return that key.") }
                apply(info)
            } catch {
                ctx.connection.report(error)
                ctx.overlays.dismissDialog()
                return
            }
        }
        loaded = true
    }

    private func apply(_ info: ButtonInfo) {
        let key = info.button
        original = key
        index = info.index
        count = info.count
        label = key.label
        symbol = key.symbol ?? "app"
        icon = key.icon
        iconAsset = info.iconAsset
        useImage = key.icon != nil
        accent = key.style == "accent"

        let action = key.action
        switch action?["type"]?.string ?? "" {
        case "launch", "":
            kind = .app
            target = action?["target"]?.string ?? ""
        case "keys":
            kind = .hotkey
            keys = action?["keys"]?.string ?? ""
        case "url":
            kind = .link
            link = action?["target"]?.string ?? ""
        case "text":
            kind = .text
            text = action?["text"]?.string ?? ""
        case "builtin":
            let id = "\(action?["panel"]?.string ?? "").\(action?["action"]?.string ?? "")"
            if let target = DeckDesktopTarget(action: action) {
                kind = .desktop
                desktop = target
            } else if DeckControlPreset.all.contains(where: { $0.id == id }) {
                kind = .control
                controlID = id
            } else {
                kind = .other
            }
        default:
            kind = .other
        }
        originalKind = kind
    }

    private func loadApps() async {
        guard apps == nil else { return }
        do {
            let result = try await ctx.connection.invoke("deck", "listApps")
            apps = (try result?.decode(AppList.self))?.apps ?? []
        } catch {
            apps = []
        }
    }

    private func draft() -> DeckKeyDraft? {
        var key = DeckKeyDraft()
        key.label = label.trimmingCharacters(in: .whitespacesAndNewlines)
        key.style = accent ? "accent" : nil
        let name = symbol.trimmingCharacters(in: .whitespaces)
        key.symbol = name.isEmpty ? nil : name
        key.icon = useImage ? icon : nil
        // What lights the key up belongs to its action, so it only survives if the action's kind does.
        if kind == originalKind {
            key.state = original.state
            key.symbolOn = original.symbolOn
        }

        switch kind {
        case .app:
            var fields = original.action?["type"]?.string == "launch" ? (original.action?.object ?? [:]) : [:]
            fields["type"] = "launch"
            fields["target"] = .string(target.trimmingCharacters(in: .whitespaces))
            key.action = .object(fields)
        case .hotkey:
            key.action = .object(["type": "keys", "keys": .string(keys.trimmingCharacters(in: .whitespaces))])
        case .link:
            key.action = .object(["type": "url", "target": .string(link.trimmingCharacters(in: .whitespaces))])
        case .text:
            key.action = .object(["type": "text", "text": .string(text)])
        case .control:
            guard let preset = DeckControlPreset.all.first(where: { $0.id == controlID }) else {
                problem = "Choose what the key should control."
                return nil
            }
            key.action = .object(["type": "builtin", "panel": .string(preset.panel), "action": .string(preset.action)])
            key.state = preset.state
            key.symbolOn = preset.symbolOn
        case .desktop:
            guard let desktop else {
                problem = "Choose which desktop the key should show."
                return nil
            }
            key.action = desktop.action
            key.state = desktop.state
            key.symbolOn = nil
        case .other:
            key.action = original.action
        }
        return key
    }

    private func save() {
        problem = nil
        guard let key = draft() else { return }
        busy = true
        Task {
            do {
                let payload = try JSON.parse(JSONEncoder().encode(key))
                var args: [String: JSON] = ["pageId": .string(pageId), "button": payload]
                if let buttonId { args["buttonId"] = .string(buttonId) }
                try await ctx.connection.invoke("deck", "saveButton", args)
                ctx.overlays.dismissDialog()
            } catch {
                problem = DeckEditing.describe(error)
            }
            busy = false
        }
    }

    private func move(_ by: Int) {
        guard let buttonId else { return }
        busy = true
        Task {
            do {
                try await ctx.connection.invoke("deck", "moveButton", ["buttonId": .string(buttonId), "by": .number(Double(by))])
                index = min(max(index + by, 0), max(count - 1, 0))
            } catch {
                problem = DeckEditing.describe(error)
            }
            busy = false
        }
    }

    private func delete() {
        guard let buttonId else { return }
        busy = true
        Task {
            do {
                try await ctx.connection.invoke("deck", "deleteButton", ["buttonId": .string(buttonId)])
                ctx.overlays.dismissDialog()
            } catch {
                problem = DeckEditing.describe(error)
            }
            busy = false
        }
    }

    private func upload(_ item: PhotosPickerItem) async {
        busy = true
        problem = nil
        defer {
            busy = false
            photo = nil
        }
        guard let data = try? await item.loadTransferable(type: Data.self),
              let image = UIImage(data: data),
              let encoded = DeckIconImage.encode(image) else {
            problem = "That photo couldn’t be read."
            return
        }
        do {
            let result = try await ctx.connection.invoke("deck", "uploadIcon", ["data": .string(encoded.base64EncodedString())])
            icon = result?["icon"]?.string
            iconAsset = result?["iconAsset"]?.string
            useImage = icon != nil
        } catch {
            problem = DeckEditing.describe(error)
        }
    }
}

// MARK: - Pieces

/// The key as it will look on the board.
/// The key as it will look on the board: a module with its symbol and name, lit if set to be.
private struct DeckKeyPreview: View {
    let symbol: String
    let iconAsset: String?
    let fill: Bool
    let label: String
    let lit: Bool
    @Environment(\.theme) private var theme
    @Environment(AppSettings.self) private var settings

    var body: some View {
        let side: CGFloat = 140
        let shape = RoundedRectangle(cornerRadius: Metrics.panelRadius, style: .continuous)
        let ink: Color = lit ? (settings.litKeysUseAccent ? theme.textOnAccent : .black) : theme.textPrimary
        ZStack {
            if lit { shape.fill(settings.litKeysUseAccent ? theme.accent : .white) } else { ModuleSurface() }
            if let iconAsset, fill {
                RemoteImage(path: iconAsset, contentMode: .fill)
                    .frame(width: side, height: side)
                    .clipShape(shape)
            } else {
                Group {
                    if let iconAsset {
                        RemoteImage(path: iconAsset, contentMode: .fit) { Image(systemName: "app").font(.system(size: 30, weight: .medium)) }
                            .frame(width: 50, height: 50)
                            .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
                    } else {
                        Image(systemName: symbol.isEmpty ? "square.dashed" : symbol).font(.system(size: 30, weight: .medium))
                    }
                }
                .foregroundStyle(ink)
                .padding(.bottom, 20)
            }
        }
        .frame(width: side, height: side)
        .overlay(alignment: .bottom) {
            if settings.keyLabels {
                Text(label.isEmpty ? "Label" : label)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(fill && iconAsset != nil ? .white : ink.opacity(label.isEmpty ? 0.35 : 0.75))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    .padding(.horizontal, 10)
                    .padding(.bottom, 12)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Preview of the key")
    }
}

private struct DeckAppRow: View {
    let app: DeckAppInfo
    let selected: Bool
    let choose: () -> Void
    @Environment(\.theme) private var theme

    var body: some View {
        Button(action: choose) {
            HStack(spacing: 12) {
                RemoteImage(path: app.icon, contentMode: .fit) { Image(systemName: "app").font(.system(size: 18)) }
                    .frame(width: 26, height: 26)
                Text(app.name).font(AppFont.body).lineLimit(1)
                Spacer(minLength: 0)
                if selected { Image(systemName: "checkmark").font(.system(size: 13, weight: .semibold)) }
            }
            .foregroundStyle(theme.textPrimary)
            .padding(.horizontal, 10)
            .frame(height: 44)
            .background(RoundedRectangle(cornerRadius: Metrics.controlRadius, style: .continuous)
                .fill(selected ? theme.controlFill : Color.clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(app.name)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// A small toggle for modifiers and named keys.
private struct DeckChip: View {
    let title: String
    let on: Bool
    let action: () -> Void
    @Environment(\.theme) private var theme

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13, weight: on ? .semibold : .regular))
                .foregroundStyle(on ? theme.textOnAccent : theme.textPrimary)
                .lineLimit(1)
                .padding(.horizontal, 12)
                .frame(minWidth: 52, maxWidth: .infinity, minHeight: 36)
                .background(Capsule().fill(on ? theme.accent : theme.controlFill))
        }
        .buttonStyle(.plain)
    }
}

/// Renames a deck page.
struct DeckPageRenameDialog: View {
    let ctx: PanelContext
    let page: DeckPageModel
    @State private var name = ""

    var body: some View {
        DialogSheet(title: "Rename page",
                    cancel: DialogAction("Cancel") { ctx.overlays.dismissDialog() },
                    confirm: DialogAction("Save", enabled: !name.trimmingCharacters(in: .whitespaces).isEmpty) { save() }) {
            TextBox(placeholder: "Page name", text: $name) { save() }
        }
        .onAppear { name = page.title }
    }

    private func save() {
        let title = name.trimmingCharacters(in: .whitespaces)
        guard !title.isEmpty else { return }
        ctx.run("deck", "renamePage", ["pageId": .string(page.id), "title": .string(title)])
        ctx.overlays.dismissDialog()
    }
}
