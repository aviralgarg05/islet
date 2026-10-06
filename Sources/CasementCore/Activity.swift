import Foundation

/// How important an activity is when several compete for the island.
public enum ActivityPriority: Int, Codable, Comparable, Sendable, CaseIterable {
    case low = 0
    case normal = 1
    case high = 2
    case critical = 3

    public static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }

    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let n = try? c.decode(Int.self) {
            self = ActivityPriority(rawValue: max(0, min(3, n))) ?? .normal
        } else {
            let s = try c.decode(String.self).lowercased()
            switch s {
            case "low": self = .low
            case "normal", "default", "medium": self = .normal
            case "high": self = .high
            case "critical", "urgent": self = .critical
            default:
                throw DecodingError.dataCorruptedError(in: c, debugDescription: "Unknown priority '\(s)'")
            }
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(String(describing: self))
    }
}

/// Semantic state drives the default tint and icon.
public enum ActivityState: String, Codable, Sendable, CaseIterable {
    case info, running, success, warning, failure, waiting
}

/// A reference to an icon. Encoded as a single prefixed string so it is easy to
/// write from a shell script: `sf:hammer.fill`, `emoji:🚀`, `app:com.apple.Music`,
/// `url:https://…/icon.png`, `file:/path/icon.png`. A bare string is treated as an
/// SF Symbol name unless it is a single emoji.
public enum ActivityIcon: Equatable, Sendable, Codable, CustomStringConvertible {
    case symbol(String)
    case emoji(String)
    case app(bundleID: String)
    case url(URL)
    case file(String)

    public init?(string raw: String) {
        let s = raw.trimmingCharacters(in: .whitespaces)
        guard !s.isEmpty else { return nil }
        if let idx = s.firstIndex(of: ":") {
            let scheme = s[..<idx].lowercased()
            let rest = String(s[s.index(after: idx)...])
            switch scheme {
            case "sf", "symbol": self = .symbol(rest); return
            case "emoji": self = .emoji(rest); return
            case "app", "bundle": self = .app(bundleID: rest); return
            case "file": self = .file(rest.hasPrefix("//") ? String(rest.dropFirst(2)) : rest); return
            case "http", "https":
                guard let u = URL(string: s) else { return nil }
                self = .url(u); return
            case "url":
                guard let u = URL(string: rest) else { return nil }
                self = .url(u); return
            default: break
            }
        }
        if s.count == 1, s.unicodeScalars.contains(where: { $0.properties.isEmojiPresentation || $0.properties.isEmoji && $0.value > 0x2000 }) {
            self = .emoji(s)
        } else if s.hasPrefix("/") {
            self = .file(s)
        } else {
            self = .symbol(s)
        }
    }

    public var description: String {
        switch self {
        case .symbol(let n): return "sf:\(n)"
        case .emoji(let e): return "emoji:\(e)"
        case .app(let b): return "app:\(b)"
        case .url(let u): return "url:\(u.absoluteString)"
        case .file(let p): return "file:\(p)"
        }
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        let s = try c.decode(String.self)
        guard let v = ActivityIcon(string: s) else {
            throw DecodingError.dataCorruptedError(in: c, debugDescription: "Invalid icon '\(s)'")
        }
        self = v
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(description)
    }
}

/// A button shown on an expanded activity.
public struct ActivityAction: Codable, Equatable, Sendable {
    public var title: String
    /// URL opened with the default handler (https, shortcuts://, raycast://, file://…).
    public var url: URL?
    /// Dismiss the activity after the action runs (default true).
    public var dismiss: Bool?

    public init(title: String, url: URL? = nil, dismiss: Bool? = nil) {
        self.title = title
        self.url = url
        self.dismiss = dismiss
    }
}

