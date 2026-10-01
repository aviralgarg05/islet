import Foundation

/// Where a timer is in its life.
public enum TimerStatus: String, Codable, Sendable, CaseIterable {
    case running
    /// Stopped with time left, which `remaining` holds.
    case paused
    /// Reached zero; waits to be stopped, snoozed or restarted.
    case ringing
}

public enum TimerAction: String, Codable, Sendable, CaseIterable {
    case pause, resume, add, stop, restart, snooze
}

public enum PomodoroAction: String, Codable, Sendable, CaseIterable {
    case start, stop, toggle
}

/// Everything the island, the API, the URL scheme and `isletctl` can ask of the timers.
public enum TimerCommand: Equatable, Sendable {
    case start(seconds: TimeInterval, title: String?, id: String?)
    /// `id` nil means the timer that is ringing, or else the newest one.
    case control(TimerAction, id: String?, seconds: TimeInterval?)
    case pomodoro(PomodoroAction)
}

public enum PomodoroPhase: String, Codable, Sendable, CaseIterable {
    case focus, shortBreak, longBreak

    public var title: String {
        switch self {
        case .focus: return "Focus"
        case .shortBreak: return "Short break"
        case .longBreak: return "Long break"
        }
    }
}

/// Pomodoro lengths, in minutes so `config.json` stays readable. Missing or out-of-range
/// values fall back to 25 / 5 / 15 with a long break after every 4th focus.
public struct PomodoroSchedule: Codable, Equatable, Sendable {
    public var focusMinutes: Double
    public var shortBreakMinutes: Double
    public var longBreakMinutes: Double
    /// Every n-th break is a long one.
    public var longBreakEvery: Int

    public init(focusMinutes: Double = 25, shortBreakMinutes: Double = 5, longBreakMinutes: Double = 15, longBreakEvery: Int = 4) {
        self.focusMinutes = focusMinutes
        self.shortBreakMinutes = shortBreakMinutes
        self.longBreakMinutes = longBreakMinutes
        self.longBreakEvery = longBreakEvery
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = PomodoroSchedule()
        self.init(
            focusMinutes: (try? c.decodeIfPresent(Double.self, forKey: .focusMinutes)) ?? d.focusMinutes,
            shortBreakMinutes: (try? c.decodeIfPresent(Double.self, forKey: .shortBreakMinutes)) ?? d.shortBreakMinutes,
            longBreakMinutes: (try? c.decodeIfPresent(Double.self, forKey: .longBreakMinutes)) ?? d.longBreakMinutes,
            longBreakEvery: (try? c.decodeIfPresent(Int.self, forKey: .longBreakEvery)) ?? d.longBreakEvery
        )
        self = sanitized()
    }

    /// Phases last 1 to 240 minutes; a long break comes after every 1 to 12 focus phases.
    public func sanitized() -> PomodoroSchedule {
        let d = PomodoroSchedule()
        func minutes(_ v: Double, _ fallback: Double) -> Double { v.isFinite ? min(240, max(1, v)) : fallback }
        return PomodoroSchedule(
            focusMinutes: minutes(focusMinutes, d.focusMinutes),
            shortBreakMinutes: minutes(shortBreakMinutes, d.shortBreakMinutes),
            longBreakMinutes: minutes(longBreakMinutes, d.longBreakMinutes),
            longBreakEvery: min(12, max(1, longBreakEvery))
        )
    }

    public func seconds(for phase: PomodoroPhase) -> TimeInterval {
        let s = sanitized()
        switch phase {
        case .focus: return s.focusMinutes * 60
        case .shortBreak: return s.shortBreakMinutes * 60
        case .longBreak: return s.longBreakMinutes * 60
        }
    }

    /// What follows `phase`, given how many focus phases are finished (including this one).
    public func phase(after phase: PomodoroPhase, completedFocus: Int) -> PomodoroPhase {
        guard phase == .focus else { return .focus }
        return completedFocus > 0 && completedFocus % sanitized().longBreakEvery == 0 ? .longBreak : .shortBreak
    }
}

