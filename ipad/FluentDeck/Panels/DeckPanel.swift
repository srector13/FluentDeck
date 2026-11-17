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
        bare: true,
        view: { AnyView(DeckPanel(ctx: $0)) })

    /// Pages, and (when the PC allows editing) adding keys and managing pages.
    static func menu(_ ctx: PanelContext) -> [ActionItem] {
        guard let deck = ctx.state("deck", as: DeckState.self), !deck.pages.isEmpty else { return [] }
        let current = DeckPanel.page(in: deck, ctx: ctx)
        let canEdit = DeckEditing.canEdit(ctx, deck)
        var items: [ActionItem] = []
        if canEdit, let page = current {
            items.append(.action("Add key…", symbol: "plus") { DeckEditing.editKey(ctx, pageId: page.id, buttonId: nil) })
            items.append(.separator)
        }
        items.append(.header("Page"))
        items += deck.pages.map { p in ActionItem.action(p.title, checked: p.id == current?.id) { ctx.updateConfig("page", p.id) } }
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

    @Environment(\.theme) private var theme

    var body: some View {
        if let deck = ctx.state("deck", as: DeckState.self) {
            if let page = Self.page(in: deck, ctx: ctx), !page.buttons.isEmpty {
                VStack(spacing: Metrics.gutter) {
                    if let error = deck.error {
                        Banner(severity: .warning, title: "deck.json has an error", message: error)
                    }
                    DeckGrid(ctx: ctx, page: page, deck: deck)
                }
            } else {
                // The keys are the deck's modules; without any, it sits on one of its own.
                VStack(spacing: 8) {
                    if let error = deck.error {
                        Banner(severity: .warning, title: "deck.json has an error", message: error)
                    }
                    if let page = Self.page(in: deck, ctx: ctx) {
                        emptyPage(page, deck)
                    } else {
                        PanelEmptyState(symbol: "square.grid.3x3", text: "No pages in deck.json")
                    }
                }
                .module()
            }
        } else {
            PanelEmptyState(symbol: "square.grid.3x3", text: "Deck unavailable").module()
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
                    .buttonStyle(PillButtonStyle(kind: .accent))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            PanelEmptyState(symbol: "square.grid.3x3", text: "No keys on this page")
        }
    }
}

/// Lays a page of keys out on the board's own rhythm: keys are modules, as far apart as modules
/// are, and together they fill the space the deck was given. A 4 × 3 deck of twelve keys puts one
/// key in each cell of the board. The column count that gives the largest keys wins, unless
/// deck.json fixes `columns`; keys stay within a modest aspect ratio, centred if that leaves room.
private enum DeckLayout {
    static let gap = Metrics.gutter
    /// How far a key may stretch from square.
    static let maxAspect: CGFloat = 1.25
    /// Below this a key is too small to hit reliably, and the page scrolls instead.
    static let minSide: CGFloat = 64

    struct Fit {
        var columns: Int
        var key: CGSize
        var scrolls: Bool
    }

    static func fit(count: Int, in size: CGSize, fixedColumns: Int?) -> Fit {
        let n = max(count, 1)

        func key(_ columns: Int) -> CGSize {
            let rows = (n + columns - 1) / columns
            var w = (size.width - CGFloat(columns - 1) * gap) / CGFloat(columns)
            var h = (size.height - CGFloat(rows - 1) * gap) / CGFloat(rows)
            w = min(w, h * maxAspect)
            h = min(h, w * maxAspect)
            return CGSize(width: max(1, w), height: max(1, h))
        }
        func scrolling(_ columns: Int) -> Fit {
            let w = max(minSide, (size.width - CGFloat(columns - 1) * gap) / CGFloat(columns))
            return Fit(columns: columns, key: CGSize(width: w, height: w), scrolls: true)
        }

        if let fixed = fixedColumns, fixed > 0 {
            let k = key(fixed)
            return min(k.width, k.height) >= minSide ? Fit(columns: fixed, key: k, scrolls: false) : scrolling(fixed)
        }

        var best: Fit?
        var bestScore: CGFloat = 0
        for columns in 1...min(n, 12) {
            let k = key(columns)
            let side = min(k.width, k.height)
            guard side >= minSide else { continue }
            // Prefer bigger keys; among near-equals, the layout that wastes the least of the space.
            let used = CGFloat(n) * k.width * k.height / max(1, size.width * size.height)
            let score = side * (0.85 + 0.15 * min(1, used))
            if score > bestScore {
                bestScore = score
                best = Fit(columns: columns, key: k, scrolls: false)
            }
        }
        return best ?? scrolling(max(1, Int((size.width + gap) / (96 + gap))))
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
                LazyVGrid(columns: Array(repeating: GridItem(.fixed(fit.key.width), spacing: DeckLayout.gap), count: fit.columns),
                          spacing: DeckLayout.gap) {
                    ForEach(page.buttons) { button in
                        DeckKey(ctx: ctx, button: button, size: fit.key, page: page, deck: deck)
                    }
                }
                // A page with room to spare sits in the middle of the space.
                .frame(maxWidth: .infinity, minHeight: fit.scrolls ? nil : g.size.height, alignment: .center)
            }
            .scrollDisabled(!fit.scrolls)
            .scrollIndicators(.hidden)
            .scrollClipDisabled()
        }
    }
}

