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
        sizes: [.small, .medium, .large, .wide],
        defaultSize: .wide,
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

private struct DeckGrid: View {
    let ctx: PanelContext
    let page: DeckPageModel

    private let gap: CGFloat = 10
    private let minKey: CGFloat = 78
    private let maxKey: CGFloat = 116

    var body: some View {
        GeometryReader { g in
            let columns = page.columns ?? max(1, Int((g.size.width + gap) / (minKey + gap)))
            let side = min(maxKey, (g.size.width - CGFloat(columns - 1) * gap) / CGFloat(columns))
            let rowsFit = max(1, Int((g.size.height + gap) / (side + gap)))
            let needsScroll = (page.buttons.count + columns - 1) / columns > rowsFit
            ScrollView(.vertical) {
                LazyVGrid(columns: Array(repeating: GridItem(.fixed(side), spacing: gap), count: columns), spacing: gap) {
                    ForEach(page.buttons) { button in
                        DeckKey(ctx: ctx, button: button, side: side)
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .scrollDisabled(!needsScroll)
            .scrollIndicators(.hidden)
        }
    }
}

private struct DeckKey: View {
    let ctx: PanelContext
    let button: DeckButtonModel
    let side: CGFloat

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
        Button(action: press) {
            VStack(spacing: side * 0.07) {
                if let icon = button.icon {
                    RemoteImage(path: icon, contentMode: .fit) {
                        Image(systemName: button.symbol ?? "app").font(.system(size: side * 0.28))
                    }
                    .frame(width: side * 0.38, height: side * 0.38)
                } else {
                    Image(systemName: (on ? button.symbolOn : nil) ?? button.symbol ?? "square.dashed")
                        .font(.system(size: side * 0.27, weight: .regular))
                        .contentTransition(.symbolEffect(.replace))
                        .frame(height: side * 0.38)
                }
                Text(button.label)
                    .font(.system(size: max(11, side * 0.12), weight: .medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .padding(.horizontal, 4)
            }
            .frame(width: side, height: side)
        }
        .buttonStyle(DeckKeyStyle(lit: lit, failed: failed))
        .overlay(alignment: .topTrailing) {
            if running { FluentProgressRing(size: 12, lineWidth: 2).padding(7) }
        }
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

/// A Stream Deck key drawn with Fluent materials: card fill + elevation border, accent when lit.
private struct DeckKeyStyle: ButtonStyle {
    let lit: Bool
    let failed: Bool

    func makeBody(configuration: Configuration) -> some View {
        KeyBody(configuration: configuration, lit: lit, failed: failed)
    }

    struct KeyBody: View {
        let configuration: ButtonStyleConfiguration
        let lit: Bool
        let failed: Bool
        @Environment(\.fluent) private var theme

        var body: some View {
            let pressed = configuration.isPressed
            let shape = RoundedRectangle(cornerRadius: Fluent.overlayRadius + 2, style: .continuous)
            configuration.label
                .foregroundStyle(lit ? theme.textOnAccent : theme.textPrimary)
                .background(shape.fill(lit ? (pressed ? theme.accentTertiary : theme.accent)
                                           : (pressed ? theme.controlFillTertiary : theme.controlFillSecondary)))
                .overlay(shape.strokeBorder(
                    failed ? AnyShapeStyle(theme.critical)
                           : AnyShapeStyle(LinearGradient(colors: [theme.controlStrokeTop, theme.controlStrokeBottom], startPoint: .top, endPoint: .bottom)),
                    lineWidth: failed ? 2 : 1))
                .shadow(color: .black.opacity(pressed ? 0 : (theme.isDark ? 0.25 : 0.08)), radius: pressed ? 0 : 3, y: pressed ? 0 : 2)
                .scaleEffect(pressed ? 0.95 : 1)
                .animation(.snappy(duration: 0.12), value: pressed)
                .animation(.easeOut(duration: 0.2), value: lit)
        }
    }
}