/// One countdown. Pomodoro phases are timers too, with `phase` set.
public struct TimerItem: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var title: String?
    /// The length it was started with; `restart` uses it again.
    public var duration: TimeInterval
    public var status: TimerStatus
    /// Running: when it will end. Ringing: when it ended. Paused: nil.
    public var endsAt: Date?
    /// Paused: the time that was left.
    public var remaining: TimeInterval?
    public var createdAt: Date
    /// Set on the Pomodoro timer.
    public var phase: PomodoroPhase?

    public init(id: String, title: String? = nil, duration: TimeInterval, status: TimerStatus = .running, endsAt: Date? = nil,
                remaining: TimeInterval? = nil, createdAt: Date, phase: PomodoroPhase? = nil) {
        self.id = id; self.title = title; self.duration = duration; self.status = status; self.endsAt = endsAt
        self.remaining = remaining; self.createdAt = createdAt; self.phase = phase
    }

    public var displayTitle: String { title ?? phase?.title ?? "Timer" }

    public func timeLeft(at now: Date) -> TimeInterval {
        switch status {
        case .running: return max(0, (endsAt ?? now).timeIntervalSince(now))
        case .paused: return max(0, remaining ?? duration)
        case .ringing: return 0
        }
    }

    /// 0 when started, 1 when done.
    public func fraction(at now: Date) -> Double {
        let left = timeLeft(at: now)
        let total = max(duration, left)
        return total > 0 ? min(1, max(0, 1 - left / total)) : 1
    }
}

/// Something that happened on its own when time passed.
public enum TimerEvent: Equatable, Sendable {
    /// A timer reached zero and is ringing.
    case finished(TimerItem)
    /// The Pomodoro moved on to its next phase.
    case phaseChanged(from: PomodoroPhase, to: TimerItem)
    /// Ended more than an hour ago (the Mac was asleep or Islet wasn't running), so it was
    /// dropped instead of ringing late.
    case missed(TimerItem)
}

public enum TimerError: Error, Equatable, Sendable, CustomStringConvertible {
    case invalidDuration(TimeInterval)
    case invalidID(String)
    case notFound(String)
    case noTimers
    case tooMany

    public var description: String {
        switch self {
        case .invalidDuration(let s): return "a timer must run for more than 0 seconds and at most 24 hours, got \(s)"
        case .invalidID(let id): return "invalid timer id '\(id)': use 1-128 characters from [A-Za-z0-9._:-]; 'pomodoro' and ids starting with '\(MenuBarLiveActivities.idPrefix)' are reserved"
        case .notFound(let id): return "no timer '\(id)'"
        case .noTimers: return "no timers are running"
        case .tooMany: return "too many timers (\(TimerEngine.maxTimers)); stop one first"
        }
    }
}

/// Timers and the Pomodoro cycle as a pure value with an injected clock. The app keeps one,
/// saves it to disk, schedules a single wake-up for `nextDeadline()` and shows each timer
/// through `spec(for:)`, so nothing ticks while nothing is visible.
public struct TimerEngine: Codable, Equatable, Sendable {
    public static let source = "timer"
    public static let pomodoroID = "pomodoro"
    public static let maxDuration: TimeInterval = 24 * 3600
    public static let snoozeLength: TimeInterval = 5 * 60
    public static let maxTimers = 20
    public static let missedLimit: TimeInterval = 3600

    /// In the order they were started.
    public private(set) var timers: [TimerItem] = []
    /// Focus phases finished in the current Pomodoro run.
    public private(set) var completedFocus = 0

    public init() {}

    public var pomodoro: TimerItem? { timers.first { $0.id == Self.pomodoroID } }

    /// Ringing first, then running by end time, then paused.
    public var ordered: [TimerItem] {
        func rank(_ t: TimerItem) -> Int {
            switch t.status {
            case .ringing: return 0
            case .running: return 1
            case .paused: return 2
            }
        }
        return timers.enumerated().sorted { a, b in
            let ra = rank(a.element), rb = rank(b.element)
            if ra != rb { return ra < rb }
            if a.element.status == .running, let ea = a.element.endsAt, let eb = b.element.endsAt, ea != eb { return ea < eb }
            return a.offset < b.offset
        }.map(\.element)
    }

    public var isRinging: Bool { timers.contains { $0.status == .ringing } }

