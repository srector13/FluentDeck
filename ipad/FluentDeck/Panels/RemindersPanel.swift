import SwiftUI

/// Open reminders from the lists set up on this iPad, with a tap to tick one off.
/// A client-only widget: it needs no PC.
struct RemindersPanel: View {
    let ctx: PanelContext

    static let spec = PanelSpec(
        kind: "reminders",
        title: "Reminders",
        summary: "Open reminders from this iPad. Tap the circle to tick one off; slide the handle up for the full list.",
        symbol: "checklist",
        sizes: [.small, .medium, .large],
        defaultSize: .medium,
        drawer: { AnyView(RemindersDrawer(ctx: $0)) },
        view: { AnyView(RemindersPanel(ctx: $0)) })

    @Environment(PlannerStore.self) private var planner
    @Environment(\.theme) private var theme

    var body: some View {
        switch planner.remindersAccess {
        case .allowed:
            TimelineView(.everyMinute) { timeline in
                list(now: timeline.date)
            }
        case .unknown:
            PlannerPrompt(symbol: "checklist", text: "See your reminders and tick them off.", button: "Allow access") {
                planner.requestRemindersAccess()
            }
        case .denied:
            PlannerPrompt(symbol: "checklist", text: "Reminders access is off for FluentDeck.", button: "Open Settings") {
                PlannerStore.openSettings()
            }
        }
    }

    @ViewBuilder
    private func list(now: Date) -> some View {
        let open = planner.reminders
        if open.isEmpty {
            PanelEmptyState(symbol: "checkmark.circle", text: "All done")
        } else if ctx.size == .small {
            let due = open.filter { PlannerFormat.isDue($0, now: now) }.count
            VStack(alignment: .leading, spacing: 2) {
                Text("\(due > 0 ? due : open.count)")
                    .font(AppFont.titleLarge)
                    .monospacedDigit()
                    .foregroundStyle(theme.textPrimary)
                Text(due > 0 ? "due today" : "open")
                    .font(AppFont.caption)
                    .foregroundStyle(theme.textSecondary)
                Text(open[0].title)
                    .font(AppFont.caption)
                    .foregroundStyle(theme.textSecondary)
                    .lineLimit(1)
                    .padding(.top, 4)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        } else {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(open.prefix(ctx.size == .large ? 6 : 2)) { reminder in
                    PlannerReminderRow(reminder: reminder, now: now)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
    }
}

/// Every open reminder.
struct RemindersDrawer: View {
    let ctx: PanelContext
    @Environment(PlannerStore.self) private var planner

    var body: some View {
        TimelineView(.everyMinute) { timeline in
            let open = planner.reminders
            if planner.remindersAccess != .allowed {
                PanelEmptyState(symbol: "checklist", text: "Reminders access is off").frame(height: 120)
            } else if open.isEmpty {
                PanelEmptyState(symbol: "checkmark.circle", text: "All done").frame(height: 120)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(open) { reminder in
                            PlannerReminderRow(reminder: reminder, now: timeline.date)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .scrollIndicators(.hidden)
                .scrollBounceBehavior(.basedOnSize)
                .frame(height: min(CGFloat(open.count) * 52, 430))
            }
        }
    }
}

/// One reminder: a circle in its list's colour to tick it off, its title, and when it's due.
struct PlannerReminderRow: View {
    let reminder: PlannerReminder
    let now: Date
    @Environment(PlannerStore.self) private var planner
    @Environment(\.theme) private var theme

    var body: some View {
        let overdue = PlannerFormat.isOverdue(reminder, now: now)
        HStack(spacing: 4) {
            Button {
                withAnimation(.snappy) { planner.complete(reminder) }
            } label: {
                Image(systemName: "circle")
                    .font(.system(size: 21))
                    .foregroundStyle(reminder.color)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.leading, -11) // the circle, not its touch target, lines up with the widget's edge
            .accessibilityLabel("Complete \(reminder.title)")
            VStack(alignment: .leading, spacing: 2) {
                Text(reminder.title)
                    .font(AppFont.bodyStrong)
                    .foregroundStyle(theme.textPrimary)
                    .lineLimit(1)
                Text(PlannerFormat.due(reminder, now: now))
                    .font(AppFont.caption)
                    .foregroundStyle(overdue ? theme.critical : theme.textSecondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .frame(height: 44)
    }
}
