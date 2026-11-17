import SwiftUI

/// Which calendars a Calendar widget shows, or which lists a Reminders widget shows. Each widget
/// keeps its own choice, so one can show work and another home.
struct PlannerSourcesDialog: View {
    enum Kind {
        case calendars, lists
        var key: String { self == .calendars ? "calendars" : "lists" }
        var title: String { self == .calendars ? "Calendars" : "Reminders Lists" }
    }

    let ctx: PanelContext
    let kind: Kind
    @Environment(PlannerStore.self) private var planner
    @Environment(\.theme) private var theme
    /// nil while everything is shown.
    @State private var chosen: Set<String>?
    @State private var loaded = false

    /// The ids a widget is limited to, or nil for all.
    static func chosen(_ ctx: PanelContext, _ kind: Kind) -> Set<String>? {
        guard let raw = ctx.config[kind.key] else { return nil }
        return Set(raw.split(separator: ",").map(String.init))
    }

    private var sources: [PlannerSource] { kind == .calendars ? planner.calendars : planner.reminderLists }

    /// Sources grouped by account, in the order they come.
    private var accounts: [(name: String, sources: [PlannerSource])] {
        var order: [String] = []
        var groups: [String: [PlannerSource]] = [:]
        for s in sources {
            if groups[s.account] == nil { order.append(s.account) }
            groups[s.account, default: []].append(s)
        }
        return order.map { ($0, groups[$0] ?? []) }
    }

    var body: some View {
        DialogSheet(title: "Show \(kind.title)", fills: true,
                    cancel: DialogAction("Cancel") { ctx.overlays.dismissDialog() },
                    confirm: DialogAction("Save", enabled: chosen.map { !$0.isEmpty } ?? true) { save() }) {
            Toggle("Show all \(kind == .calendars ? "calendars" : "lists")", isOn: Binding(
                get: { chosen == nil },
                set: { all in chosen = all ? nil : Set(sources.map(\.id)) }))
                .font(AppFont.body)
                .foregroundStyle(theme.textPrimary)
            if sources.isEmpty {
                PanelEmptyState(symbol: kind == .calendars ? "calendar" : "checklist",
                                text: "No \(kind == .calendars ? "calendars" : "lists") on this iPad yet")
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        ForEach(accounts, id: \.name) { account in
                            VStack(alignment: .leading, spacing: 2) {
                                if !account.name.isEmpty {
                                    Text(account.name.uppercased())
                                        .font(AppFont.caption.weight(.semibold))
                                        .foregroundStyle(theme.textSecondary)
                                        .padding(.leading, 12)
                                        .padding(.bottom, 4)
                                }
                                ForEach(account.sources) { row($0) }
                            }
                        }
                    }
                }
                .opacity(chosen == nil ? 0.45 : 1)
                .disabled(chosen == nil)
            }
        }
        .onAppear {
            guard !loaded else { return }
            chosen = Self.chosen(ctx, kind)
            loaded = true
        }
    }

    private func row(_ source: PlannerSource) -> some View {
        let on = chosen?.contains(source.id) ?? true
        return Button {
            guard var set = chosen else { return }
            if on { set.remove(source.id) } else { set.insert(source.id) }
            chosen = set
        } label: {
            HStack(spacing: 12) {
                Circle().fill(source.color).frame(width: 12, height: 12)
                Text(source.title).font(AppFont.body).foregroundStyle(theme.textPrimary)
                Spacer(minLength: 0)
                Image(systemName: on ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 22))
                    .foregroundStyle(on ? source.color : theme.textTertiary)
            }
            .padding(.horizontal, 12)
            .frame(minHeight: 48)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(source.title)
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    private func save() {
        ctx.updateConfig(kind.key, chosen.map { $0.sorted().joined(separator: ",") })
        ctx.overlays.dismissDialog()
    }
}