/// The payload clients send to create or update an activity. Every field except
/// `title` is optional; on update, omitted fields keep their previous value.
public struct ActivitySpec: Codable, Equatable, Sendable {
    public var id: String?
    public var source: String?
    public var title: String?
    public var subtitle: String?
    public var icon: ActivityIcon?
    /// Short text for the right-hand compact wing, e.g. "42%" or "3/5".
    public var trailing: String?
    /// 0...1 for determinate progress, any negative number for indeterminate.
    public var progress: Double?
    public var state: ActivityState?
    /// Hex (`#34C759`) or a named system color (`green`).
    public var tint: String?
    public var priority: ActivityPriority?
    /// Seconds until auto-dismiss. `0` or absent means it stays until removed.
    public var ttl: Double?
    /// Show a live countdown to this moment.
    public var endsAt: Date?
    /// Show a live count-up from this moment (calls, stopwatches, recordings).
    public var startedAt: Date?
    /// Opened when the island is clicked while showing this activity.
    public var url: URL?
    /// After this moment the content is shown dimmed as out of date.
    public var staleAt: Date?
    /// 0–100; orders activities of the same priority (ActivityKit's relevance score).
    public var relevance: Double?
    /// Segmented progress: total number of steps, and the current one (1-based).
    public var steps: Int?
    public var step: Int?
    public var actions: [ActivityAction]?
    /// Briefly expand the island when this spec is applied.
    public var sneak: Bool?

    // Template fields (ActivityTemplate.swift): optional, validated by `validateTemplateFields()`.
    /// Layout name: eta, stages, flight, route, score, timer, workout, gauge, live-audio, media, agent, progress.
    public var template: String?
    /// At most 5 characters for the minimal bubble ("3–1", "12m").
    public var compactShort: String?
    /// Glyph that rides the ETA track (`sf:car.fill`).
    public var trackerIcon: ActivityIcon?
    /// pickup, enroute, arrived, delivered (eta); predeparture, boarding, airborne, landed (flight); or free text.
    public var phase: String?
    public var stageLabels: [String]?
    public var stageSymbols: [ActivityIcon]?
    public var teams: [ActivityTeam]?
    /// Game period or clock text ("Q3", "67'", "Bot 7").
    public var period: String?
    public var flight: ActivityFlight?
    public var route: ActivityRoute?
    public var metrics: [ActivityMetric]?

    public init(
        id: String? = nil, source: String? = nil, title: String? = nil, subtitle: String? = nil,
        icon: ActivityIcon? = nil, trailing: String? = nil, progress: Double? = nil,
        state: ActivityState? = nil, tint: String? = nil, priority: ActivityPriority? = nil,
        ttl: Double? = nil, endsAt: Date? = nil, startedAt: Date? = nil, url: URL? = nil, staleAt: Date? = nil,
        relevance: Double? = nil, steps: Int? = nil, step: Int? = nil, actions: [ActivityAction]? = nil, sneak: Bool? = nil
    ) {
        self.id = id; self.source = source; self.title = title; self.subtitle = subtitle
        self.icon = icon; self.trailing = trailing; self.progress = progress; self.state = state
        self.tint = tint; self.priority = priority; self.ttl = ttl; self.endsAt = endsAt
        self.startedAt = startedAt; self.url = url; self.staleAt = staleAt; self.relevance = relevance
        self.steps = steps; self.step = step; self.actions = actions; self.sneak = sneak
    }
}

