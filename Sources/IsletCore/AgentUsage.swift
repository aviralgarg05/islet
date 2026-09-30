import Foundation

/// A coding agent whose plan limits Islet can show.
public enum UsageProvider: String, Codable, Sendable, CaseIterable {
    case claude, codex

    public var displayName: String { self == .claude ? "Claude" : "Codex" }
    public var symbol: String { self == .claude ? "sparkle" : "terminal.fill" }
    public var tint: String { self == .claude ? "#D97757" : "#10A37F" }
}

/// One rate-limit window, such as Claude's 5-hour or weekly limit.
public struct UsageWindow: Codable, Equatable, Sendable, Identifiable {
    /// Key from the source: `five_hour`, `seven_day` (Claude) or `primary`, `secondary` (Codex).
    public var id: String
    /// Percentage of the window used, 0–100.
    public var usedPercent: Double
    /// Window length: 300 for 5 hours, 10080 for a week.
    public var windowMinutes: Int?
    public var resetsAt: Date?

    public init(id: String, usedPercent: Double, windowMinutes: Int? = nil, resetsAt: Date? = nil) {
        self.id = id
        self.usedPercent = usedPercent
        self.windowMinutes = windowMinutes
        self.resetsAt = resetsAt
    }

    /// The window has rolled over, so `usedPercent` is out of date.
    public func hasReset(at now: Date) -> Bool { resetsAt.map { $0 <= now } ?? false }

    /// "5h", "7d": for bars.
    public var shortLabel: String {
        guard let m = windowMinutes, m > 0 else { return id == "seven_day" || id == "secondary" ? "7d" : "5h" }
        if m % 1440 == 0 { return "\(m / 1440)d" }
        if m % 60 == 0 { return "\(m / 60)h" }
        return "\(m)m"
    }

    /// "5-hour", "weekly": for sentences.
    public var longLabel: String {
        guard let m = windowMinutes, m > 0 else { return id == "seven_day" || id == "secondary" ? "weekly" : "5-hour" }
        if m == 10080 { return "weekly" }
        if m % 1440 == 0 { return "\(m / 1440)-day" }
        if m % 60 == 0 { return "\(m / 60)-hour" }
        return "\(m)-minute"
    }
}

/// The latest plan usage for one agent, read from files the agent itself writes.
public struct AgentUsage: Codable, Equatable, Sendable, Identifiable {
    public var provider: UsageProvider
    public var windows: [UsageWindow]
    /// Model of the latest session ("Opus 5.5").
    public var model: String?
    /// Share of the latest session's context window in use, 0–100.
    public var contextPercent: Double?
    /// Session cost in US dollars, as the agent reports it.
    public var costUSD: Double?
    public var sessionID: String?
    /// Folder name of the latest session.
    public var project: String?
    /// Plan name when the agent reports one ("team", "pro").
    public var planType: String?
    public var updatedAt: Date?

    public var id: String { provider.rawValue }

    public init(provider: UsageProvider, windows: [UsageWindow] = [], model: String? = nil, contextPercent: Double? = nil,
                costUSD: Double? = nil, sessionID: String? = nil, project: String? = nil, planType: String? = nil,
                updatedAt: Date? = nil) {
        self.provider = provider
        self.windows = windows
        self.model = model
        self.contextPercent = contextPercent
        self.costUSD = costUSD
        self.sessionID = sessionID
        self.project = project
        self.planType = planType
        self.updatedAt = updatedAt
    }

    public func window(_ id: String) -> UsageWindow? { windows.first { $0.id == id } }

    /// Same figures, ignoring when they were read.
    public func sameFigures(as other: AgentUsage?) -> Bool {
        guard var other else { return false }
        other.updatedAt = updatedAt
        return other == self
    }

    /// Worth a card: a recent session, a window still running, or windows read within `recent`.
    public func isRelevant(at now: Date, recent: TimeInterval = 12 * 3600) -> Bool {
        if hasRecentSession(at: now) { return true }
        guard !windows.isEmpty else { return false }
        if windows.contains(where: { $0.resetsAt.map { $0 > now } ?? false }) { return true }
        guard let updatedAt else { return false }
        return now.timeIntervalSince(updatedAt) < recent
    }

    /// The model and context line is shown only while the session is recent.
    public func hasRecentSession(at now: Date, within: TimeInterval = 30 * 60) -> Bool {
        guard model != nil || contextPercent != nil, let updatedAt else { return false }
        return now.timeIntervalSince(updatedAt) < within
    }
}

// MARK: - Parsing

enum UsageJSON {
    static func number(_ v: Any?) -> Double? {
        if let n = v as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID() { return n.doubleValue.isFinite ? n.doubleValue : nil }
        if let s = v as? String, let d = Double(s.trimmingCharacters(in: .whitespaces)), d.isFinite { return d }
        return nil
    }

    /// Epoch seconds (or milliseconds), or an ISO 8601 string.
    static func date(_ v: Any?) -> Date? {
        if let n = number(v), n > 0 { return Date(timeIntervalSince1970: n > 100_000_000_000 ? n / 1000 : n) }
        if let s = v as? String { return iso(s) }
        return nil
    }

