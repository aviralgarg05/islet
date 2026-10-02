import Foundation

/// The app a meeting's call link opens.
public enum MeetingApp: String, Sendable, CaseIterable {
    case zoom, meet, teams, webex, facetime, other

    public init(url: URL) {
        let scheme = url.scheme?.lowercased() ?? ""
        let host = url.host?.lowercased() ?? ""
        func on(_ domain: String) -> Bool { host == domain || host.hasSuffix("." + domain) }
        if scheme == "zoommtg" || scheme == "zoomus" || on("zoom.us") || on("zoomgov.com") {
            self = .zoom
        } else if on("meet.google.com") {
            self = .meet
        } else if scheme == "msteams" || on("teams.microsoft.com") || on("teams.live.com") {
            self = .teams
        } else if on("webex.com") {
            self = .webex
        } else if on("facetime.apple.com") {
            self = .facetime
        } else {
            self = .other
        }
    }

    public var name: String {
        switch self {
        case .zoom: return "Zoom"
        case .meet: return "Google Meet"
        case .teams: return "Teams"
        case .webex: return "Webex"
        case .facetime: return "FaceTime"
        case .other: return "Call"
        }
    }

    /// Its Mac app, the current one first. Google Meet and other web calls run in the browser.
    public var bundleIDs: [String] {
        switch self {
        case .zoom: return ["us.zoom.xos"]
        case .teams: return ["com.microsoft.teams2", "com.microsoft.teams"]
        case .webex: return ["Cisco-Systems.Spark", "com.cisco.webexmeetingsapp"]
        case .facetime: return ["com.apple.FaceTime"]
        case .meet, .other: return []
        }
    }
}

/// How meeting reminders behave (Settings → Calendar & Reminders → Meeting reminders).
public struct MeetingReminderOptions: Equatable, Sendable {
    /// Seconds before the start that a meeting shows in the closed island.
    public var lead: TimeInterval
    /// Once it has started, it stays until you join, dismiss it, or it ends.
    public var keepUntilJoined: Bool
    /// Only meetings with a call link.
    public var onlyWithLink: Bool
    /// Without `keepUntilJoined`: how long after the start it stays.
    public var linger: TimeInterval

    public init(lead: TimeInterval, keepUntilJoined: Bool = true, onlyWithLink: Bool = true, linger: TimeInterval = 5 * 60) {
        self.lead = lead
        self.keepUntilJoined = keepUntilJoined
        self.onlyWithLink = onlyWithLink
        self.linger = linger
    }

    /// From the settings; nil while reminders (or the calendar) are off.
    public init?(_ s: IsletSettings) {
        guard s.calendarEnabled, s.meetingReminderMinutes > 0 else { return nil }
        self.init(lead: TimeInterval(s.meetingReminderMinutes) * 60, keepUntilJoined: s.meetingRemindUntilJoined,
                  onlyWithLink: s.meetingRemindersNeedLink)
    }
}

/// One meeting showing in the closed island.
public struct MeetingReminder: Equatable, Sendable, Identifiable {
    public enum Phase: String, Codable, Sendable {
        /// Counting down to the start.
        case soon
        /// Started: urgent until you join or dismiss it.
        case now
    }

    public var item: AgendaItem
    public var phase: Phase
    /// The occurrence (`MeetingReminders.key`): every repeat of a meeting has its own.
    public var key: String
    /// The activity showing it.
    public var id: String
    /// The app its call link opens; nil without a link.
    public var app: MeetingApp?
    /// When it goes on its own.
    public var until: Date

    /// The wing: "9 min" before the start, then "Now".
    public func trailing(now: Date) -> String {
        guard phase == .soon else { return "Now" }
        return "\(minutesLeft(now: now)) min"
    }

    /// The wing's value where "9 min" doesn't fit: "9m" before the start, nothing after it
    /// ("Now" fits as it is).
    public func shortTrailing(now: Date) -> String? {
        phase == .soon ? "\(minutesLeft(now: now))m" : nil
    }

    private func minutesLeft(now: Date) -> Int {
        max(1, Int((item.start.timeIntervalSince(now) / 60).rounded(.up)))
    }
}

/// Meeting reminders: which meetings show in the closed island now, which ones you joined or
/// dismissed, and when that changes next. A value type with an injected clock; the app calls
/// `live` whenever the agenda, the settings or the time (`nextDeadline`) changes, and keeps the
/// records in a file so a relaunch doesn't bring back a meeting you dealt with.
///
/// - A meeting shows from `lead` before its start, on the day it happens. All-day events and
///   invitations you declined never show, and with `onlyWithLink` neither do meetings without
///   a call link.
/// - At its start it turns urgent. With `keepUntilJoined` it stays until you join it, dismiss
///   it, or it ends; without, it goes `linger` after the start.
/// - Each occurrence of a repeating meeting is its own: dismissing today's leaves tomorrow's.
/// - It opens the island for a moment when it first shows and again at its start, once each,
///   also across a relaunch. A Mac asleep through the start catches up when it wakes.
public struct MeetingReminders: Codable, Equatable, Sendable {
    public struct Record: Codable, Equatable, Sendable {
        public enum Outcome: String, Codable, Sendable { case joined, dismissed }

