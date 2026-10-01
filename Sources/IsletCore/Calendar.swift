import Foundation

/// A calendar event reduced to what the island shows.
public struct AgendaItem: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var title: String
    public var start: Date
    public var end: Date
    public var isAllDay: Bool
    public var calendarColor: String?
    public var location: String?
    /// Video-call link found in the URL, location or notes (Zoom, Meet, Teams, Webex…).
    public var meetingURL: URL?
    /// Identifier of the calendar it belongs to (for hiding calendars).
    public var calendarID: String?
    public var calendarTitle: String?
    /// You declined the invitation.
    public var isDeclined: Bool

    public init(id: String, title: String, start: Date, end: Date, isAllDay: Bool = false,
                calendarColor: String? = nil, location: String? = nil, meetingURL: URL? = nil,
                calendarID: String? = nil, calendarTitle: String? = nil, isDeclined: Bool = false) {
        self.id = id; self.title = title; self.start = start; self.end = end; self.isAllDay = isAllDay
        self.calendarColor = calendarColor; self.location = location; self.meetingURL = meetingURL
        self.calendarID = calendarID; self.calendarTitle = calendarTitle; self.isDeclined = isDeclined
    }

    enum CodingKeys: String, CodingKey {
        case id, title, start, end, isAllDay, calendarColor, location, meetingURL, calendarID, calendarTitle, isDeclined
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        title = try c.decode(String.self, forKey: .title)
        start = try c.decode(Date.self, forKey: .start)
        end = try c.decode(Date.self, forKey: .end)
        isAllDay = try c.decodeIfPresent(Bool.self, forKey: .isAllDay) ?? false
        calendarColor = try c.decodeIfPresent(String.self, forKey: .calendarColor)
        location = try c.decodeIfPresent(String.self, forKey: .location)
        meetingURL = try c.decodeIfPresent(URL.self, forKey: .meetingURL)
        calendarID = try c.decodeIfPresent(String.self, forKey: .calendarID)
        calendarTitle = try c.decodeIfPresent(String.self, forKey: .calendarTitle)
        isDeclined = try c.decodeIfPresent(Bool.self, forKey: .isDeclined) ?? false
    }

    public func isOngoing(at now: Date) -> Bool { start <= now && now < end }
}

public enum Agenda {
    /// Hosts recognised as joinable video calls.
    static let meetingHosts = [
        "zoom.us", "zoomgov.com", "meet.google.com", "teams.microsoft.com", "teams.live.com",
        "webex.com", "whereby.com", "meet.jit.si", "gotomeeting.com", "chime.aws", "around.co",
        "facetime.apple.com", "discord.gg", "slack.com/huddle", "app.slack.com/huddle",
    ]

    /// First video-call link in any of the given texts.
    public static func meetingLink(in texts: [String?]) -> URL? {
        let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
        for text in texts.compactMap({ $0 }) where !text.isEmpty {
            let range = NSRange(text.startIndex..., in: text)
            for match in detector?.matches(in: text, range: range) ?? [] {
                guard let url = match.url, isMeetingLink(url) else { continue }
                return url
            }
        }
        return nil
    }

    /// A joinable call link: https (or a call app's own scheme) on one of `meetingHosts` or a
    /// subdomain of it, never a host that merely starts with one ("zoom.us.example.com").
    static func isMeetingLink(_ url: URL) -> Bool {
        let scheme = url.scheme?.lowercased() ?? ""
        if ["zoommtg", "zoomus", "msteams"].contains(scheme) { return true }
        guard scheme == "https", let host = url.host?.lowercased() else { return false }
        let path = url.path.lowercased()
        return meetingHosts.contains { entry in
            let parts = entry.split(separator: "/", maxSplits: 1)
            let entryHost = String(parts[0])
            guard host == entryHost || host.hasSuffix("." + entryHost) else { return false }
            return parts.count == 1 || path.hasPrefix("/" + parts[1])
        }
    }

    /// The event worth surfacing now: an ongoing timed event, else the next one starting
    /// within `horizon`. All-day events are ignored (they are not actionable reminders).
    public static func upcoming(_ items: [AgendaItem], now: Date, horizon: TimeInterval = 12 * 3600) -> AgendaItem? {
        let timed = items.filter { !$0.isAllDay && $0.end > now }.sorted { $0.start < $1.start }
        if let ongoing = timed.first(where: { $0.isOngoing(at: now) }) { return ongoing }
        return timed.first { $0.start.timeIntervalSince(now) <= horizon }
    }
}

