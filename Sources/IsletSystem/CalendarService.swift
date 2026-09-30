import AppKit
import EventKit
import Foundation
import IsletCore

/// Reads upcoming events and reminders with EventKit. Access is only requested when the
/// user turns the module on, never at launch.
public final class CalendarService {
    public enum Access: Equatable { case notDetermined, granted, denied }

    public var onAgenda: (([AgendaItem]) -> Void)?
    private let store = EKEventStore()
    private var observer: NSObjectProtocol?

    public init() {}
    deinit { stop() }

    public static var eventAccess: Access {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .fullAccess, .authorized: return .granted
        case .notDetermined: return .notDetermined
        default: return .denied
        }
    }

    public func requestAccess(completion: @escaping (Bool) -> Void) {
        store.requestFullAccessToEvents { granted, _ in
            DispatchQueue.main.async { completion(granted) }
        }
    }

    public func start() {
        guard Self.eventAccess == .granted else { return }
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

    /// Events from now until the end of tomorrow.
    public func refresh() {
        guard Self.eventAccess == .granted else { return }
        let now = Date()
        let end = Calendar.current.date(byAdding: .day, value: 2, to: Calendar.current.startOfDay(for: now)) ?? now.addingTimeInterval(86400)
        let predicate = store.predicateForEvents(withStart: now.addingTimeInterval(-3600), end: end, calendars: nil)
        let items = store.events(matching: predicate).map(Self.item(from:))
        onAgenda?(items)
    }

    static func item(from e: EKEvent) -> AgendaItem {
        let color = e.calendar?.color.usingColorSpace(.sRGB).map { c in
            String(format: "#%02X%02X%02X", Int(c.redComponent * 255), Int(c.greenComponent * 255), Int(c.blueComponent * 255))
        }
        return AgendaItem(
            id: e.eventIdentifier ?? UUID().uuidString,
            title: e.title ?? "Untitled",
            start: e.startDate,
            end: e.endDate,
            isAllDay: e.isAllDay,
            calendarColor: color,
            location: e.location,
            meetingURL: Agenda.meetingLink(in: [e.url?.absoluteString, e.location, e.notes])
        )
    }
}
