import SwiftUI
import Observation

// Menus and sheets are the system's own. This file describes them as data (so a panel can offer
// a menu without drawing one) and owns the two things the app presents over a board: a dialog in
// a system sheet, and the drawer that slides up from the bottom edge with the rest of a compact
// widget's controls.

/// One row of a menu, or a divider or heading between rows.
struct ActionItem: Identifiable {
    enum Kind {
        case action(title: String, symbol: String?, checked: Bool?, destructive: Bool, perform: () -> Void)
        case separator
        case header(String)
    }

    let id = UUID()
    let kind: Kind

    /// `checked: nil` → plain item; `true` shows a checkmark, `false` leaves room for one.
    static func action(_ title: String, symbol: String? = nil, checked: Bool? = nil, destructive: Bool = false,
                       perform: @escaping () -> Void) -> ActionItem {
        ActionItem(kind: .action(title: title, symbol: symbol, checked: checked, destructive: destructive, perform: perform))
    }
    static var separator: ActionItem { ActionItem(kind: .separator) }
    static func header(_ title: String) -> ActionItem { ActionItem(kind: .header(title)) }
}

/// A button that opens a system menu built from `ActionItem`s.
struct ActionMenu<Label: View>: View {
    let items: () -> [ActionItem]
    @ViewBuilder let label: () -> Label

    var body: some View {
        Menu {
            ActionMenuContent(items: items())
        } label: {
            label()
        }
        .menuOrder(.fixed)
    }
}

/// The rows of a menu: separators and headers become sections.
struct ActionMenuContent: View {
    let items: [ActionItem]

    private struct Block: Identifiable {
        var id: Int
        var title: String?
        var rows: [ActionItem] = []
    }

    var body: some View {
        ForEach(Self.groups(items)) { group in
            if let title = group.title {
                Section(title) { rows(group.rows) }
            } else {
                Section { rows(group.rows) }
            }
        }
    }

    @ViewBuilder
    private func rows(_ rows: [ActionItem]) -> some View {
        ForEach(rows) { item in
            if case let .action(title, symbol, checked, destructive, perform) = item.kind {
                Button(role: destructive ? .destructive : nil, action: perform) {
                    if checked == true {
                        SwiftUI.Label(title, systemImage: "checkmark")
                    } else if let symbol {
                        SwiftUI.Label(title, systemImage: symbol)
                    } else {
                        Text(title)
                    }
                }
            }
        }
    }

    private static func groups(_ items: [ActionItem]) -> [Block] {
        var groups = [Block(id: 0)]
        for item in items {
            switch item.kind {
            case .action:
                groups[groups.count - 1].rows.append(item)
            case .separator:
                groups.append(Block(id: groups.count))
            case .header(let title):
                if groups[groups.count - 1].rows.isEmpty {
                    groups[groups.count - 1].title = title
                } else {
                    groups.append(Block(id: groups.count, title: title))
                }
            }
        }
        return groups.filter { !$0.rows.isEmpty }
    }
}

@MainActor
@Observable
final class OverlayCenter {
    /// How large a dialog's sheet is: just tall enough for its content, or a full page.
    enum SheetSize { case fitted, page }

    struct Dialog: Identifiable {
        let id = UUID()
        var size: SheetSize
        var content: AnyView
    }

    struct Drawer: Identifiable {
        let id = UUID()
        var title: String
        var content: AnyView
    }

    /// The dialog on screen, if any. The root view presents it as a sheet.
    var dialog: Dialog?
    /// The drawer on screen, if any. The root view slides it up from the bottom edge.
    var drawer: Drawer?

    func present<V: View>(size: SheetSize = .fitted, @ViewBuilder _ content: () -> V) {
        dialog = Dialog(size: size, content: AnyView(content()))
    }

    func dismissDialog() {
        dialog = nil
    }

    /// Slide a card up from the bottom of the board with the rest of a widget's controls.
    func openDrawer<V: View>(title: String, @ViewBuilder _ content: () -> V) {
        drawer = Drawer(title: title, content: AnyView(content()))
    }

    func closeDrawer() {
        drawer = nil
    }
}

extension View {
    /// Present the app's dialog as a system sheet and its drawer as a card that slides up from the
    /// bottom edge. `scope` re-applies the app's environment, which both need as much as the
    /// screen beneath them.
    func overlaySheets<Scoped: View>(_ overlays: OverlayCenter, scope: @escaping (AnyView) -> Scoped) -> some View {
        self
            .overlay { scope(AnyView(DrawerLayer())) }
            .sheet(item: Binding(get: { overlays.dialog }, set: { overlays.dialog = $0 })) { dialog in
                scope(AnyView(DialogHost(dialog: dialog)))
            }
    }

    /// Size the sheet to its content's height.
    func fittedSheet() -> some View { modifier(FittedSheet()) }

    /// A page-sized sheet where the system can size sheets (iOS 18); the default form sheet before.
    @ViewBuilder
    func pageSheet() -> some View {
        if #available(iOS 18.0, *) {
            presentationSizing(.page)
        } else {
            self
        }
    }
}

/// Measures the content and gives the sheet one detent of exactly that height.
private struct FittedSheet: ViewModifier {
    @State private var height: CGFloat = 320

    func body(content: Content) -> some View {
        content
            .fixedSize(horizontal: false, vertical: true)
            .onGeometryChange(for: CGFloat.self) { proxy in
                proxy.size.height
            } action: { new in
                height = new
            }
            .frame(maxHeight: .infinity, alignment: .top)
            .presentationDetents([.height(max(height, 120))])
    }
}