/// A deck key drawn as a Control Center module: the board's translucent surface with the symbol
/// in the middle and the name along the bottom. While it is on it lights up white (or in the
/// accent colour), as Control Center's toggles do.
private struct DeckKey: View {
    let ctx: PanelContext
    let button: DeckButtonModel
    let size: CGSize
    let page: DeckPageModel
    let deck: DeckState

    @Environment(\.theme) private var theme
    @Environment(AppSettings.self) private var settings
    @State private var running = false
    @State private var failed = false
    @State private var presses = 0

    /// Live binding: lit when topic.path equals the configured value (default true).
    private var isOn: Bool {
        guard let b = button.state else { return false }
        let value = ctx.box(b.topic).value?.value(at: b.path)
        return value == (b.equals ?? .bool(true))
    }

    private var side: CGFloat { min(size.width, size.height) }
    private var radius: CGFloat { min(Metrics.panelRadius, side * 0.22) }
    private var showsLabel: Bool { settings.keyLabels && side >= 76 && !button.label.isEmpty }

    var body: some View {
        let on = isOn
        let lit = on || button.style == "accent"
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        let litFill = settings.litKeysUseAccent ? theme.accent : Color.white
        let ink: Color = lit ? (settings.litKeysUseAccent ? theme.textOnAccent : .black) : theme.textPrimary
        Button(action: ctx.editing ? edit : press) {
            ZStack {
                if lit { shape.fill(litFill) } else { ModuleSurface(radius: radius) }
                face(on: on, ink: ink, shape: shape)
                if failed { shape.strokeBorder(theme.critical, lineWidth: 2) }
            }
            .frame(width: size.width, height: size.height)
            .overlay(alignment: .topTrailing) {
                if running && !ctx.editing {
                    ProgressView().controlSize(.small).tint(ink).padding(10)
                }
            }
            .overlay(alignment: .topTrailing) {
                if ctx.editing {
                    Image(systemName: "pencil")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(theme.textPrimary)
                        .frame(width: 24, height: 24)
                        .background(Circle().fill(theme.controlSolidFill))
                        .offset(x: 6, y: -6)
                }
            }
            .contentShape(shape)
        }
        .buttonStyle(DeckKeyStyle())
        .animation(.easeOut(duration: 0.2), value: lit)
        .sensoryFeedback(trigger: presses) { _, _ in settings.haptics ? .impact(weight: .light) : nil }
        .accessibilityLabel(button.label)
        .accessibilityHint(ctx.editing ? "Edits this key" : "")
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    /// The symbol or picture, and the name under it.
    @ViewBuilder
    private func face(on: Bool, ink: Color, shape: RoundedRectangle) -> some View {
        let glyph = min(max(side * 0.2, 20), 40)
        let labelSize: CGFloat = side >= 140 ? 14 : 12
        let labelSpace: CGFloat = showsLabel ? labelSize + 18 : 0
        if let icon = button.icon, button.iconFill == true {
            // A picture fills the key, as on a Stream Deck; the name sits on a shade at its foot.
            RemoteImage(path: icon, contentMode: .fill)
                .frame(width: size.width, height: size.height)
                .clipShape(shape)
                .overlay(alignment: .bottom) {
                    if showsLabel {
                        label(size: labelSize, color: .white)
                            .padding(.top, 18)
                            .frame(maxWidth: .infinity)
                            .background(LinearGradient(colors: [.clear, .black.opacity(0.55)], startPoint: .top, endPoint: .bottom))
                            .clipShape(shape)
                    }
                }
        } else {
            VStack(spacing: 0) {
                Spacer(minLength: 0)
                Group {
                    if let icon = button.icon {
                        // An app's own icon, shaped like one on the Home Screen.
                        let s = min(side * 0.36, 72)
                        RemoteImage(path: icon, contentMode: .fit) {
                            Image(systemName: button.symbol ?? "app").font(.system(size: glyph, weight: .medium))
                        }
                        .frame(width: s, height: s)
                        .clipShape(RoundedRectangle(cornerRadius: s * 0.22, style: .continuous))
                    } else {
                        Image(systemName: (on ? button.symbolOn : nil) ?? button.symbol ?? "square.dashed")
                            .font(.system(size: glyph, weight: .medium))
                            .contentTransition(.symbolEffect(.replace))
                    }
                }
                .foregroundStyle(ink)
                Spacer(minLength: 0)
            }
            .padding(.bottom, labelSpace * 0.6)
            .frame(width: size.width, height: size.height)
            .overlay(alignment: .bottom) {
                if showsLabel { label(size: labelSize, color: ink.opacity(on || button.style == "accent" ? 0.8 : 0.72)) }
            }
        }
    }

    private func label(size: CGFloat, color: Color) -> some View {
        Text(button.label)
            .font(.system(size: size, weight: .semibold))
            .foregroundStyle(color)
            .lineLimit(1)
            .minimumScaleFactor(0.75)
            .padding(.horizontal, 10)
            .padding(.bottom, 12)
    }

    private func edit() {
        if let reason = DeckEditing.blocked(ctx, deck) {
            ctx.connection.report(HostError.action(reason))
        } else {
            DeckEditing.editKey(ctx, pageId: page.id, buttonId: button.id)
        }
    }

    private func press() {
        // The finger was swiping to another board, not pressing this key.
        guard !TouchArbiter.swipeInProgress else { return }
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
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(.snappy(duration: 0.12), value: configuration.isPressed)
    }
}