        /// The end of the occurrence. The record is forgotten a day later.
        public var until: Date
        /// The phase it last opened the island in.
        public var announced: MeetingReminder.Phase?
        public var outcome: Outcome?

        public init(until: Date, announced: MeetingReminder.Phase? = nil, outcome: Outcome? = nil) {
            self.until = until
            self.announced = announced
            self.outcome = outcome
        }
    }

    /// By occurrence key.
    public private(set) var records: [String: Record] = [:]

    public init() {}

    /// The source of reminder activities. Muting it in the island mutes the reminders.
    public static let source = "calendar"
    public static let idPrefix = "meeting-"

    /// One occurrence: a repeating meeting shares its event identifier, so the start tells them apart.
    public static func key(for item: AgendaItem) -> String {
        "\(item.id)@\(Int(item.start.timeIntervalSince1970.rounded()))"
    }

    public static func activityID(for key: String) -> String {
        ActivityCenter.namespacedID(key, prefix: idPrefix)
    }

    /// A reminder's activity. Scripts never read these: they carry meeting titles.
    public static func isReminder(_ a: Activity) -> Bool {
        a.source == source && a.id.hasPrefix(idPrefix)
    }

    public static func isEligible(_ item: AgendaItem, options: MeetingReminderOptions) -> Bool {
        !item.isAllDay && !item.isDeclined && !item.isCancelled && (!options.onlyWithLink || item.meetingURL != nil)
    }

    /// When an occurrence shows, starts and goes.
    static func window(_ item: AgendaItem, options: MeetingReminderOptions) -> (from: Date, start: Date, until: Date) {
        // A meeting with no length still has a minute to be seen.
        let ends = max(item.end, item.start.addingTimeInterval(60))
        let until = options.keepUntilJoined ? ends : min(ends, item.start.addingTimeInterval(options.linger))
        return (item.start.addingTimeInterval(-options.lead), item.start, until)
    }

    /// The meetings to show at `now`, earliest first.
    public func live(_ items: [AgendaItem], now: Date, options: MeetingReminderOptions?) -> [MeetingReminder] {
        guard let options else { return [] }
        var seen = Set<String>()
        return items.compactMap { item -> MeetingReminder? in
            guard Self.isEligible(item, options: options) else { return nil }
            let key = Self.key(for: item)
            guard seen.insert(key).inserted, records[key]?.outcome == nil else { return nil }
            let w = Self.window(item, options: options)
            guard w.from <= now, now < w.until else { return nil }
            return MeetingReminder(item: item, phase: now < w.start ? .soon : .now, key: key, id: Self.activityID(for: key),
                                   app: item.meetingURL.map(MeetingApp.init(url:)), until: w.until)
        }
        .sorted { ($0.item.start, $0.key) < ($1.item.start, $1.key) }
    }

    /// The next moment `live` changes: a meeting showing, starting or going, or a countdown
    /// reaching its next minute. Nil when nothing is due, so nothing runs.
    public func nextDeadline(_ items: [AgendaItem], now: Date, options: MeetingReminderOptions?) -> Date? {
        guard let options else { return nil }
        var dates: [Date] = []
        for item in items where Self.isEligible(item, options: options) && records[Self.key(for: item)]?.outcome == nil {
            let w = Self.window(item, options: options)
            for d in [w.from, w.start, w.until] where d > now { dates.append(d) }
            if w.from <= now, now < w.start {
                // "9 min" becomes "8 min" when 8 minutes are left.
                let left = w.start.timeIntervalSince(now)
                let next = w.start.addingTimeInterval(-60 * (ceil(left / 60) - 1))
                if next > now { dates.append(next) }
            }
        }
        return dates.min()
    }

    /// Which of `live` should open the island for a moment now: those showing for the first time
    /// and those that have just started. Each is announced once per phase.
    public mutating func announce(_ live: [MeetingReminder]) -> Set<String> {
        var fresh = Set<String>()
        for r in live {
            var record = records[r.key] ?? Record(until: r.item.end)
            record.until = max(record.until, r.item.end)
            if record.announced != r.phase {
                record.announced = r.phase
                fresh.insert(r.key)
            }
            if records[r.key] != record { records[r.key] = record }
        }
        return fresh
    }

    /// You joined the meeting (its Join button, or a call starting in its app).
    public mutating func join(_ item: AgendaItem) { settle(item, .joined) }

    /// You dismissed the reminder (its ×, a swipe up, or Dismiss in its menu).
    public mutating func dismiss(_ item: AgendaItem) { settle(item, .dismissed) }

