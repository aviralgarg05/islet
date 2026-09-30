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

    public init(id: String, title: String, start: Date, end: Date, isAllDay: Bool = false,
                calendarColor: String? = nil, location: String? = nil, meetingURL: URL? = nil) {
        self.id = id; self.title = title; self.start = start; self.end = end; self.isAllDay = isAllDay
        self.calendarColor = calendarColor; self.location = location; self.meetingURL = meetingURL
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
                guard let url = match.url, let host = url.host?.lowercased() else { continue }
                let hostPath = host + url.path.lowercased()
                if meetingHosts.contains(where: { hostPath == $0 || hostPath.hasSuffix("." + $0) || hostPath.hasPrefix($0) || host.hasSuffix("." + $0) }) {
                    return url
                }
            }
        }
        return nil
    }

    /// The event worth surfacing now: an ongoing timed event, else the next one starting
    /// within `horizon`. All-day events are ignored (they are not actionable reminders).
    public static func upcoming(_ items: [AgendaItem], now: Date, horizon: TimeInterval = 12 * 3600) -> AgendaItem? {
        let timed = items.filter { !$0.isAllDay && $0.end > now }.sorted { $0.start < $1.start }
        if let ongoing = timed.first(where: { $0.isOngoing(at: now) }) { return ongoing }
        return timed.first { $0.start.timeIntervalSince(now) <= horizon }
    }

    /// Whether to raise a "starting soon" live activity for this event.
    public static func shouldAlert(_ item: AgendaItem, now: Date, lead: TimeInterval = 5 * 60) -> Bool {
        guard !item.isAllDay else { return false }
        let delta = item.start.timeIntervalSince(now)
        return delta <= lead && delta > -60
    }

    /// The live activity announcing an imminent event.
    public static func activity(for item: AgendaItem, now: Date) -> ActivitySpec {
        var actions: [ActivityAction] = []
        if let url = item.meetingURL { actions.append(ActivityAction(title: "Join", url: url)) }
        return ActivitySpec(
            id: "calendar-\(String(item.id.filter { $0.isLetter || $0.isNumber }.prefix(40)))",
            source: "calendar",
            title: item.title,
            subtitle: item.location.flatMap { $0.isEmpty ? nil : $0 } ?? Format.relative(to: item.start, now: now),
            icon: .symbol(item.meetingURL != nil ? "video.fill" : "calendar"),
            state: .info,
            tint: item.calendarColor ?? "blue",
            priority: .high,
            ttl: max(60, item.start.timeIntervalSince(now) + 120),
            endsAt: item.start > now ? item.start : nil,
            actions: actions,
            sneak: true
        )
    }
}