private struct DialogHost: View {
    let dialog: OverlayCenter.Dialog

    var body: some View {
        switch dialog.size {
        case .fitted:
            dialog.content
                .fittedSheet()
                .presentationDragIndicator(.hidden)
        case .page:
            dialog.content
                .pageSheet()
        }
    }
}

// MARK: - Drawer

/// Dims the board and holds the drawer at its bottom edge. Tapping outside the drawer closes it.
private struct DrawerLayer: View {
    @Environment(OverlayCenter.self) private var overlays

    var body: some View {
        ZStack(alignment: .bottom) {
            if let drawer = overlays.drawer {
                Color.black.opacity(0.35)
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture { overlays.closeDrawer() }
                    .accessibilityHidden(true)
                    .transition(.opacity)
                    .zIndex(0)
                DrawerCard(drawer: drawer)
                    .id(drawer.id)
                    .transition(.move(edge: .bottom))
                    .zIndex(1)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .ignoresSafeArea(edges: .bottom)
        .animation(.spring(response: 0.38, dampingFraction: 0.88), value: overlays.drawer?.id)
    }
}

/// The drawer itself: a grabber, the widget's name, a close button, and the widget's full
/// controls, on a card as tall as they need. Drag its top down to put it away.
private struct DrawerCard: View {
    let drawer: OverlayCenter.Drawer
    @Environment(OverlayCenter.self) private var overlays
    @Environment(\.theme) private var theme
    @State private var drag: CGFloat = 0

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 34, style: .continuous)
        VStack(alignment: .leading, spacing: 10) {
            header
            drawer.content
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 22)
        .frame(maxWidth: 640)
        .fixedSize(horizontal: false, vertical: true)
        .background(shape.fill(.regularMaterial))
        .shadow(color: .black.opacity(0.35), radius: 30, y: 10)
        .padding(.horizontal, 16)
        .padding(.bottom, 16)
        .offset(y: drag)
    }

    private var header: some View {
        VStack(spacing: 4) {
            Capsule()
                .fill(theme.textTertiary)
                .frame(width: 36, height: 5)
                .padding(.top, 8)
                .accessibilityHidden(true)
            HStack {
                Text(drawer.title).font(AppFont.subtitle).foregroundStyle(theme.textPrimary)
                Spacer()
                Button { overlays.closeDrawer() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(theme.textSecondary)
                        .frame(width: 30, height: 30)
                        .background(Circle().fill(theme.controlFill))
                        .frame(width: Metrics.touchTarget, height: Metrics.touchTarget)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.trailing, -7)
                .accessibilityLabel("Close")
            }
        }
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 6)
                .onChanged { drag = max(0, $0.translation.height) }
                .onEnded { value in
                    if value.translation.height > 90 || value.predictedEndTranslation.height > 260 {
                        overlays.closeDrawer()
                    } else {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { drag = 0 }
                    }
                })
    }
}

// MARK: - Dialog

/// One of a dialog's two buttons.
struct DialogAction {
    var title: String
    var enabled: Bool
    var perform: () -> Void

    init(_ title: String, enabled: Bool = true, perform: @escaping () -> Void) {
        self.title = title
        self.enabled = enabled
        self.perform = perform
    }
}

/// The layout of a dialog. A small one is a title, its content, and Cancel beside the main action.
/// One that fills a page sheet has a bar across the top instead, in the manner of an iOS sheet:
/// Cancel on the left, the title in the middle, the main action on the right.
struct DialogSheet<Content: View>: View {
    var title: String
    /// Stretch the content to fill a page sheet under a top bar.
    var fills = false
    var cancel: DialogAction
    var confirm: DialogAction
    @ViewBuilder var content: () -> Content
    @Environment(\.theme) private var theme

    var body: some View {
        if fills {
            VStack(spacing: 0) {
                ZStack {
                    Text(title).font(.system(size: 17, weight: .semibold)).foregroundStyle(theme.textPrimary)
                    HStack {
                        Button(cancel.title, action: cancel.perform)
                            .buttonStyle(PillButtonStyle())
                        Spacer()
                        Button(confirm.title, action: confirm.perform)
                            .buttonStyle(PillButtonStyle(kind: .accent))
                            .disabled(!confirm.enabled)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 18)
                .padding(.bottom, 16)
                VStack(alignment: .leading, spacing: 14) { content() }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 24)
            }
        } else {
            VStack(alignment: .leading, spacing: 18) {
                Text(title).font(AppFont.subtitle).foregroundStyle(theme.textPrimary)
                VStack(alignment: .leading, spacing: 14) { content() }
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                HStack(spacing: 10) {
                    Button(action: cancel.perform) { Text(cancel.title).frame(maxWidth: .infinity) }
                        .buttonStyle(PillButtonStyle(fill: true))
                    Button(action: confirm.perform) { Text(confirm.title).frame(maxWidth: .infinity) }
                        .buttonStyle(PillButtonStyle(kind: .accent, fill: true))
                        .disabled(!confirm.enabled)
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: - Segmented control

/// The system segmented control over a list of titled choices.
struct SegmentedBar<ID: Hashable>: View {
    struct Item: Identifiable { var id: ID; var title: String }
    let items: [Item]
    @Binding var selection: ID?

    var body: some View {
        if let first = items.first {
            Picker("", selection: Binding(get: { selection ?? first.id }, set: { selection = $0 })) {
                ForEach(items) { item in
                    Text(item.title).tag(item.id)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
        }
    }
}