    static func iso(_ s: String) -> Date? {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f.date(from: s) { return d }
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: s)
    }

    static func rounded(_ v: Double?, places: Double = 10) -> Double? {
        v.map { ($0 * places).rounded() / places }
    }
}

/// The JSON Claude Code sends on stdin to a status-line command
/// ([docs](https://code.claude.com/docs/en/statusline)). Every field may be missing:
/// `rate_limits` only appears for Pro and Max plans after the session's first reply.
public enum ClaudeStatusLine {
    public static func parse(_ data: Data, now: Date = Date()) -> AgentUsage? {
        guard let o = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return nil }
        var u = AgentUsage(provider: .claude, updatedAt: now)
        if let limits = o["rate_limits"] as? [String: Any] {
            for (key, minutes) in [("five_hour", 300), ("seven_day", 10080)] {
                guard let w = limits[key] as? [String: Any], let used = UsageJSON.number(w["used_percentage"]) else { continue }
                u.windows.append(UsageWindow(id: key, usedPercent: UsageJSON.rounded(used)!, windowMinutes: minutes,
                                             resetsAt: UsageJSON.date(w["resets_at"])))
            }
        }
        if let model = o["model"] as? [String: Any] {
            u.model = (model["display_name"] as? String) ?? (model["id"] as? String)
        } else if let model = o["model"] as? String {
            u.model = model
        }
        u.contextPercent = UsageJSON.rounded(UsageJSON.number((o["context_window"] as? [String: Any])?["used_percentage"]))
        u.costUSD = UsageJSON.rounded(UsageJSON.number((o["cost"] as? [String: Any])?["total_cost_usd"]), places: 100)
        u.sessionID = o["session_id"] as? String
        let dir = ((o["workspace"] as? [String: Any])?["current_dir"] as? String) ?? (o["cwd"] as? String)
        if let dir, !dir.isEmpty { u.project = URL(fileURLWithPath: dir).lastPathComponent }
        return u
    }

    /// Keep what the new reading lacks: account windows always (a new session reports none
    /// until its first reply), and session details when it is the same session.
    public static func merged(_ new: AgentUsage, previous: AgentUsage?) -> AgentUsage {
        guard let previous else { return new }
        var m = new
        for w in previous.windows where m.window(w.id) == nil { m.windows.append(w) }
        m.windows.sort { ($0.windowMinutes ?? 0, $0.id) < ($1.windowMinutes ?? 0, $1.id) }
        if new.sessionID == nil || new.sessionID == previous.sessionID {
            m.sessionID = m.sessionID ?? previous.sessionID
            m.model = m.model ?? previous.model
            m.contextPercent = m.contextPercent ?? previous.contextPercent
            m.costUSD = m.costUSD ?? previous.costUSD
            m.project = m.project ?? previous.project
        }
        return m
    }
}

/// Codex CLI session logs (`~/.codex/sessions/YYYY/MM/DD/rollout-*.jsonl`). Each model reply
/// appends `{"type":"event_msg","payload":{"type":"token_count","rate_limits":{…}}}`.
public enum CodexRollout {
    static let marker = Data("\"token_count\"".utf8)

    /// Usage from one rollout line, or nil unless it is a `token_count` event with limits.
    public static func usage(fromLine line: Data) -> AgentUsage? {
        guard let o = (try? JSONSerialization.jsonObject(with: line)) as? [String: Any],
              o["type"] as? String == "event_msg",
              let payload = o["payload"] as? [String: Any], payload["type"] as? String == "token_count",
              let limits = payload["rate_limits"] as? [String: Any] else { return nil }
        let stamp = (o["timestamp"] as? String).flatMap(UsageJSON.iso)
        var windows: [UsageWindow] = []
        for key in ["primary", "secondary"] {
            guard let w = limits[key] as? [String: Any], let used = UsageJSON.number(w["used_percent"]) else { continue }
            var resets = UsageJSON.date(w["resets_at"])
            if resets == nil, let seconds = UsageJSON.number(w["resets_in_seconds"]), let stamp {
                resets = stamp.addingTimeInterval(seconds)
            }
            windows.append(UsageWindow(id: key, usedPercent: UsageJSON.rounded(used)!,
                                       windowMinutes: UsageJSON.number(w["window_minutes"]).map { Int($0) }, resetsAt: resets))
        }
        guard !windows.isEmpty else { return nil }
        return AgentUsage(provider: .codex, windows: windows, planType: limits["plan_type"] as? String, updatedAt: stamp)
    }

