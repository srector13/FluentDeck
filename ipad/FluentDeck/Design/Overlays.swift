import SwiftUI
import Observation

// Menus and sheets are the system's own. This file describes them as data (so a panel can offer
// a menu without drawing one) and owns the two sheets the app presents: a dialog, and the drawer
// that slides up from a compact widget.

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
    /// The drawer on screen, if any. The root view presents it as a bottom sheet.
    var drawer: Drawer?

    func present<V: View>(size: SheetSize = .fitted, @ViewBuilder _ content: () -> V) {
        dialog = Dialog(size: size, content: AnyView(content()))
    }

    func dismissDialog() {
        dialog = nil
    }

    /// Slide a sheet up over the board with the rest of a widget's controls.
    func openDrawer<V: View>(title: String, @ViewBuilder _ content: () -> V) {
        drawer = Drawer(title: title, content: AnyView(content()))
    }

    func closeDrawer() {
        drawer = nil
    }
}

extension View {
    /// Present the app's dialog and drawer as system sheets. `scope` re-applies the app's
    /// environment, which a sheet's content needs as much as the screen beneath it.
    func overlaySheets<Scoped: View>(_ overlays: OverlayCenter, scope: @escaping (AnyView) -> Scoped) -> some View {
        self
            .sheet(item: Binding(get: { overlays.dialog }, set: { overlays.dialog = $0 })) { dialog in
                scope(AnyView(DialogHost(dialog: dialog)))
            }
            .sheet(item: Binding(get: { overlays.drawer }, set: { overlays.drawer = $0 })) { drawer in
                scope(AnyView(DrawerHost(drawer: drawer)))
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

/// The sheet that rises from a compact widget: the widget's name, a close button, and its full
/// controls. The system provides the grabber and the drag to dismiss.
private struct DrawerHost: View {
    let drawer: OverlayCenter.Drawer
    @Environment(OverlayCenter.self) private var overlays
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
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
            drawer.content
        }
        .padding(.horizontal, 24)
        .padding(.top, 22)
        .padding(.bottom, 18)
        .fittedSheet()
        .presentationDragIndicator(.visible)
        .presentationBackground(.regularMaterial)
        .presentationCornerRadius(34)
    }
}

/// The layout of a dialog's sheet: a title, the content, and a row of equal-width buttons.
struct DialogSheet<Content: View, Footer: View>: View {
    var title: String
    /// Stretch the content to fill a page sheet, pinning the buttons to the bottom.
    var fills = false
    @ViewBuilder var content: () -> Content
    @ViewBuilder var footer: () -> Footer
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(title).font(AppFont.subtitle).foregroundStyle(theme.textPrimary)
            VStack(alignment: .leading, spacing: 14) { content() }
                .frame(maxWidth: .infinity, maxHeight: fills ? .infinity : nil, alignment: .topLeading)
            HStack(spacing: 10) { footer() }
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Footer button for a dialog (fills its share of the row).
struct DialogButton: View {
    var title: String
    var accent = false
    var enabled = true
    let action: () -> Void

    var body: some View {
        Button(action: action) { Text(title).frame(maxWidth: .infinity) }
            .buttonStyle(PillButtonStyle(kind: accent ? .accent : .standard, fill: true))
            .disabled(!enabled)
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
