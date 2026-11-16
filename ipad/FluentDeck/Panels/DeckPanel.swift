import SwiftUI

/// The Stream Deck half: a page of buttons defined in deck.json on the PC.
struct DeckPanel: View {
    let ctx: PanelContext

    static let spec = PanelSpec(
        kind: "deck",
        title: "Deck",
        summary: "A grid of buttons from deck.json on your PC — launch apps, send hotkeys, run macros. Edit the file and the buttons update live.",
        symbol: "square.grid.3x3",
        requires: "deck",
        sizes: [.small, .medium, .large, .wide, .huge],
        defaultSize: .huge,
        defaultConfig: ["page": "main"],
        menu: { ctx in
            guard let deck = ctx.state("deck", as: DeckState.self), !deck.pages.isEmpty else { return [] }
            let current = DeckPanel.page(in: deck, ctx: ctx)?.id
            return [FlyoutItem.header("Page")]
                + deck.pages.map { p in FlyoutItem.action(p.title, checked: p.id == current) { ctx.updateConfig("page", p.id) } }
                + [FlyoutItem.separator, FlyoutItem.action("Reload deck.json", symbol: "arrow.clockwise") { ctx.run("deck", "reload") }]
        },
        view: { AnyView(DeckPanel(ctx: $0)) })

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
                    DeckGrid(ctx: ctx, page: page)
                } else {
                    PanelEmptyState(symbol: "square.grid.3x3", text: "No pages in deck.json")
                }
            }
        } else {
            PanelEmptyState(symbol: "square.grid.3x3", text: "Deck unavailable")
        }
    }
}

/// Sizes the keys so a page fills its panel: the column count that gives the largest tiles
/// (by area) without scrolling, unless deck.json fixes `columns`.
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
            let score = t.width * t.height
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

    var body: some View {
        GeometryReader { g in
            let fit = DeckLayout.fit(count: page.buttons.count, in: g.size, fixedColumns: page.columns)
            ScrollView(.vertical) {
                LazyVGrid(columns: Array(repeating: GridItem(.fixed(fit.tile.width), spacing: DeckLayout.gap), count: fit.columns),
                          spacing: DeckLayout.rowGap) {
                    ForEach(page.buttons) { button in
                        DeckKey(ctx: ctx, button: button, tile: fit.tile)
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
        Button(action: press) {
            VStack(spacing: DeckLayout.labelGap) {
                ZStack {
                    if lit {
                        shape.fill(theme.accent)
                            .shadow(color: theme.accent.opacity(0.45), radius: 22)
                    } else {
                        shape.fill(theme.tileFill)
                    }
                    if failed { shape.strokeBorder(theme.critical, lineWidth: 2) }
                    if let icon = button.icon {
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
                    if running { FluentProgressRing(size: 12, lineWidth: 2).padding(8) }
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