    /// The newest usage in the tail of a rollout file, scanning backwards.
    /// - Parameter startsMidLine: the tail was cut from a longer file, so its first line is partial.
    public static func latestUsage(inTail data: Data, startsMidLine: Bool) -> AgentUsage? {
        var end = data.endIndex
        while end > data.startIndex, let hit = data.range(of: marker, options: .backwards, in: data.startIndex..<end) {
            let lineStart = data[data.startIndex..<hit.lowerBound].lastIndex(of: 0x0A).map { $0 + 1 } ?? data.startIndex
            let lineEnd = data[hit.upperBound...].firstIndex(of: 0x0A) ?? data.endIndex
            if !(startsMidLine && lineStart == data.startIndex), let u = usage(fromLine: data.subdata(in: lineStart..<lineEnd)) {
                return u
            }
            end = lineStart
        }
        return nil
    }
}

// MARK: - Alerts

/// A window that has just crossed 90% or 100%.
public struct UsageAlert: Equatable, Sendable {
    public var provider: UsageProvider
    public var window: UsageWindow
    public var threshold: Int

    public init(provider: UsageProvider, window: UsageWindow, threshold: Int) {
        self.provider = provider
        self.window = window
        self.threshold = threshold
    }

    public var title: String {
        let name = "\(provider.displayName) \(window.longLabel) limit"
        return threshold >= 100 ? "\(name) reached" : "\(name) at \(Int(window.usedPercent.rounded(.down)))%"
    }

    /// A normal live activity: it sneaks in once, then leaves on its own.
    public func activity(now: Date, calendar: Calendar = .current, locale: Locale = .current) -> ActivitySpec {
        let reached = threshold >= 100
        return ActivitySpec(
            id: "usage-\(provider.rawValue)-\(window.id)", source: "agent-usage", title: title,
            subtitle: window.resetsAt.map { "Resets \(UsageFormat.clockTime($0, now: now, calendar: calendar, locale: locale))" },
            icon: .symbol(provider.symbol), state: .warning, tint: reached ? "red" : "orange",
            priority: reached ? .high : .normal, ttl: reached ? 120 : 60, sneak: true
        )
    }
}

/// One-shot alerts when a window first crosses 90% and 100%. Re-arms when the window resets.
/// The first reading of a window only sets the baseline, so relaunching Islet doesn't repeat
/// an alert already shown.
public struct UsageAlertTracker: Sendable {
    public static let thresholds = [90, 100]

    struct Mark: Equatable, Sendable {
        var resetsAt: Date?
        var level: Int
    }

    private var marks: [String: Mark] = [:]

    public init() {}

    public mutating func ingest(_ usage: AgentUsage, now: Date) -> [UsageAlert] {
        var alerts: [UsageAlert] = []
        for w in usage.windows where !w.hasReset(at: now) {
            let key = "\(usage.provider.rawValue).\(w.id)"
            let level = Self.thresholds.last { w.usedPercent >= Double($0) } ?? 0
            guard var mark = marks[key] else {
                marks[key] = Mark(resetsAt: w.resetsAt, level: level)
                continue
            }
            if Self.isNewWindow(w, after: mark, now: now) { mark.level = 0 }
            mark.resetsAt = w.resetsAt ?? mark.resetsAt
            if level > mark.level {
                alerts.append(UsageAlert(provider: usage.provider, window: w, threshold: level))
            }
            mark.level = max(mark.level, level)
            marks[key] = mark
        }
        return alerts
    }

    public mutating func reset() { marks.removeAll() }

    /// A later reset time means a new window (they are hours apart, so small jitter is ignored).
    /// Without reset times, a big drop in usage means the same.
    static func isNewWindow(_ w: UsageWindow, after mark: Mark, now: Date) -> Bool {
        if let old = mark.resetsAt {
            if old <= now { return true }
            if let new = w.resetsAt { return new.timeIntervalSince(old) > 15 * 60 }
            return false
        }
        return w.resetsAt == nil && mark.level > 0 && w.usedPercent < 50
    }
}

// MARK: - Formatting

public enum UsageFormat {
    /// Time left until a reset: "12 min", "1 h 12 min", "3 d 4 h". Rounded up to the minute.
    public static func remaining(until date: Date, now: Date) -> String {
        let mins = max(1, Int((date.timeIntervalSince(now) / 60).rounded(.up)))
        if mins < 60 { return "\(mins) min" }
        if mins < 24 * 60 {
            let h = mins / 60, m = mins % 60
            return m == 0 ? "\(h) h" : "\(h) h \(m) min"
        }
        let d = mins / (24 * 60), h = (mins % (24 * 60)) / 60
        return h == 0 ? "\(d) d" : "\(d) d \(h) h"
    }

    /// Clock time of a reset: "16:40" today, "Thu 16:40" on another day (in the user's locale).
    public static func clockTime(_ date: Date, now: Date, calendar: Calendar = .current, locale: Locale = .current) -> String {
        let f = DateFormatter()
        f.calendar = calendar
        f.timeZone = calendar.timeZone
        f.locale = locale
        f.setLocalizedDateFormatFromTemplate(calendar.isDate(date, inSameDayAs: now) ? "jmm" : "EEE jmm")
        return f.string(from: date)
    }

    /// "42%" with no decimals.
    public static func percent(_ v: Double) -> String { "\(Int(min(999, max(0, v)).rounded()))%" }
}
