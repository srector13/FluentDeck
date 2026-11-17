import SwiftUI

/// What's next on the calendars set up on this iPad. A client-only widget: it needs no PC.
struct CalendarPanel: View {
    let ctx: PanelContext

    static let spec = PanelSpec(
        kind: "calendar",
        title: "Calendar",
        summary: "What’s next on the calendars set up on this iPad. Slide the handle up for the week ahead.",
        symbol: "calendar",
        sizes: [.small, .medium, .large],
        defaultSize: .medium,
        drawer: { AnyView(CalendarDrawer(ctx: $0)) },
        view: { AnyView(CalendarPanel(ctx: $0)) })

    @Environment(PlannerStore.self) private var planner
    @Environment(\.theme) private var theme

    var body: some View {
        switch planner.calendarAccess {
        case .allowed:
            TimelineView(.everyMinute) { timeline in
                agenda(now: timeline.date)
            }
        case .unknown:
            PlannerPrompt(symbol: "calendar", text: "See what’s next on your calendar.", button: "Allow access") {
                planner.requestCalendarAccess()
            }
        case .denied:
            PlannerPrompt(symbol: "calendar", text: "Calendar access is off for FluentDeck.", button: "Open Settings") {
                PlannerStore.openSettings()
            }
        }
    }

    @ViewBuilder
    private func agenda(now: Date) -> some View {
        let upcoming = planner.events.filter { $0.end > now }
        if upcoming.isEmpty {
            PanelEmptyState(symbol: "calendar", text: "Nothing coming up")
        } else if ctx.size == .small, let next = upcoming.first {
            VStack(alignment: .leading, spacing: 4) {
                Capsule().fill(next.color).frame(width: 28, height: 4)
                Text(next.allDay ? "All day" : (next.start <= now ? "Now" : PlannerFormat.time(next.start)))
                    .font(AppFont.subtitle)
                    .foregroundStyle(theme.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(next.title)
                    .font(AppFont.body)
                    .foregroundStyle(theme.textSecondary)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        } else {
            VStack(alignment: .leading, spacing: 6) {
                // The day in red capitals, as the iOS calendar widget heads its list.
                Text(now, format: .dateTime.weekday(.wide).day())
                    .textCase(.uppercase)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(theme.critical)
                ForEach(upcoming.prefix(ctx.size == .large ? 6 : 2)) { event in
                    PlannerEventRow(event: event, now: now)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
    }
}

/// The week ahead, day by day.
struct CalendarDrawer: View {
    let ctx: PanelContext
    @Environment(PlannerStore.self) private var planner
    @Environment(\.theme) private var theme

    private struct Day: Identifiable {
        var id: Date
        var events: [PlannerEvent]
    }

    var body: some View {
        TimelineView(.everyMinute) { timeline in
            let now = timeline.date
            let days = Self.days(planner.events.filter { $0.end > now })
            if planner.calendarAccess != .allowed {
                PanelEmptyState(symbol: "calendar", text: "Calendar access is off").frame(height: 120)
            } else if days.isEmpty {
                PanelEmptyState(symbol: "calendar", text: "Nothing in the next week").frame(height: 120)
            } else {
                let rows = days.reduce(0) { $0 + $1.events.count }
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(days) { day in
                            Text(PlannerFormat.day(day.id, now: now))
                                .font(AppFont.caption.weight(.semibold))
                                .foregroundStyle(theme.textSecondary)
                                .padding(.top, 6)
                            ForEach(day.events) { event in
                                PlannerEventRow(event: event, now: now, underDayHeading: true)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .scrollIndicators(.hidden)
                .scrollBounceBehavior(.basedOnSize)
                .frame(height: min(CGFloat(rows) * 52 + CGFloat(days.count) * 30 + 8, 430))
            }
        }
    }

    private static func days(_ events: [PlannerEvent]) -> [Day] {
        let groups = Dictionary(grouping: events) { Calendar.current.startOfDay(for: $0.start) }
        return groups.keys.sorted().map { Day(id: $0, events: groups[$0] ?? []) }
    }
}

/// One event: its calendar's colour, its title, and when (and where) it is.
struct PlannerEventRow: View {
    let event: PlannerEvent
    let now: Date
    var underDayHeading = false
    @Environment(\.theme) private var theme

    var body: some View {
        HStack(spacing: 12) {
            Capsule().fill(event.color).frame(width: 4, height: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text(event.title)
                    .font(AppFont.bodyStrong)
                    .foregroundStyle(theme.textPrimary)
                    .lineLimit(1)
                Text(detail)
                    .font(AppFont.caption)
                    .foregroundStyle(theme.textSecondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .frame(height: 44)
        .accessibilityElement(children: .combine)
    }

    private var detail: String {
        let when = PlannerFormat.when(event, now: now, underDayHeading: underDayHeading)
        if let location = event.location { return "\(when) · \(location)" }
        return when
    }
}

/// Shown until iOS has been asked for access, or when access is off.
struct PlannerPrompt: View {
    let symbol: String
    let text: String
    let button: String
    let action: () -> Void
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: symbol).font(.system(size: 22, weight: .light)).foregroundStyle(theme.textTertiary)
            Text(text)
                .font(AppFont.caption)
                .foregroundStyle(theme.textSecondary)
                .multilineTextAlignment(.center)
                .lineLimit(3)
                .minimumScaleFactor(0.8)
            Button(button, action: action)
                .buttonStyle(PillButtonStyle(kind: .standard, compact: true))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