    /// The soonest moment a timer ends, for the app's single wake-up.
    public func nextDeadline() -> Date? {
        timers.filter { $0.status == .running }.compactMap(\.endsAt).min()
    }

    /// Finds a timer by id, by number ("2" for "timer-2") or by title. Without a reference:
    /// the timer that is ringing, or else the newest one.
    public func find(_ ref: String?) -> TimerItem? {
        (try? index(ref)).map { timers[$0] }
    }

    func index(_ ref: String?) throws -> Int {
        guard let ref = ref?.trimmingCharacters(in: .whitespaces), !ref.isEmpty else {
            let ringing = timers.indices.filter { timers[$0].status == .ringing }
            if let i = ringing.max(by: { (timers[$0].endsAt ?? .distantPast) < (timers[$1].endsAt ?? .distantPast) }) { return i }
            guard let last = timers.indices.last else { throw TimerError.noTimers }
            return last
        }
        if let i = timers.firstIndex(where: { $0.id == ref }) { return i }
        if Int(ref) != nil, let i = timers.firstIndex(where: { $0.id == "timer-\(ref)" }) { return i }
        let byTitle = timers.indices.filter { timers[$0].displayTitle.caseInsensitiveCompare(ref) == .orderedSame }
        guard byTitle.count == 1 else { throw TimerError.notFound(ref) }
        return byTitle[0]
    }

    // MARK: Commands

    @discardableResult
    public mutating func start(seconds: TimeInterval, title: String? = nil, id: String? = nil, now: Date) throws -> TimerItem {
        try Self.validate(seconds)
        if let id {
            // A timer shows as the activity with its id, so it mustn't take a mirrored one's.
            guard ActivityCenter.isValidID(id), id != Self.pomodoroID, !MenuBarLiveActivities.isMirrored(id: id) else {
                throw TimerError.invalidID(id)
            }
            timers.removeAll { $0.id == id }
        }
        guard timers.count < Self.maxTimers else { throw TimerError.tooMany }
        let item = TimerItem(id: id ?? nextID(), title: Self.clean(title), duration: seconds,
                             endsAt: now.addingTimeInterval(seconds), createdAt: now)
        timers.append(item)
        return item
    }

    @discardableResult
    public mutating func pause(_ ref: String? = nil, now: Date) throws -> TimerItem {
        let i = try index(ref)
        if timers[i].status == .running {
            timers[i].remaining = timers[i].timeLeft(at: now)
            timers[i].endsAt = nil
            timers[i].status = .paused
        }
        return timers[i]
    }

    @discardableResult
    public mutating func resume(_ ref: String? = nil, now: Date) throws -> TimerItem {
        let i = try index(ref)
        if timers[i].status == .paused {
            timers[i].endsAt = now.addingTimeInterval(timers[i].remaining ?? timers[i].duration)
            timers[i].remaining = nil
            timers[i].status = .running
        }
        return timers[i]
    }

    /// Adds time. A ringing timer starts again with just the added time.
    @discardableResult
    public mutating func add(_ seconds: TimeInterval, to ref: String? = nil, now: Date) throws -> TimerItem {
        try Self.validate(seconds)
        let i = try index(ref)
        switch timers[i].status {
        case .running:
            let end = (timers[i].endsAt ?? now).addingTimeInterval(seconds)
            timers[i].endsAt = min(end, now.addingTimeInterval(Self.maxDuration))
        case .paused:
            timers[i].remaining = min((timers[i].remaining ?? 0) + seconds, Self.maxDuration)
        case .ringing:
            timers[i].endsAt = now.addingTimeInterval(seconds)
            timers[i].status = .running
        }
        return timers[i]
    }

    @discardableResult
    public mutating func stop(_ ref: String? = nil) throws -> TimerItem {
        let i = try index(ref)
        let t = timers.remove(at: i)
        if t.id == Self.pomodoroID { completedFocus = 0 }
        return t
    }

    /// Runs again from the full length it was started with.
    @discardableResult
    public mutating func restart(_ ref: String? = nil, now: Date) throws -> TimerItem {
        let i = try index(ref)
        timers[i].endsAt = now.addingTimeInterval(timers[i].duration)
        timers[i].remaining = nil
        timers[i].status = .running
        return timers[i]
    }