    private mutating func settle(_ item: AgendaItem, _ outcome: Record.Outcome) {
        let key = Self.key(for: item)
        var record = records[key] ?? Record(until: item.end)
        record.until = max(record.until, item.end)
        record.outcome = outcome
        records[key] = record
    }

    public func outcome(of item: AgendaItem) -> Record.Outcome? { records[Self.key(for: item)]?.outcome }

    /// How long before a meeting's start a call may begin and still count as joining it: people
    /// join a little early. A call that began before that is another meeting running on.
    public static let joinWindow: TimeInterval = 10 * 60

    /// The calls going on now (from call detection): the meetings on show that they join. A call
    /// joins a meeting when it is in the meeting's own app, or in a browser for meetings that run
    /// there (Google Meet, other web calls), and began no earlier than `joinWindow` before the
    /// start. It counts whenever Islet looks, so a call joined early, before the reminder showed
    /// or before the urgent "Now", takes the reminder away too.
    public static func joinedByCalls(_ calls: [OngoingCall], live: [MeetingReminder]) -> [MeetingReminder] {
        live.filter { r in
            guard let app = r.app else { return false }
            let earliest = r.item.start.addingTimeInterval(-joinWindow)
            return calls.contains { call in
                call.since >= earliest && (call.isBrowser ? app.bundleIDs.isEmpty : app.bundleIDs.contains(call.bundleID))
            }
        }
    }

    /// Forget occurrences that ended more than a day ago. Returns whether any went.
    @discardableResult
    public mutating func forget(before now: Date) -> Bool {
        let kept = records.filter { $0.value.until > now.addingTimeInterval(-86_400) }
        guard kept.count != records.count else { return false }
        records = kept
        return true
    }

    // MARK: Activity

    /// The icon: the call app's own when it is installed, a video glyph for other call links,
    /// a calendar glyph without one.
    public static func icon(for r: MeetingReminder, installed: (String) -> Bool) -> ActivityIcon {
        if let app = r.app, let bundle = app.bundleIDs.first(where: installed) { return .app(bundleID: bundle) }
        return .symbol(r.app == nil ? "calendar" : "video.fill")
    }

    /// The activity showing `r`: the meeting's title, the countdown then "Now" in the wing, a
    /// Join button for a call link, and the calendar's colour. It turns urgent (waiting, which
    /// glows) at the start. High priority: above playing music, but hidden for a full screen app
    /// or an app rule like other activities.
    public static func activity(for r: MeetingReminder, now: Date, icon: ActivityIcon, sneak: Bool,
                                time: (Date) -> String) -> ActivitySpec {
        let via = r.app.map { $0 == .other ? "" : " · \($0.name)" } ?? ""
        var spec = ActivitySpec(
            id: r.id, source: source, title: r.item.title,
            subtitle: r.phase == .soon ? "At \(time(r.item.start))\(via)" : "Now · until \(time(r.item.end))",
            icon: icon, trailing: r.trailing(now: now),
            state: r.phase == .now ? .waiting : .info,
            tint: r.item.calendarColor ?? "blue", priority: .high, ttl: 0,
            actions: r.item.meetingURL.map { [ActivityAction(title: "Join", url: $0)] } ?? [],
            sneak: sneak
        )
        // A narrow wing says "9m" rather than a shrunken "9 min"; "Now" fits as it is ("" clears
        // the short form an earlier update set).
        spec.compactShort = r.shortTrailing(now: now) ?? ""
        return spec
    }

    // MARK: File

    static var coder: (JSONEncoder, JSONDecoder) {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.sortedKeys]
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return (e, d)
    }

    /// Reads `meetings.json`. One that doesn't parse is moved aside and the reminders start afresh.
    public static func start(from url: URL) -> JSONStore.Start<MeetingReminders> {
        JSONStore.start(url) { JSONStore.read(MeetingReminders.self, from: $0, decoder: coder.1) }
    }

    public func save(to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Self.coder.0.encode(self).write(to: url, options: .atomic)
    }

    enum CodingKeys: String, CodingKey { case records }
}

/// A call going on now, as call detection sees it.
public struct OngoingCall: Equatable, Sendable {
    /// The call's app (a browser's own id for a web call).
    public var bundleID: String
    public var isBrowser: Bool
    /// When its microphone use began.
    public var since: Date

    public init(bundleID: String, isBrowser: Bool, since: Date) {
        self.bundleID = bundleID
        self.isBrowser = isBrowser
        self.since = since
    }
}

extension CallDetector {
    /// The calls going on now, for meeting reminders (`MeetingReminders.joinedByCalls`).
    public var ongoing: [OngoingCall] {
        active.compactMap { bundle, since in
            Self.classify(bundle).map { OngoingCall(bundleID: $0.bundleID, isBrowser: $0.app.isBrowser, since: since) }
        }
        .sorted { $0.bundleID < $1.bundleID }
    }
}
