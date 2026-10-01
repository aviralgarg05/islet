import AppKit
import EventKit
import Foundation
import IsletCore

/// Reads upcoming events and reminders with EventKit. Access is only requested when the
/// user turns the module on, never at launch.
public final class CalendarService {
    public var onAgenda: (([AgendaItem]) -> Void)?
    public var onReminders: (([ReminderItem]) -> Void)?
    /// Also fetch reminders (requires separate Reminders access).
    public var includeReminders = false
    /// Made on first use: creating a store contacts the calendar daemon, which runs a privacy
    /// check even while the module is off. Made again when access arrives (`accessChanged`).
    private var storeInstance: EKEventStore?
    private var store: EKEventStore {
        if let s = storeInstance { return s }
        let s = EKEventStore()
        storeInstance = s
        return s
    }
    private var observer: NSObjectProtocol?

    public init() {}
    deinit { stop() }

    /// What macOS allows for calendars: full access, "Add events only", refused, restricted or
    /// not asked yet. Reading it never prompts.
    public static var eventAccess: CalendarAccess { access(EKEventStore.authorizationStatus(for: .event)) }

    public static var reminderAccess: CalendarAccess { access(EKEventStore.authorizationStatus(for: .reminder)) }

    static func access(_ status: EKAuthorizationStatus) -> CalendarAccess {
        switch status {
        case .fullAccess, .authorized: return .fullAccess
        case .writeOnly: return .writeOnly
        case .denied: return .denied
        case .restricted: return .restricted
        case .notDetermined: return .notDetermined
        @unknown default: return .denied
        }
    }

    /// Access changed while Islet was running (the user came back from System Settings). A
    /// store made before access was granted may go on seeing nothing, so the next use makes a
    /// new one; a running service starts reading straight away.
    public func accessChanged() {
        let running = observer != nil
        stop()
        storeInstance = nil
        if running { start() }
    }

    public func requestReminderAccess(completion: @escaping (Bool) -> Void) {
        store.requestFullAccessToReminders { granted, _ in
            DispatchQueue.main.async { completion(granted) }
        }
    }

    /// Event calendars, for choosing which ones to show: (identifier, title, colour hex).
    public func calendars() -> [(id: String, title: String, color: String?)] {
        guard Self.eventAccess.canRead else { return [] }
        return store.calendars(for: .event).map { ($0.calendarIdentifier, $0.title, Self.hex($0.color)) }
            .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }

    static func hex(_ color: NSColor?) -> String? {
        color?.usingColorSpace(.sRGB).map { c in
            String(format: "#%02X%02X%02X", Int(c.redComponent * 255), Int(c.greenComponent * 255), Int(c.blueComponent * 255))
        }
    }

    public func requestAccess(completion: @escaping (Bool) -> Void) {
        store.requestFullAccessToEvents { granted, _ in
            DispatchQueue.main.async { completion(granted) }
        }
    }

    public func start() {
        guard Self.eventAccess.canRead || includeReminders && Self.reminderAccess.canRead else { return }
        if observer == nil {
            observer = NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: store, queue: .main) { [weak self] _ in
                self?.refresh()
            }
        }
        refresh()
    }

    public func stop() {
        if let o = observer { NotificationCenter.default.removeObserver(o) }
        observer = nil
    }

    /// Events from an hour ago until the end of tomorrow, and incomplete reminders due by then.
    public func refresh() {
        refreshReminders()
        guard Self.eventAccess.canRead else { return }
        let now = Date()
        let end = Calendar.current.date(byAdding: .day, value: 2, to: Calendar.current.startOfDay(for: now)) ?? now.addingTimeInterval(86400)
        let predicate = store.predicateForEvents(withStart: now.addingTimeInterval(-3600), end: end, calendars: nil)
        let items = store.events(matching: predicate).map(Self.item(from:))
        onAgenda?(items)
    }

    private func refreshReminders() {
        guard includeReminders, Self.reminderAccess.canRead else { return }
        let end = Calendar.current.date(byAdding: .day, value: 2, to: Calendar.current.startOfDay(for: Date())) ?? Date()
        let predicate = store.predicateForIncompleteReminders(withDueDateStarting: nil, ending: end, calendars: nil)
        store.fetchReminders(matching: predicate) { [weak self] reminders in
            let items = (reminders ?? []).map(Self.reminder(from:))
            DispatchQueue.main.async { self?.onReminders?(items) }
        }
    }

    /// Mark a reminder done (the user ticked it in the island).
    @discardableResult
    public func complete(reminderID: String) -> Bool {
        guard Self.reminderAccess.canRead,
              let r = store.calendarItem(withIdentifier: reminderID) as? EKReminder else { return false }
        r.isCompleted = true
        do {
            try store.save(r, commit: true)
            return true
        } catch {
            return false
        }
    }

    static func reminder(from r: EKReminder) -> ReminderItem {
        let comps = r.dueDateComponents
        let due = comps.flatMap { Calendar.current.date(from: $0) }
        return ReminderItem(
            id: r.calendarItemIdentifier,
            title: r.title ?? "Untitled",
            due: due,
            isAllDay: comps != nil && comps?.hour == nil,
            listColor: hex(r.calendar?.color),
            listTitle: r.calendar?.title,
            priority: r.priority
        )
    }

    static func item(from e: EKEvent) -> AgendaItem {
        let color = hex(e.calendar?.color)
        return AgendaItem(
            id: Agenda.eventID(eventIdentifier: e.eventIdentifier, calendarItemIdentifier: e.calendarItemIdentifier, start: e.startDate),
            title: e.title ?? "Untitled",
            start: e.startDate,
            end: e.endDate,
            isAllDay: e.isAllDay,
            calendarColor: color,
            location: e.location,
            meetingURL: Agenda.meetingLink(in: [e.url?.absoluteString, e.location, e.notes]),
            calendarID: e.calendar?.calendarIdentifier,
            calendarTitle: e.calendar?.title,
            isDeclined: e.attendees?.first(where: \.isCurrentUser)?.participantStatus == .declined,
            // A cancelled meeting (Exchange keeps it in the calendar) is left out, and never reminds.
            isCancelled: e.status == .canceled
        )
    }
}
