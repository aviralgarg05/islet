import Foundation

/// A request to keep the Mac awake, or to stop.
public enum KeepAwakeChange: Equatable, Sendable {
    /// `minutes` nil = until turned off.
    case start(minutes: Double?)
    case stop
}

/// One keep-awake period.
public struct KeepAwakeSession: Codable, Equatable, Sendable {
    public var since: Date
    /// nil = until turned off.
    public var until: Date?

    public init(since: Date, until: Date? = nil) {
        self.since = since
        self.until = until
    }
}

/// What `GET /v1/awake` and `isletctl awake` report.
public struct KeepAwakeStatus: Codable, Equatable, Sendable {
    public var active: Bool
    public var since: Date?
    public var until: Date?
    /// Whole minutes left, rounded up; nil when inactive or open-ended.
    public var minutesLeft: Int?

    public init(active: Bool, since: Date? = nil, until: Date? = nil, minutesLeft: Int? = nil) {
        self.active = active
        self.since = since
        self.until = until
        self.minutesLeft = minutesLeft
    }
}

/// Keep awake: stops the display (and so the Mac) from sleeping while idle, for a while or
/// until turned off. Rules and presentation live here; the power assertion lives in IsletSystem.
public enum KeepAwake {
    public static let activityID = "keep-awake"
    public static let source = "awake"
    public static let symbol = "cup.and.saucer.fill"
    public static let tint = "yellow"
    /// Longest timed period (24 h); longer requests are refused.
    public static let maxMinutes: Double = 24 * 60
    /// Below this level on battery, keep awake turns itself off.
    public static let lowBatteryLevel = 20

    /// Menu choices: title and minutes (nil = until turned off).
    public static let presets: [(title: String, minutes: Double?)] = [
        ("15 Minutes", 15), ("1 Hour", 60), ("2 Hours", 120), ("Until Turned Off", nil),
    ]

    /// Parse `15m`, `1h`, `1h30m`, `90s`, a bare number of minutes (`45`), `on`/`forever`
    /// (until turned off) or `off`. Returns nil for anything else or out of range.
    public static func parse(_ raw: String) -> KeepAwakeChange? {
        let s = raw.trimmingCharacters(in: .whitespaces).lowercased()
        switch s {
        case "", "on", "forever", "indefinite", "indefinitely", "always", "true", "yes":
            return .start(minutes: nil)
        case "off", "stop", "false", "no", "0":
            return .stop
        default:
            break
        }
        guard let minutes = minutes(in: s), minutes > 0, minutes <= maxMinutes else { return nil }
        return .start(minutes: minutes)
    }

    /// Minutes in a duration like `1h30m`, `90s`, `2.5h` or a bare number (minutes).
    static func minutes(in s: String) -> Double? {
        if let bare = Double(s) { return bare.isFinite ? bare : nil }
        var total = 0.0
        var number = ""
        var sawUnit = false
        for ch in s {
            if ch.isNumber || ch == "." {
                number.append(ch)
                continue
            }
            let mult: Double
            switch ch {
            case "h": mult = 60
            case "m": mult = 1
            case "s": mult = 1.0 / 60
            default: return nil
            }
            guard let v = Double(number) else { return nil }
            total += v * mult
            number = ""
            sawUnit = true
        }
        guard sawUnit, number.isEmpty, total.isFinite else { return nil }
        return total
    }

    /// Turn off on battery below `lowBatteryLevel`, so keep awake never drains the Mac flat.
    public static func shouldRelease(_ battery: BatteryState?) -> Bool {
        guard let b = battery else { return false }
        return !b.isPluggedIn && !b.isCharging && b.level < lowBatteryLevel
    }

    public static func status(_ session: KeepAwakeSession?, now: Date) -> KeepAwakeStatus {
        guard let session else { return KeepAwakeStatus(active: false) }
        let left = session.until.map { max(0, Int(($0.timeIntervalSince(now) / 60).rounded(.up))) }
        return KeepAwakeStatus(active: true, since: session.since, until: session.until, minutesLeft: left)
    }

    /// The live activity shown while keep awake is on: a countdown, or "On" when open-ended.
    public static func activity(for session: KeepAwakeSession, sneak: Bool, timeStyle: (Date) -> String) -> ActivitySpec {
        ActivitySpec(
            id: activityID, source: source, title: "Keep awake",
            subtitle: session.until.map { "Display stays on until \(timeStyle($0))" } ?? "Display stays on until you turn it off",
            icon: .symbol(symbol), trailing: session.until == nil ? "On" : "", state: .running, tint: tint,
            priority: .low, ttl: 0, endsAt: session.until,
            actions: [ActivityAction(title: "Turn Off", url: URL(string: "islet://awake/off"), dismiss: false)],
            sneak: sneak
        )
    }

    /// A short notice when keep awake stops on its own.
    public static func notice(_ text: String) -> ActivitySpec {
        ActivitySpec(
            id: activityID + "-notice", source: source, title: "Keep awake is off", subtitle: text,
            icon: .symbol("cup.and.saucer"), state: .info, tint: tint, priority: .normal, ttl: 5, sneak: true
        )
    }
}
