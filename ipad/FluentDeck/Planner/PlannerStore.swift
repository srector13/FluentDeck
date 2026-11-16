import EventKit
import Observation
import SwiftUI
import UIKit

/// An event from the calendars set up on this iPad.
struct PlannerEvent: Identifiable, Equatable {
    var id: String
    var title: String
    var start: Date
    var end: Date
    var allDay: Bool
    var location: String?
    var color: Color
}

/// An open reminder from the lists set up on this iPad.
struct PlannerReminder: Identifiable, Equatable {
    var id: String
    var title: String
    var due: Date?
    /// The due date carries a time of day, not just a day.
    var dueHasTime: Bool
    var list: String
    var color: Color
}

/// The iPad's own calendar and reminders (EventKit), for the Calendar and Reminders widgets.
/// Nothing here involves the PC: it works whether or not one is connected. iOS asks the person
/// for access the first time each widget wants it.
@MainActor
@Observable
final class PlannerStore {
    enum Access { case unknown, allowed, denied }

    private(set) var calendarAccess = Access.unknown
    private(set) var remindersAccess = Access.unknown
    /// Events that haven't ended, from today through the next seven days, soonest first.
    private(set) var events: [PlannerEvent] = []
    /// Open reminders: dated ones first (soonest first), then the rest.
    private(set) var reminders: [PlannerReminder] = []

    @ObservationIgnored private let store = EKEventStore()
    @ObservationIgnored private var items: [String: EKReminder] = [:]
    @ObservationIgnored private var observer: NSObjectProtocol?
    @ObservationIgnored private var ticker: Task<Void, Never>?
    /// Canned data for screenshots and UI tests (`-FluentDeckDemoPlanner YES`); EventKit isn't touched.
    @ObservationIgnored private let demo = LaunchOptions.demoPlanner

    init() {
        if demo {
            calendarAccess = .allowed
            remindersAccess = .allowed
            events = PlannerDemo.events()
            reminders = PlannerDemo.reminders()
            return
        }
        observer = NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: store, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        ticker = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 300_000_000_000)
                self?.refresh()
            }
        }
        refresh()
    }

    private static func access(for type: EKEntityType) -> Access {
        switch EKEventStore.authorizationStatus(for: type) {
        case .fullAccess: return .allowed
        case .notDetermined: return .unknown
        default: return .denied // denied, restricted, or write-only: nothing to show
        }
    }

    func requestCalendarAccess() {
        guard !demo else { return }
        Task {
            _ = try? await store.requestFullAccessToEvents()
            refresh()
        }
    }

    func requestRemindersAccess() {
        guard !demo else { return }
        Task {
            _ = try? await store.requestFullAccessToReminders()
            refresh()
        }
    }

    static func openSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
    }

    /// Re-read what iOS will let us see. Cheap enough to call whenever the app comes forward.
    func refresh() {
        guard !demo else { return }
        calendarAccess = Self.access(for: .event)
        remindersAccess = Self.access(for: .reminder)

        if calendarAccess == .allowed {
            let now = Date()
            let start = Calendar.current.startOfDay(for: now)
            let end = Calendar.current.date(byAdding: .day, value: 8, to: start) ?? start.addingTimeInterval(8 * 86_400)
            let found = store.events(matching: store.predicateForEvents(withStart: start, end: end, calendars: nil))
            let upcoming = found.filter { $0.endDate > now }.sorted { $0.startDate < $1.startDate }
            events = upcoming.prefix(80).map(Self.event)
        } else {
            events = []
        }

        if remindersAccess == .allowed {
            let open = store.predicateForIncompleteReminders(withDueDateStarting: nil, ending: nil, calendars: nil)
            _ = store.fetchReminders(matching: open) { [weak self] found in
                let list = found ?? []
                Task { @MainActor in self?.apply(list) }
            }
        } else {
            reminders = []
            items = [:]
        }
    }

    /// Tick a reminder off. It leaves the list at once; if iOS refuses the save it comes back.
    func complete(_ reminder: PlannerReminder) {
        reminders.removeAll { $0.id == reminder.id }
        guard !demo, let item = items[reminder.id] else { return }
        item.isCompleted = true
        do {
            try store.save(item, commit: true)
        } catch {
            refresh()
        }
    }

    private func apply(_ found: [EKReminder]) {
        var byID: [String: EKReminder] = [:]
        var list: [PlannerReminder] = []
        for item in found {
            let reminder = Self.reminder(item)
            byID[reminder.id] = item
            list.append(reminder)
        }
        list.sort { a, b in
            switch (a.due, b.due) {
            case let (x?, y?): return x < y
            case (_?, nil): return true
            case (nil, _?): return false
            case (nil, nil): return a.title.localizedCaseInsensitiveCompare(b.title) == .orderedAscending
            }
        }
        items = byID
        reminders = Array(list.prefix(100))
    }

    private static func event(_ item: EKEvent) -> PlannerEvent {
        let title = item.title ?? ""
        let location = item.location ?? ""
        return PlannerEvent(
            // A repeating event shares one identifier across its occurrences.
            id: "\(item.eventIdentifier ?? title)@\(item.startDate.timeIntervalSince1970)",
            title: title.isEmpty ? "Untitled event" : title,
            start: item.startDate,
            end: item.endDate,
            allDay: item.isAllDay,
            location: location.isEmpty ? nil : location,
            color: color(of: item.calendar))
    }

    private static func reminder(_ item: EKReminder) -> PlannerReminder {
        let title = item.title ?? ""
        let parts = item.dueDateComponents
        return PlannerReminder(
            id: item.calendarItemIdentifier,
            title: title.isEmpty ? "Untitled reminder" : title,
            due: parts.flatMap { Calendar.current.date(from: $0) },
            dueHasTime: parts?.hour != nil,
            list: item.calendar?.title ?? "",
            color: color(of: item.calendar))
    }

    private static func color(of calendar: EKCalendar?) -> Color {
        guard let cg = calendar?.cgColor else { return .gray }
        return Color(cgColor: cg)
    }
}