/// A live activity as held by the `ActivityCenter`.
public struct Activity: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var source: String
    public var title: String
    public var subtitle: String?
    public var icon: ActivityIcon?
    public var trailing: String?
    public var progress: Double?
    public var state: ActivityState
    public var tint: String?
    public var priority: ActivityPriority
    public var endsAt: Date?
    public var startedAt: Date?
    public var url: URL?
    public var staleAt: Date?
    public var relevance: Double?
    public var steps: Int?
    public var step: Int?
    public var expiresAt: Date?
    public var actions: [ActivityAction]
    public var createdAt: Date
    public var updatedAt: Date

    // Template fields (ActivityTemplate.swift); see the matching fields on `ActivitySpec`.
    public var template: ActivityTemplate? = nil
    public var compactShort: String? = nil
    public var trackerIcon: ActivityIcon? = nil
    public var phase: String? = nil
    public var stageLabels: [String]? = nil
    public var stageSymbols: [ActivityIcon]? = nil
    public var teams: [ActivityTeam]? = nil
    public var period: String? = nil
    public var flight: ActivityFlight? = nil
    public var route: ActivityRoute? = nil
    public var metrics: [ActivityMetric]? = nil
    /// Seconds the ETA track covers, fixed from the first `endsAt` (see `stretchTrack`).
    public var trackSpan: Double? = nil

    public var isIndeterminate: Bool { (progress ?? 0) < 0 }

    public func isStale(at now: Date) -> Bool { staleAt.map { $0 <= now } ?? false }

    /// Progress implied by steps when no explicit progress was sent.
    public var stepProgress: Double? {
        guard let steps, steps > 0, let step else { return nil }
        return min(1, max(0, Double(step) / Double(steps)))
    }

    /// Normalised progress in 0...1, or nil for none / indeterminate.
    public var clampedProgress: Double? {
        guard let p = progress else { return stepProgress }
        guard p >= 0 else { return nil }
        return min(1, p)
    }

    /// Default icon used when the client did not send one.
    public var effectiveIcon: ActivityIcon {
        if let icon { return icon }
        switch state {
        case .info: return .symbol("info.circle.fill")
        case .running: return .symbol("gearshape.2.fill")
        case .success: return .symbol("checkmark.circle.fill")
        case .warning: return .symbol("exclamationmark.triangle.fill")
        case .failure: return .symbol("xmark.octagon.fill")
        case .waiting: return .symbol("hourglass")
        }
    }

    /// Default tint derived from state when the client did not send one.
    public var effectiveTint: String {
        if let tint { return tint }
        switch state {
        case .info: return "blue"
        case .running: return "orange"
        case .success: return "green"
        case .warning: return "yellow"
        case .failure: return "red"
        case .waiting: return "purple"
        }
    }

    /// Text for the right-hand compact wing.
    public func trailingText(now: Date) -> String? {
        if let trailing { return trailing }
        if let endsAt { return Format.countdown(until: endsAt, now: now) }
        if let startedAt { return Format.clock(now.timeIntervalSince(startedAt)) }
        if let steps, let step, steps > 0 { return "\(min(step, steps))/\(steps)" }
        if let p = clampedProgress { return "\(Int((p * 100).rounded()))%" }
        return nil
    }
}

public enum ActivityError: Error, Equatable, CustomStringConvertible {
    case missingTitle
    case invalidProgress(Double)
    case invalidTint(String)
    case notFound(String)
    case invalidID(String)
    /// A write to a Live Activity mirrored from the menu bar. The same whether or not it exists.
    case mirrored
    /// A source over `ActivityLimits.source`. Refused rather than shortened, because Mute and
    /// `DELETE ?source=` match on the whole thing.
    case longSource(Int)

    public var description: String {
        switch self {
        case .missingTitle: return "'title' is required when creating an activity"
        case .invalidProgress(let p): return "'progress' must be between 0 and 1 (or negative for indeterminate), got \(p)"
        case .invalidTint(let t): return "'tint' must be a hex color like #34C759 or a named color, got '\(t)'"
        case .notFound(let id): return "No activity with id '\(id)'"
        case .invalidID(let id): return "Invalid id '\(id)': use 1-128 characters from [A-Za-z0-9._:-]"
        case .longSource(let n):
            return "'source' must be at most \(ActivityLimits.source) characters, got \(n): it is the name Mute and ?source= match on, so it is never shortened"
        case .mirrored:
            return "ids starting with '\(MenuBarLiveActivities.idPrefix)' or '\(MirroredNotification.idPrefix)' and sources starting with '\(MenuBarLiveActivities.source)' are kept for Live Activities mirrored from the menu bar and for notification banners, which scripts can't create, change or remove"
        }
    }
}
