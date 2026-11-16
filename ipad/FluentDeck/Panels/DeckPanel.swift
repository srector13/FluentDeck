import SwiftUI

/// The Stream Deck half: a page of keys defined in deck.json on the PC. While the board is being
/// customized, tapping a key edits it (if the PC allows that).
struct DeckPanel: View {
    let ctx: PanelContext

    static let spec = PanelSpec(
        kind: "deck",
        title: "Deck",
        summary: "A grid of keys that launch apps, send hotkeys, open links and run macros on your PC. Tap Customize, then a key, to change it.",
        symbol: "square.grid.3x3",
        requires: "deck",
        sizes: [.small, .medium, .large, .wide, .huge],
        defaultSize: .huge,
        defaultConfig: ["page": "main"],
        menu: { ctx in DeckPanel.menu(ctx) },
        editsInPlace: true,
        view: { AnyView(DeckPanel(ctx: $0)) })

    /// Pages, and (when the PC allows editing) adding keys and managing pages.
    static func menu(_ ctx: PanelContext) -> [FlyoutItem] {
        guard let deck = ctx.state("deck", as: DeckState.self), !deck.pages.isEmpty else { return [] }
        let current = DeckPanel.page(in: deck, ctx: ctx)
        let canEdit = DeckEditing.canEdit(ctx, deck)
        var items: [FlyoutItem] = []
        if canEdit, let page = current {
            items.append(.action("Add key…", symbol: "plus") { DeckEditing.editKey(ctx, pageId: page.id, buttonId: nil) })
            items.append(.separator)
        }
        items.append(.header("Page"))
        items += deck.pages.map { p in FlyoutItem.action(p.title, checked: p.id == current?.id) { ctx.updateConfig("page", p.id) } }
        if canEdit {
            items.append(.action("New page", symbol: "plus.rectangle.on.rectangle") { DeckEditing.addPage(ctx) })
            if let page = current {
                items.append(.action("Rename page…", symbol: "pencil") { ctx.overlays.present { DeckPageRenameDialog(ctx: ctx, page: page) } })
                if deck.pages.count > 1 {
                    items.append(.action("Delete page", symbol: "trash", destructive: true) {
                        ctx.run("deck", "deletePage", ["pageId": .string(page.id)])
                    })
                }
            }
        }
        items.append(.separator)
        items.append(.action("Reload deck.json", symbol: "arrow.clockwise") { ctx.run("deck", "reload") })
        return items
    }

    static func page(in deck: DeckState, ctx: PanelContext) -> DeckPageModel? {
        deck.pages.first { $0.id == ctx.config["page"] } ?? deck.pages.first
    }

    @Environment(\.fluent) private var theme

    var body: some View {
        if let deck = ctx.state("deck", as: DeckState.self) {
            VStack(spacing: 8) {
                if let error = deck.error {
                    InfoBar(severity: .warning, title: "deck.json has an error", message: error)
                }
                if let page = Self.page(in: deck, ctx: ctx) {
                    if page.buttons.isEmpty {
                        emptyPage(page, deck)
                    } else {
                        DeckGrid(ctx: ctx, page: page, deck: deck)
                    }
                } else {
                    PanelEmptyState(symbol: "square.grid.3x3", text: "No pages in deck.json")
                }
            }
        } else {
            PanelEmptyState(symbol: "square.grid.3x3", text: "Deck unavailable")
        }
    }
}

extension DeckPanel {
    @ViewBuilder
    fileprivate func emptyPage(_ page: DeckPageModel, _ deck: DeckState) -> some View {
        if DeckEditing.canEdit(ctx, deck) {
            VStack(spacing: 12) {
                PanelEmptyState(symbol: "square.grid.3x3", text: "No keys on this page yet").frame(maxHeight: 90)
                Button { DeckEditing.editKey(ctx, pageId: page.id, buttonId: nil) } label: { Label("Add key", systemImage: "plus") }
                    .buttonStyle(FluentButtonStyle(kind: .accent))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            PanelEmptyState(symbol: "square.grid.3x3", text: "No keys on this page")
        }
    }
}

/// Sizes the keys so a page fills its widget: the column count that gives the largest tiles
/// without scrolling, unless deck.json fixes `columns`. Width beyond a key-like shape doesn't
/// count, so a page becomes a grid of keys rather than a stack of wide bars.
private enum DeckLayout {
    static let gap: CGFloat = 16
    static let rowGap: CGFloat = 12
    static let labelGap: CGFloat = 9
    static let labelHeight: CGFloat = 18
    /// Height of a quick settings tile relative to its width.
    static let aspect: CGFloat = 0.87

    struct Fit {
        var columns: Int
        var tile: CGSize
        var scrolls: Bool
    }

    static func fit(count: Int, in size: CGSize, fixedColumns: Int?) -> Fit {
        let n = max(count, 1)

        func width(_ columns: Int) -> CGFloat {
            max(1, (size.width - CGFloat(columns - 1) * gap) / CGFloat(columns))
        }
        func tile(_ columns: Int) -> CGSize {
            let w = width(columns)
            let rows = (n + columns - 1) / columns
            let cell = (size.height - CGFloat(rows - 1) * rowGap) / CGFloat(rows)
            return CGSize(width: w, height: min(cell - labelGap - labelHeight, w * aspect))
        }
        func scrolling(_ columns: Int) -> Fit {
            let w = width(columns)
            return Fit(columns: columns, tile: CGSize(width: w, height: max(44, w * aspect)), scrolls: true)
        }

        if let fixed = fixedColumns, fixed > 0 {
            let t = tile(fixed)
            return t.height >= 44 ? Fit(columns: fixed, tile: t, scrolls: false) : scrolling(fixed)
        }

        var best: Fit?
        var bestScore: CGFloat = 0
        for columns in 1...min(n, 12) {
            let t = tile(columns)
            guard t.width >= 56, t.height >= 44 else { continue }
            let score = min(t.width, t.height * 1.6) * t.height
            if score > bestScore {
                bestScore = score
                best = Fit(columns: columns, tile: t, scrolls: false)
            }
        }
        return best ?? scrolling(max(1, Int((size.width + gap) / (84 + gap))))
    }
}

private struct DeckGrid: View {
    let ctx: PanelContext
    let page: DeckPageModel
    let deck: DeckState