    /// A ringing timer rings again after `seconds`; any other timer gets that much longer.
    @discardableResult
    public mutating func snooze(_ ref: String? = nil, now: Date, seconds: TimeInterval = TimerEngine.snoozeLength) throws -> TimerItem {
        try add(seconds, to: ref, now: now)
    }

    /// Stops every timer, the Pomodoro included.
    public mutating func removeAll() {
        timers.removeAll()
        completedFocus = 0
    }

    @discardableResult
    public mutating func startPomodoro(now: Date, schedule: PomodoroSchedule = PomodoroSchedule()) throws -> TimerItem {
        if let p = pomodoro { return p }
        guard timers.count < Self.maxTimers else { throw TimerError.tooMany }
        completedFocus = 0
        let length = schedule.seconds(for: .focus)
        let item = TimerItem(id: Self.pomodoroID, duration: length, endsAt: now.addingTimeInterval(length), createdAt: now, phase: .focus)
        timers.append(item)
        return item
    }

    @discardableResult
    public mutating func stopPomodoro() -> TimerItem? {
        guard pomodoro != nil else { return nil }
        return try? stop(Self.pomodoroID)
    }

    /// Applies a command. Returns the timer it started or changed, or nil when it stopped one.
    @discardableResult
    public mutating func perform(_ command: TimerCommand, now: Date, schedule: PomodoroSchedule = PomodoroSchedule()) throws -> TimerItem? {
        switch command {
        case .start(let seconds, let title, let id):
            return try start(seconds: seconds, title: title, id: id, now: now)
        case .control(let action, let id, let seconds):
            switch action {
            case .pause: return try pause(id, now: now)
            case .resume: return try resume(id, now: now)
            case .add: return try add(seconds ?? 60, to: id, now: now)
            case .stop:
                try stop(id)
                return nil
            case .restart: return try restart(id, now: now)
            case .snooze: return try snooze(id, now: now, seconds: seconds ?? Self.snoozeLength)
            }
        case .pomodoro(let action):
            switch action {
            case .start: return try startPomodoro(now: now, schedule: schedule)
            case .stop:
                stopPomodoro()
                return nil
            case .toggle:
                if stopPomodoro() != nil { return nil }
                return try startPomodoro(now: now, schedule: schedule)
            }
        }
    }

    /// Moves on every timer whose end has passed: plain timers start ringing, the Pomodoro
    /// starts its next phase. Call it when the wake-up for `nextDeadline()` fires.
    public mutating func advance(now: Date, schedule: PomodoroSchedule = PomodoroSchedule()) -> [TimerEvent] {
        var events: [TimerEvent] = []
        for i in timers.indices.reversed() {
            guard timers[i].status == .running, let end = timers[i].endsAt, end <= now else { continue }
            let t = timers[i]
            let late = now.timeIntervalSince(end)
            if late > Self.missedLimit {
                timers.remove(at: i)
                if t.id == Self.pomodoroID { completedFocus = 0 }
                events.append(.missed(t))
            } else if let phase = t.phase {
                if phase == .focus { completedFocus += 1 }
                let next = schedule.phase(after: phase, completedFocus: completedFocus)
                let length = schedule.seconds(for: next)
                // Keep the rhythm when the wake-up was on time; start afresh after a sleep.
                let start = late < 60 ? end : now
                timers[i].phase = next
                timers[i].duration = length
                timers[i].endsAt = start.addingTimeInterval(length)
                events.append(.phaseChanged(from: phase, to: timers[i]))
            } else {
                timers[i].status = .ringing
                events.append(.finished(timers[i]))
            }
        }
        return events.reversed()
    }

    // MARK: Presentation

    /// Pomodoro progress for the subtitle: "Round 2 of 4", "Round 2 of 4 done", "All 4 rounds done".
    /// `short` gives "2/4" during focus and nothing during breaks.
    public func pomodoroRound(_ t: TimerItem, schedule: PomodoroSchedule = PomodoroSchedule(), short: Bool = false) -> String? {
        guard let phase = t.phase else { return nil }
        let every = schedule.sanitized().longBreakEvery
        if short { return phase == .focus ? "\(completedFocus % every + 1)/\(every)" : nil }
        switch phase {
        case .focus: return "Round \(completedFocus % every + 1) of \(every)"
        case .shortBreak: return "Round \((max(1, completedFocus) - 1) % every + 1) of \(every) done"
        case .longBreak: return every == 1 ? "Round done" : "All \(every) rounds done"
        }
    }