/// How the widgets word dates.
enum PlannerFormat {
    static func time(_ date: Date) -> String {
        date.formatted(date: .omitted, time: .shortened)
    }

    /// "Today", "Tomorrow", or "Wed, Nov 18".
    static func day(_ date: Date, now: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDate(date, inSameDayAs: now) { return "Today" }
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: now), calendar.isDate(date, inSameDayAs: tomorrow) { return "Tomorrow" }
        return date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
    }

    /// When an event is, for a row that isn't under a day heading.
    static func when(_ event: PlannerEvent, now: Date, underDayHeading: Bool = false) -> String {
        let prefix = underDayHeading || Calendar.current.isDate(event.start, inSameDayAs: now) ? "" : day(event.start, now: now) + ", "
        if event.allDay { return prefix + "All day" }
        if event.start <= now { return "Now, until \(time(event.end))" }
        var text = prefix + "\(time(event.start)) – \(time(event.end))"
        let minutes = Int(event.start.timeIntervalSince(now) / 60)
        if minutes < 60 { text += " · in \(max(minutes, 1)) min" }
        return text
    }

    static func isOverdue(_ reminder: PlannerReminder, now: Date) -> Bool {
        guard let due = reminder.due else { return false }
        if reminder.dueHasTime { return due < now }
        return due < Calendar.current.startOfDay(for: now)
    }

    /// Due today (or earlier) and still open.
    static func isDue(_ reminder: PlannerReminder, now: Date) -> Bool {
        guard let due = reminder.due else { return false }
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: now)) ?? now
        return due < tomorrow
    }

    /// "Today, 5:00 PM", "Overdue · Mon, Nov 16", or the list's name when there's no date.
    static func due(_ reminder: PlannerReminder, now: Date) -> String {
        guard let due = reminder.due else { return reminder.list }
        var text = day(due, now: now)
        if reminder.dueHasTime { text += ", \(time(due))" }
        return isOverdue(reminder, now: now) ? "Overdue · \(text)" : text
    }
}

/// Stand-in events and reminders, placed relative to now so the widgets always have something next.
enum PlannerDemo {
    private static func quarterHour(after minutes: Double, from now: Date) -> Date {
        let t = now.addingTimeInterval(minutes * 60).timeIntervalSinceReferenceDate
        return Date(timeIntervalSinceReferenceDate: (t / 900).rounded(.up) * 900)
    }

    private static func tomorrow(at hour: Int, from now: Date) -> Date {
        let day = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: now)) ?? now
        return Calendar.current.date(bySettingHour: hour, minute: 0, second: 0, of: day) ?? day
    }

    static func events(now: Date = Date()) -> [PlannerEvent] {
        let blue = Color(hex: "#4A9BFF"), orange = Color(hex: "#FF9F43"), green = Color(hex: "#3DD68C"), red = Color(hex: "#FF6B6B")
        func event(_ title: String, _ start: Date, _ minutes: Double, _ color: Color, _ location: String? = nil) -> PlannerEvent {
            PlannerEvent(id: title, title: title, start: start, end: start.addingTimeInterval(minutes * 60), allDay: false, location: location, color: color)
        }
        return [
            event("Design review", quarterHour(after: 20, from: now), 45, blue, "Room 4"),
            event("Lunch with the team", quarterHour(after: 120, from: now), 60, orange),
            event("Release check-in", quarterHour(after: 270, from: now), 30, green),
            event("Dentist", tomorrow(at: 9, from: now), 60, red),
            event("Sprint planning", tomorrow(at: 14, from: now), 60, blue, "Room 2"),
        ].sorted { $0.start < $1.start }
    }

    static func reminders(now: Date = Date()) -> [PlannerReminder] {
        let work = Color(hex: "#4A9BFF"), home = Color(hex: "#FF9F43")
        let today = Calendar.current.startOfDay(for: now)
        return [
            PlannerReminder(id: "1", title: "Renew the domain", due: today.addingTimeInterval(-86_400), dueHasTime: false, list: "Work", color: work),
            PlannerReminder(id: "2", title: "Send the invoice", due: today, dueHasTime: false, list: "Work", color: work),
            PlannerReminder(id: "3", title: "Book flights", due: tomorrow(at: 10, from: now), dueHasTime: true, list: "Home", color: home),
            PlannerReminder(id: "4", title: "Call the bank", due: nil, dueHasTime: false, list: "Home", color: home),
            PlannerReminder(id: "5", title: "Water the plants", due: nil, dueHasTime: false, list: "Home", color: home),
        ]
    }
}