extension Agenda {
    /// What's left of today: timed events that haven't ended, in order, and today's all-day events.
    public static func restOfToday(_ items: [AgendaItem], now: Date, calendar: Calendar = .current) -> (timed: [AgendaItem], allDay: [AgendaItem]) {
        let today = items.filter { calendar.isDate($0.start, inSameDayAs: now) || ($0.start < now && $0.end > now) }
        let timed = today.filter { !$0.isAllDay && $0.end > now }.sorted { $0.start < $1.start }
        let allDay = today.filter(\.isAllDay).sorted { $0.title < $1.title }
        return (timed, allDay)
    }

    /// Drop events from calendars the user hid.
    public static func visible(_ items: [AgendaItem], hiding hidden: Set<String>) -> [AgendaItem] {
        hidden.isEmpty ? items : items.filter { !hidden.contains($0.calendarID ?? "") }
    }

    /// The next moment what the agenda shows changes on its own: a timed event starting or
    /// ending. The app redraws then, rather than checking every minute.
    public static func nextChange(_ items: [AgendaItem], now: Date) -> Date? {
        items.filter { !$0.isAllDay }.flatMap { [$0.start, $0.end] }.filter { $0 > now }.min()
    }
}

/// A reminder reduced to what the island shows.
public struct ReminderItem: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var title: String
    public var due: Date?
    /// True when the due date has no time of day ("today", not "today at 3 pm").
    public var isAllDay: Bool
    public var listColor: String?
    public var listTitle: String?
    /// EventKit priority: 1 (high) … 9 (low), 0 = none.
    public var priority: Int

    public init(id: String, title: String, due: Date?, isAllDay: Bool = false, listColor: String? = nil,
                listTitle: String? = nil, priority: Int = 0) {
        self.id = id; self.title = title; self.due = due; self.isAllDay = isAllDay
        self.listColor = listColor; self.listTitle = listTitle; self.priority = priority
    }

    public func isOverdue(at now: Date, calendar: Calendar = .current) -> Bool {
        guard let due else { return false }
        return isAllDay ? calendar.startOfDay(for: due) < calendar.startOfDay(for: now) : due < now
    }
}

public enum Reminders {
    /// Overdue first, then by due time; timeless items due today after timed ones.
    public static func dueSoon(_ items: [ReminderItem], now: Date, calendar: Calendar = .current) -> [ReminderItem] {
        let endOfToday = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) ?? now
        return items.filter { r in
            guard let due = r.due else { return false }
            return due < endOfToday
        }.sorted { a, b in
            let ao = a.isOverdue(at: now, calendar: calendar), bo = b.isOverdue(at: now, calendar: calendar)
            if ao != bo { return ao }
            if a.isAllDay != b.isAllDay { return !a.isAllDay }
            return (a.due ?? .distantFuture, a.title) < (b.due ?? .distantFuture, b.title)
        }
    }

    /// When the next timed reminder is due, so its alert shows on time without checking every minute.
    public static func nextDue(_ items: [ReminderItem], now: Date) -> Date? {
        items.compactMap { $0.isAllDay ? nil : $0.due }.filter { $0 > now }.min()
    }

    /// Timed reminders alert at their due minute (never all-day ones, which have no moment).
    public static func shouldAlert(_ item: ReminderItem, now: Date) -> Bool {
        guard let due = item.due, !item.isAllDay else { return false }
        let delta = now.timeIntervalSince(due)
        return delta >= 0 && delta < 90
    }

    public static func activity(for item: ReminderItem) -> ActivitySpec {
        ActivitySpec(
            id: "reminder-\(String(item.id.filter { $0.isLetter || $0.isNumber }.prefix(40)))",
            source: "reminders",
            title: item.title,
            subtitle: item.listTitle.map { "Reminder · \($0)" } ?? "Reminder",
            icon: .symbol(item.priority == 1 ? "exclamationmark.circle.fill" : "checklist"),
            state: .info,
            tint: item.listColor ?? "orange",
            priority: item.priority == 1 ? .high : .normal,
            ttl: 20,
            sneak: true
        )
    }
}