    public static func look(for t: TimerItem) -> (icon: ActivityIcon, tint: String) {
        switch t.phase {
        case .focus: return (.emoji("🍅"), "red")
        case .shortBreak: return (.symbol("cup.and.saucer.fill"), "green")
        case .longBreak: return (.symbol("figure.walk"), "teal")
        case nil: return (.symbol("timer"), "orange")
        }
    }

    /// The activity that shows a timer. Running: a live countdown to `endsAt`. Paused: no
    /// countdown, "Paused" in the wing and the time left underneath. Ringing: critical, so it
    /// breaks through fullscreen, with Stop / Snooze / Restart.
    public func spec(for t: TimerItem, schedule: PomodoroSchedule = PomodoroSchedule()) -> ActivitySpec {
        let look = Self.look(for: t)
        var spec = ActivitySpec(id: t.id, source: Self.source, title: t.displayTitle, icon: look.icon,
                                tint: look.tint, priority: .normal, ttl: 0, sneak: false)
        switch t.status {
        case .running:
            spec.state = .running
            spec.subtitle = pomodoroRound(t, schedule: schedule)
            spec.endsAt = t.endsAt
        case .paused:
            spec.state = .info
            spec.tint = "gray"
            spec.subtitle = "\(Format.clock((t.remaining ?? t.duration).rounded(.up))) left"
            spec.trailing = "Paused"
        case .ringing:
            spec.state = .waiting
            spec.priority = .critical
            spec.icon = .symbol("alarm.fill")
            spec.subtitle = "Time's up"
            spec.trailing = "Done"
            spec.actions = [
                ActivityAction(title: "Stop", url: Self.url(.stop, id: t.id), dismiss: false),
                ActivityAction(title: "Snooze 5 min", url: Self.url(.snooze, id: t.id), dismiss: false),
                ActivityAction(title: "Restart", url: Self.url(.restart, id: t.id), dismiss: false),
            ]
        }
        return spec
    }

    /// `islet://timer?action=…&id=…`
    public static func url(_ action: TimerAction, id: String) -> URL? {
        var c = URLComponents()
        c.scheme = "islet"
        c.host = "timer"
        c.queryItems = [URLQueryItem(name: "action", value: action.rawValue), URLQueryItem(name: "id", value: id)]
        return c.url
    }

    // MARK: Storage

    /// Reads timers saved by `save(to:)`; nil when the file is missing or unreadable.
    public static func load(from url: URL) -> TimerEngine? {
        read(from: url).value
    }

    /// Timers saved by `save(to:)`, or whether the file is missing or doesn't parse.
    public static func read(from url: URL) -> FileRead<TimerEngine> {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .secondsSince1970
        return JSONStore.read(TimerEngine.self, from: url, decoder: d)
    }

    /// What the timers start from at launch. An unreadable `timers.json` is moved to
    /// `timers.json.corrupt` first, so starting empty never destroys it.
    public static func start(from url: URL) -> JSONStore.Start<TimerEngine> {
        JSONStore.start(url, read: read(from:))
    }

    public func save(to url: URL) throws {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .secondsSince1970
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try e.encode(self).write(to: url, options: .atomic)
    }

    // MARK: Helpers

    static func validate(_ seconds: TimeInterval) throws {
        guard seconds.isFinite, seconds > 0, seconds <= maxDuration else { throw TimerError.invalidDuration(seconds) }
    }

    static func clean(_ title: String?) -> String? {
        guard let t = title?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty else { return nil }
        return String(t.prefix(80))
    }

    /// The lowest free "timer-N", like shell job numbers.
    func nextID() -> String {
        var n = 1
        while timers.contains(where: { $0.id == "timer-\(n)" }) { n += 1 }
        return "timer-\(n)"
    }
}