    var body: some View {
        GeometryReader { g in
            let fit = DeckLayout.fit(count: page.buttons.count, in: g.size, fixedColumns: page.columns)
            ScrollView(.vertical) {
                LazyVGrid(columns: Array(repeating: GridItem(.fixed(fit.tile.width), spacing: DeckLayout.gap), count: fit.columns),
                          spacing: DeckLayout.rowGap) {
                    ForEach(page.buttons) { button in
                        DeckKey(ctx: ctx, button: button, tile: fit.tile, page: page, deck: deck)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollDisabled(!fit.scrolls)
            .scrollClipDisabled(!fit.scrolls) // a lit key's glow isn't cut off at the edge
            .scrollIndicators(.hidden)
        }
    }
}

/// A deck key drawn as a quick settings toggle: a soft, borderless tile with its label underneath.
/// While it is on it fills with the accent and glows.
private struct DeckKey: View {
    let ctx: PanelContext
    let button: DeckButtonModel
    let tile: CGSize
    let page: DeckPageModel
    let deck: DeckState

    @Environment(\.fluent) private var theme
    @State private var running = false
    @State private var failed = false
    @State private var presses = 0

    /// Live binding: lit when topic.path equals the configured value (default true).
    private var isOn: Bool {
        guard let b = button.state else { return false }
        let value = ctx.box(b.topic).value?.value(at: b.path)
        return value == (b.equals ?? .bool(true))
    }

    var body: some View {
        let on = isOn
        let lit = on || button.style == "accent"
        let shape = RoundedRectangle(cornerRadius: min(Fluent.tileRadius, tile.height * 0.2), style: .continuous)
        let glyph = min(max(tile.height * 0.3, 18), 44)
        Button(action: ctx.editing ? edit : press) {
            VStack(spacing: DeckLayout.labelGap) {
                ZStack {
                    if lit {
                        shape.fill(theme.accent)
                            .shadow(color: theme.accent.opacity(0.45), radius: 22)
                    } else {
                        shape.fill(theme.tileFill)
                    }
                    if failed { shape.strokeBorder(theme.critical, lineWidth: 2) }
                    if let icon = button.icon, button.iconFill == true {
                        // A picture fills the key, as on a Stream Deck.
                        RemoteImage(path: icon, contentMode: .fill)
                            .frame(width: tile.width, height: tile.height)
                            .clipShape(shape)
                    } else if let icon = button.icon {
                        RemoteImage(path: icon, contentMode: .fit) {
                            Image(systemName: button.symbol ?? "app").font(.system(size: glyph))
                        }
                        .frame(width: glyph * 1.3, height: glyph * 1.3)
                    } else {
                        Image(systemName: (on ? button.symbolOn : nil) ?? button.symbol ?? "square.dashed")
                            .font(.system(size: glyph, weight: .regular))
                            .contentTransition(.symbolEffect(.replace))
                    }
                }
                .foregroundStyle(lit ? theme.textOnAccent : theme.textPrimary)
                .frame(width: tile.width, height: tile.height)
                .overlay(alignment: .topTrailing) {
                    if ctx.editing {
                        Image(systemName: "pencil")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(theme.textPrimary)
                            .frame(width: 24, height: 24)
                            .background(Circle().fill(theme.controlSolidFill))
                            .padding(8)
                    } else if running {
                        FluentProgressRing(size: 12, lineWidth: 2).padding(8)
                    }
                }
                Text(button.label)
                    .font(.system(size: 13))
                    .foregroundStyle(lit ? theme.textPrimary : theme.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    .frame(width: tile.width, height: DeckLayout.labelHeight)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(DeckKeyStyle())
        .animation(.easeOut(duration: 0.2), value: lit)
        .sensoryFeedback(.impact(weight: .light), trigger: presses)
        .accessibilityLabel(button.label)
        .accessibilityHint(ctx.editing ? "Edits this key" : "")
    }

    private func edit() {
        if let reason = DeckEditing.blocked(ctx, deck) {
            ctx.connection.report(HostError.action(reason))
        } else {
            DeckEditing.editKey(ctx, pageId: page.id, buttonId: button.id)
        }
    }

    private func press() {
        presses += 1
        running = true
        Task { @MainActor in
            do {
                try await ctx.connection.invoke("deck", "press", ["buttonId": .string(button.id)])
            } catch {
                ctx.connection.report(error)
                withAnimation { failed = true }
                try? await Task.sleep(nanoseconds: 900_000_000)
                withAnimation { failed = false }
            }
            running = false
        }
    }
}

/// Press feedback for a key: it dips and dims under the finger.
private struct DeckKeyStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .opacity(configuration.isPressed ? 0.8 : 1)
            .animation(.snappy(duration: 0.12), value: configuration.isPressed)
    }
}
