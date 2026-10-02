import Foundation

/// Per-kind layouts for live activities, after the iPhone apps that use Live Activities
/// (research report 07, §5). The template decides what the wings, the bubble, the sneak peek
/// and the expanded row show; the data comes from the activity's fields.
public enum ActivityTemplate: String, Codable, Sendable, CaseIterable {
    /// Ride or delivery arriving: vehicle glyph, minutes, a 10-segment track.
    case eta
    /// Order or parcel stepping through named stages.
    case stages
    /// Departure and arrival board.
    case flight
    /// Transit trip or turn-by-turn step.
    case route
    /// Two teams and their scores.
    case score
    /// Countdown or count-up.
    case timer
    /// Live session metrics.
    case workout
    /// A level filling or draining.
    case gauge
    /// Calls, recordings and voice assistants.
    case liveAudio = "live-audio"
    /// Now Playing from a mirrored or plugin source.
    case media
    /// AI agent, build or CI run.
    case agent
    /// Anything else: the generic look.
    case progress

    /// Accepts `live-audio`, `live_audio` and `liveAudio`, in any case.
    public init?(name: String) {
        let key = name.trimmingCharacters(in: .whitespaces).lowercased().replacingOccurrences(of: "_", with: "-")
        if let t = ActivityTemplate(rawValue: key) { self = t } else if key == "liveaudio" { self = .liveAudio } else { return nil }
    }

    /// Whether an activity carries the data this template needs. A template suggested by the
    /// catalogue for the activity's source is used only when it fits.
    public func fits(_ a: Activity) -> Bool {
        switch self {
        case .eta: return a.endsAt != nil || a.trackerIcon != nil || a.phase != nil
        case .stages: return a.stageLabels != nil || a.steps != nil
        case .flight: return a.flight != nil
        case .route: return a.route != nil
        case .score: return a.teams != nil
        case .timer: return a.endsAt != nil || a.startedAt != nil
        case .workout: return a.metrics != nil || a.startedAt != nil
        case .gauge: return a.clampedProgress != nil
        case .liveAudio: return a.startedAt != nil
        // Local players already have the Now Playing card; media needs an explicit template.
        case .media: return false
        case .agent, .progress: return true
        }
    }

    /// The template implied by the fields an activity carries.
    public static func infer(from a: Activity) -> ActivityTemplate {
        if a.teams != nil { return .score }
        if a.flight != nil { return .flight }
        if a.route != nil { return .route }
        if a.stageLabels != nil { return .stages }
        if a.trackerIcon != nil || a.phase.map(ActivityPhase.eta.contains) == true { return .eta }
        if a.metrics != nil { return .workout }
        if a.endsAt != nil || a.startedAt != nil, a.progress == nil, a.steps == nil { return .timer }
        return .progress
    }
}

/// Phase names the templates react to. Any other text is shown as it is.
public enum ActivityPhase {
    public static let eta: Set<String> = ["pickup", "enroute", "arrived", "delivered"]
    public static let flight: Set<String> = ["predeparture", "boarding", "airborne", "landed"]
}

/// A side in a `score` activity.
public struct ActivityTeam: Codable, Equatable, Sendable {
    /// Up to 4 characters, shown in the badge ("LAL").
    public var abbr: String?
    public var name: String?
    /// Text so it can hold "245/3" or "40"; numbers are accepted too.
    public var score: String?
    public var tint: String?

    public init(abbr: String? = nil, name: String? = nil, score: String? = nil, tint: String? = nil) {
        self.abbr = abbr; self.name = name; self.score = score; self.tint = tint
    }

    enum CodingKeys: String, CodingKey { case abbr, name, score, tint }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        abbr = try c.decodeIfPresent(String.self, forKey: .abbr)
        name = try c.decodeIfPresent(String.self, forKey: .name)
        score = try LenientText.decode(c, .score)
        tint = try c.decodeIfPresent(String.self, forKey: .tint)
    }

    /// Badge text: the abbreviation, else the first three letters of the name.
    public var badge: String { abbr ?? name.map { String($0.prefix(3)).uppercased() } ?? "" }

    /// Sent fields replace the old ones; an empty string clears one.
    func merged(with new: ActivityTeam) -> ActivityTeam {
        ActivityTeam(abbr: pick(new.abbr, abbr), name: pick(new.name, name), score: pick(new.score, score), tint: pick(new.tint, tint))
    }
}

/// Departure board data for a `flight` activity.
public struct ActivityFlight: Codable, Equatable, Sendable {
    public var number: String?
    /// Airport codes ("SFO").
    public var from: String?
    public var to: String?
    public var departs: Date?
    public var arrives: Date?
    public var gate: String?
    public var terminal: String?
    public var seat: String?
    /// Free text: "On time", "Delayed 25 min", "Cancelled", "Boarding".
    public var status: String?
    /// Baggage belt after landing.
    public var carousel: String?

    public init(number: String? = nil, from: String? = nil, to: String? = nil, departs: Date? = nil, arrives: Date? = nil,
                gate: String? = nil, terminal: String? = nil, seat: String? = nil, status: String? = nil, carousel: String? = nil) {
        self.number = number; self.from = from; self.to = to; self.departs = departs; self.arrives = arrives
        self.gate = gate; self.terminal = terminal; self.seat = seat; self.status = status; self.carousel = carousel
    }

    public enum StatusKind: Equatable, Sendable { case normal, delayed, cancelled }

    /// Colour class for the status chip: cancelled or diverted is red, delayed amber, else green.
    public var statusKind: StatusKind {
        let s = status?.lowercased() ?? ""
        if s.contains("cancel") || s.contains("divert") { return .cancelled }
        if s.contains("delay") || s.contains("late") { return .delayed }
        return .normal
    }

    /// Share of the flight flown, from departure to arrival.
    public func progress(now: Date) -> Double? {
        guard let departs, let arrives, arrives > departs else { return nil }
        return min(1, max(0, now.timeIntervalSince(departs) / arrives.timeIntervalSince(departs)))
    }

    /// Sent fields replace the old ones; an empty string clears one.
    func merged(with new: ActivityFlight) -> ActivityFlight {
        ActivityFlight(number: pick(new.number, number), from: pick(new.from, from), to: pick(new.to, to), departs: new.departs ?? departs,
                       arrives: new.arrives ?? arrives, gate: pick(new.gate, gate), terminal: pick(new.terminal, terminal),
                       seat: pick(new.seat, seat), status: pick(new.status, status), carousel: pick(new.carousel, carousel))
    }
}

/// A transit leg or a navigation step for a `route` activity.
public struct ActivityRoute: Codable, Equatable, Sendable {
    /// walk, bus, tram, train, subway, ferry, car or bike.
    public var mode: String?
    /// Line name for the badge ("N", "L", "42").
    public var line: String?
    public var lineTint: String?
    public var stopsLeft: Int?
    /// "Turn left onto Market St", "Get off at Church".
    public var instruction: String?
    /// Distance to the next turn ("200 m").
    public var distance: String?

    public init(mode: String? = nil, line: String? = nil, lineTint: String? = nil, stopsLeft: Int? = nil,
                instruction: String? = nil, distance: String? = nil) {
        self.mode = mode; self.line = line; self.lineTint = lineTint; self.stopsLeft = stopsLeft
        self.instruction = instruction; self.distance = distance
    }

    /// SF Symbol for the leg: a turn arrow for turn-by-turn steps, else the mode.
    public var symbol: String {
        let text = instruction?.lowercased() ?? ""
        if text.contains("u-turn") || text.contains("u turn") { return "arrow.uturn.left" }
        if text.contains("left") { return "arrow.turn.up.left" }
        if text.contains("right") { return "arrow.turn.up.right" }
        switch mode?.lowercased() ?? "" {
        case "walk", "walking": return "figure.walk"
        case "bus", "coach": return "bus.fill"
        case "train", "rail": return "train.side.front.car"
        case "tram", "subway", "metro", "underground", "light rail": return "tram.fill"
        case "ferry", "boat": return "ferry.fill"
        case "bike", "bicycle", "cycle", "cycling": return "bicycle"
        case "car", "drive", "driving", "taxi": return "car.fill"
        default: return text.isEmpty ? "tram.fill" : "arrow.up"
        }
    }

    /// Sent fields replace the old ones; an empty string clears one.
    func merged(with new: ActivityRoute) -> ActivityRoute {
        ActivityRoute(mode: pick(new.mode, mode), line: pick(new.line, line), lineTint: pick(new.lineTint, lineTint),
                      stopsLeft: new.stopsLeft ?? stopsLeft, instruction: pick(new.instruction, instruction),
                      distance: pick(new.distance, distance))
    }
}

/// A merged text field: the new value when sent (nil when it is empty), else the old one.
private func pick(_ new: String?, _ old: String?) -> String? {
    guard let new else { return old }
    return new.isEmpty ? nil : new
}

/// One live value in a `workout` or `gauge` activity: `{"label": "pace", "value": "5:31", "unit": "/km"}`.
public struct ActivityMetric: Codable, Equatable, Sendable {
    public var label: String?
    /// Text so it can hold "5:31"; numbers are accepted too.
    public var value: String
    public var unit: String?

    public init(label: String? = nil, value: String, unit: String? = nil) {
        self.label = label; self.value = value; self.unit = unit
    }

    enum CodingKeys: String, CodingKey { case label, value, unit }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        label = try c.decodeIfPresent(String.self, forKey: .label)
        guard let v = try LenientText.decode(c, .value) else {
            throw DecodingError.keyNotFound(CodingKeys.value, .init(codingPath: c.codingPath, debugDescription: "metric needs a 'value'"))
        }
        value = v
        unit = try c.decodeIfPresent(String.self, forKey: .unit)
    }

    /// "5.2 km", or the value alone.
    public var text: String { unit.map { "\(value) \($0)" } ?? value }
}

/// Reads a field that may be sent as text or as a number.
enum LenientText {
    static func decode<K: CodingKey>(_ c: KeyedDecodingContainer<K>, _ key: K) throws -> String? {
        if let s = try? c.decodeIfPresent(String.self, forKey: key) { return s }
        if let i = try? c.decodeIfPresent(Int.self, forKey: key) { return String(i) }
        if let d = try c.decodeIfPresent(Double.self, forKey: key) { return d.rounded() == d && abs(d) < 1e15 ? String(Int(d)) : String(d) }
        return nil
    }
}

/// A template field that failed validation.
public struct ActivityFieldError: Error, Equatable, CustomStringConvertible {
    public var field: String
    public var reason: String

    public init(_ field: String, _ reason: String) {
        self.field = field
        self.reason = reason
    }

    public var description: String { "'\(field)' \(reason)" }
}

/// Size limits for the template fields. The island is small; longer values would be cut off.
public enum TemplateLimits {
    public static let compactShort = 5
    public static let phase = 24
    public static let period = 12
    public static let stages = 8
    public static let stageLabel = 24
    public static let teamAbbr = 4
    public static let teamName = 32
    public static let teamScore = 7
    public static let metrics = 3
    public static let metricLabel = 12
    public static let metricValue = 10
    public static let metricUnit = 8
    public static let flightNumber = 10
    public static let airport = 4
    public static let flightShort = 6
    public static let flightStatus = 24
    public static let routeMode = 12
    public static let routeLine = 6
    public static let routeInstruction = 80
    public static let routeDistance = 10
    public static let stopsLeft = 999
}

extension ActivitySpec {
    /// Checks the template fields before anything is applied. Empty strings and arrays are
    /// allowed: they clear the field on update.
    public func validateTemplateFields() throws {
        typealias L = TemplateLimits
        func text(_ value: String?, _ field: String, _ max: Int) throws {
            if let value, value.count > max { throw ActivityFieldError(field, "must be at most \(max) characters, got \(value.count)") }
        }
        func color(_ value: String?, _ field: String) throws {
            if let value, !value.isEmpty, RGBA.parse(value) == nil {
                throw ActivityFieldError(field, "must be a hex color like #34C759 or a named color, got '\(value)'")
            }
        }
        if let t = template, !t.isEmpty, ActivityTemplate(name: t) == nil {
            let names = ActivityTemplate.allCases.map(\.rawValue).joined(separator: ", ")
            throw ActivityFieldError("template", "must be one of \(names), got '\(t)'")
        }
        try text(compactShort, "compactShort", L.compactShort)
        try text(phase, "phase", L.phase)
        try text(period, "period", L.period)
        if let labels = stageLabels {
            if labels.count > L.stages { throw ActivityFieldError("stageLabels", "must have at most \(L.stages) entries, got \(labels.count)") }
            for label in labels {
                if label.isEmpty { throw ActivityFieldError("stageLabels", "must not contain empty labels") }
                try text(label, "stageLabels", L.stageLabel)
            }
        }
        if let symbols = stageSymbols, symbols.count > L.stages {
            throw ActivityFieldError("stageSymbols", "must have at most \(L.stages) entries, got \(symbols.count)")
        }
        if let teams, !teams.isEmpty {
            guard teams.count == 2 else { throw ActivityFieldError("teams", "must have exactly 2 entries, got \(teams.count)") }
            for t in teams {
                try text(t.abbr, "teams.abbr", L.teamAbbr)
                try text(t.name, "teams.name", L.teamName)
                try text(t.score, "teams.score", L.teamScore)
                try color(t.tint, "teams.tint")
            }
        }
        if let f = flight {
            try text(f.number, "flight.number", L.flightNumber)
            try text(f.from, "flight.from", L.airport)
            try text(f.to, "flight.to", L.airport)
            try text(f.gate, "flight.gate", L.flightShort)
            try text(f.terminal, "flight.terminal", L.flightShort)
            try text(f.seat, "flight.seat", L.flightShort)
            try text(f.carousel, "flight.carousel", L.flightShort)
            try text(f.status, "flight.status", L.flightStatus)
            if let d = f.departs, let a = f.arrives, a < d { throw ActivityFieldError("flight.arrives", "must not be before 'flight.departs'") }
        }
        if let r = route {
            try text(r.mode, "route.mode", L.routeMode)
            try text(r.line, "route.line", L.routeLine)
            try color(r.lineTint, "route.lineTint")
            try text(r.instruction, "route.instruction", L.routeInstruction)
            try text(r.distance, "route.distance", L.routeDistance)
            if let n = r.stopsLeft, !(0...L.stopsLeft).contains(n) {
                throw ActivityFieldError("route.stopsLeft", "must be between 0 and \(L.stopsLeft), got \(n)")
            }
        }
        if let metrics {
            if metrics.count > L.metrics { throw ActivityFieldError("metrics", "must have at most \(L.metrics) entries, got \(metrics.count)") }
            for m in metrics {
                try text(m.label, "metrics.label", L.metricLabel)
                try text(m.value, "metrics.value", L.metricValue)
                try text(m.unit, "metrics.unit", L.metricUnit)
            }
        }
    }
}

extension Activity {
    /// Copy the template fields a spec sends; omitted fields keep their value. Empty strings
    /// and arrays clear a field. `flight`, `route` and `teams` merge field by field.
    public mutating func mergeTemplateFields(_ spec: ActivitySpec) {
        func str(_ new: String?, _ old: String?) -> String? {
            guard let new else { return old }
            return new.isEmpty ? nil : new
        }
        func list<T>(_ new: [T]?, _ old: [T]?) -> [T]? {
            guard let new else { return old }
            return new.isEmpty ? nil : new
        }
        if let t = spec.template { template = t.isEmpty ? nil : ActivityTemplate(name: t) }
        compactShort = str(spec.compactShort, compactShort)
        if let v = spec.trackerIcon { trackerIcon = v }
        phase = str(spec.phase.map(Self.normalizedPhase), phase)
        stageLabels = list(spec.stageLabels, stageLabels)
        stageSymbols = list(spec.stageSymbols, stageSymbols)
        if let new = spec.teams {
            if new.isEmpty {
                teams = nil
            } else if let old = teams, old.count == new.count {
                teams = zip(old, new).map { $0.merged(with: $1) }
            } else {
                teams = new.map { ActivityTeam().merged(with: $0) }
            }
        }
        period = str(spec.period, period)
        if let new = spec.flight { flight = (flight ?? ActivityFlight()).merged(with: new) }
        if let new = spec.route { route = (route ?? ActivityRoute()).merged(with: new) }
        metrics = list(spec.metrics, metrics)
    }

    /// Known phases are stored lowercased ("Arrived" → "arrived"); other text is kept as sent.
    static func normalizedPhase(_ p: String) -> String {
        let key = p.lowercased().replacingOccurrences(of: " ", with: "").replacingOccurrences(of: "-", with: "")
        return ActivityPhase.eta.contains(key) || ActivityPhase.flight.contains(key) ? key : p
    }

    /// Fix the ETA track's span from the first ETA (Lyft's rule), so the tracker moves at a
    /// steady pace. A later ETA that grows stretches the span instead, so the tracker never
    /// moves backwards; one that arrives after the track was complete starts a new track.
    public mutating func stretchTrack(to newEnd: Date?, now: Date) {
        guard let newEnd else { return }
        let remaining = newEnd.timeIntervalSince(now)
        guard remaining > 0 else { return }
        guard let span = trackSpan, span > 0, let oldEnd = endsAt else {
            trackSpan = remaining
            return
        }
        let done = min(1, max(0, 1 - oldEnd.timeIntervalSince(now) / span))
        trackSpan = done >= 1 ? remaining : max(span, remaining / (1 - done))
    }

    /// Whether an update is a moment worth a sneak peek for the template: the ride arrives, an
    /// order moves to its next stage, a score changes, a gate or flight status changes, or a
    /// transit trip is two stops away or at its stop. Ordinary ticks stay quiet.
    public func isTemplateMoment(after old: Activity) -> Bool {
        switch resolvedTemplate {
        case .eta:
            return phase != old.phase && (phase == "arrived" || phase == "delivered")
        case .stages:
            return (currentStage ?? 0) > (old.currentStage ?? 0)
        case .score:
            return teams?.map(\.score) != old.teams?.map(\.score) && old.teams != nil
        case .flight:
            guard let f = flight, let o = old.flight else { return false }
            return (f.gate != o.gate && o.gate != nil) || f.statusKind != o.statusKind
                || (phase != old.phase && phase == "boarding")
        case .route:
            guard let n = route?.stopsLeft, n != old.route?.stopsLeft else { return false }
            return n == 2 || n == 0
        default:
            return false
        }
    }

    /// Where the ETA tracker sits, 0...1: explicit progress, else time along the fixed span.
    public func trackProgress(now: Date) -> Double? {
        if let p = clampedProgress { return p }
        guard let endsAt, let span = trackSpan, span > 0 else { return nil }
        return min(1, max(0, 1 - endsAt.timeIntervalSince(now) / span))
    }

    /// The template to draw with: the one sent, else the catalogue's for the source when the
    /// activity has the data for it, else one inferred from the fields present.
    public var resolvedTemplate: ActivityTemplate {
        if let template { return template }
        if let t = LiveActivityCatalog.entry(forSource: source)?.template, t.fits(self) { return t }
        return ActivityTemplate.infer(from: self)
    }

    /// Number of stages: the labels, else `steps`.
    public var stageCount: Int? {
        if let n = stageLabels?.count, n > 0 { return n }
        return steps
    }

    /// Current stage, 1-based: `step`, else derived from progress, else the first.
    public var currentStage: Int? {
        guard let count = stageCount, count > 0 else { return nil }
        if let step { return min(max(step, 1), count) }
        if let p = clampedProgress { return min(max(Int((p * Double(count)).rounded(.up)), 1), count) }
        return 1
    }

    public var currentStageLabel: String? {
        guard let labels = stageLabels, let i = currentStage, i <= labels.count else { return nil }
        return labels[i - 1]
    }

    public var currentStageSymbol: ActivityIcon? {
        guard let symbols = stageSymbols, let i = currentStage, i <= symbols.count else { return nil }
        return symbols[i - 1]
    }

    /// The flight phase sent, else one derived from the departure and arrival times.
    public func flightPhase(now: Date) -> String? {
        if let phase, ActivityPhase.flight.contains(phase) { return phase }
        guard let f = flight else { return nil }
        if let arrives = f.arrives, now >= arrives { return "landed" }
        if let departs = f.departs, now >= departs { return "airborne" }
        return f.departs == nil ? nil : "predeparture"
    }

    /// Countdown share left for a timer ring, 1 → 0; nil without an end time. The ring spans
    /// from `startedAt` for a timer that sends one, else from when the current countdown was
    /// set (`trackSpan`), so a timer restarted with a new `endsAt`, or a workout's rest
    /// countdown, starts full rather than measured from when the activity was created.
    public func timerFractionLeft(now: Date) -> Double? {
        guard let endsAt else { return nil }
        let total: Double
        if resolvedTemplate != .workout, let startedAt, startedAt < endsAt {
            total = endsAt.timeIntervalSince(startedAt)
        } else if let trackSpan, trackSpan > 0 {
            total = trackSpan
        } else {
            total = endsAt.timeIntervalSince(createdAt)
        }
        guard total > 0 else { return 0 }
        return min(1, max(0, endsAt.timeIntervalSince(now) / total))
    }

    /// The right-hand wing text for the resolved template, or nil when the template draws a
    /// graphic there instead (a waveform, a badge).
    public func templateTrailing(now: Date) -> String? {
        if let trailing { return trailing }
        switch resolvedTemplate {
        case .eta:
            if phase == "arrived" { return "Here" }
            if phase == "delivered" { return "Done" }
            if let endsAt { return TemplateFormat.minutes(until: endsAt, now: now) }
        case .stages:
            if let endsAt, endsAt > now { return TemplateFormat.minutes(until: endsAt, now: now) }
            if let count = stageCount, let i = currentStage { return "\(i)/\(count)" }
        case .flight:
            guard let f = flight else { break }
            switch flightPhase(now: now) {
            case "landed": return f.carousel.map { "Belt \($0)" } ?? "Landed"
            // In minutes like every other countdown in the wings: "0:42" reads as seconds.
            case "airborne": if let a = f.arrives { return TemplateFormat.minutes(until: a, now: now) }
            default: if let d = f.departs { return TemplateFormat.minutes(until: d, now: now) }
            }
        case .route:
            if let n = route?.stopsLeft { return n == 1 ? "1 stop" : "\(n) stops" }
            if let d = route?.distance { return d }
            if let endsAt { return TemplateFormat.minutes(until: endsAt, now: now) }
        case .score:
            if let teams, teams.count == 2 { return "\(teams[0].score ?? "0")–\(teams[1].score ?? "0")" }
        case .timer:
            break
        case .workout:
            if let endsAt, endsAt > now { return Format.countdown(until: endsAt, now: now) }
            if let startedAt { return Format.clock(now.timeIntervalSince(startedAt)) }
            if let m = metrics?.first { return m.text }
        case .gauge:
            if let endsAt, endsAt > now { return TemplateFormat.minutes(until: endsAt, now: now) }
        case .liveAudio, .media:
            if let startedAt { return Format.clock(now.timeIntervalSince(startedAt)) }
            return nil
        case .agent:
            if state == .waiting { return "Needs you" }
            if let phase { return phase }
        case .progress:
            break
        }
        return trailingText(now: now)
    }

    /// How the template's time-based text changes on its own: a periodic refresh from `anchor`
    /// every `interval` seconds (1 for clocks, 60 for minute counts, aligned so each tick lands
    /// where the text changes), or nil when nothing changes until the next update.
    public func templateRefresh(now: Date) -> (anchor: Date, interval: TimeInterval)? {
        func until(_ deadline: Date?, _ step: TimeInterval) -> (anchor: Date, interval: TimeInterval)? {
            guard let deadline else { return nil }
            let remaining = deadline.timeIntervalSince(now)
            guard remaining > 0 else { return nil }
            return (deadline.addingTimeInterval(-step * (remaining / step).rounded(.up)), step)
        }
        func since(_ start: Date?) -> (anchor: Date, interval: TimeInterval)? { start.map { ($0, 1) } }
        switch resolvedTemplate {
        case .eta:
            return phase == "arrived" || phase == "delivered" ? nil : until(endsAt, 60)
        case .stages, .gauge:
            return until(endsAt, 60)
        case .flight:
            switch flightPhase(now: now) {
            case "airborne": return until(flight?.arrives, 60)
            case "landed": return nil
            default: return until(flight?.departs, 60)
            }
        case .route:
            return route?.stopsLeft != nil || route?.distance != nil ? nil : until(endsAt, 60)
        case .score:
            // Only the game clock (`endsAt` or `startedAt`) changes on its own.
            return until(endsAt, 1) ?? since(startedAt)
        case .workout:
            return until(endsAt, 1) ?? since(startedAt)
        case .liveAudio, .media:
            return since(startedAt)
        case .timer, .agent, .progress:
            return until(endsAt, 1) ?? since(startedAt)
        }
    }

    /// At most 5 characters for the minimal bubble: `compactShort`, else a short form of the
    /// changing value. Nil when the bubble shows a glyph or ring instead.
    public func minimalText(now: Date) -> String? {
        if let compactShort { return compactShort }
        switch resolvedTemplate {
        case .eta:
            if phase == "arrived" || phase == "delivered" { return nil }
            if let endsAt { return TemplateFormat.shortDuration(until: endsAt, now: now) }
        case .route:
            if let n = route?.stopsLeft { return "\(n)" }
            if let endsAt { return TemplateFormat.shortDuration(until: endsAt, now: now) }
        case .score:
            if let text = templateTrailing(now: now), text.count <= TemplateLimits.compactShort { return text }
        case .timer:
            if let endsAt { return TemplateFormat.shortDuration(until: endsAt, now: now) }
            if let startedAt { return TemplateFormat.shortDuration(since: startedAt, now: now) }
        case .workout:
            if let endsAt, endsAt > now { return TemplateFormat.shortDuration(until: endsAt, now: now) }
            if let startedAt { return TemplateFormat.shortDuration(since: startedAt, now: now) }
        case .gauge:
            if let p = clampedProgress { return "\(Int((p * 100).rounded()))" }
        case .stages, .flight, .liveAudio, .media, .agent, .progress:
            break
        }
        return nil
    }

    /// The wing's value in a few characters, for a wing too narrow for the full one ("18m"
    /// for "18 min", "2h" for "1:59:54", "3/7" for an agent's "Testing"): `compactShort`, else
    /// a short form of the changing value. Nil when there is none, and the wing shows a glyph
    /// or nothing rather than a shrunken or cut value. A route's stops are drawn beside a stop
    /// glyph instead.
    public func wingShort(now: Date) -> String? {
        if let compactShort { return compactShort }
        // A value sent in words ("4 min", a mirrored Live Activity's) shortens the same way.
        if let trailing, let short = TemplateFormat.compactUnits(trailing) { return short }
        return templateShort(now: now)
    }

    private func templateShort(now: Date) -> String? {
        func until(_ date: Date?) -> String? {
            guard let date, date > now else { return nil }
            return TemplateFormat.shortDuration(until: date, now: now)
        }
        func since(_ date: Date?) -> String? { date.map { TemplateFormat.shortDuration(since: $0, now: now) } }
        switch resolvedTemplate {
        case .eta:
            if phase == "arrived" || phase == "delivered" { return nil }
            return until(endsAt)
        case .stages:
            if let short = until(endsAt) { return short }
            if let count = stageCount, let i = currentStage { return "\(i)/\(count)" }
        case .flight:
            guard let f = flight else { break }
            switch flightPhase(now: now) {
            case "landed": return nil
            case "airborne": return until(f.arrives)
            default: return until(f.departs)
            }
        case .route:
            if route?.stopsLeft != nil || route?.distance != nil { return nil }
            return until(endsAt)
        case .score:
            if let text = templateTrailing(now: now), text.count <= TemplateLimits.compactShort { return text }
        case .gauge:
            if let short = until(endsAt) { return short }
            if let p = clampedProgress { return "\(Int((p * 100).rounded()))%" }
        case .liveAudio, .media:
            return since(startedAt)
        case .agent:
            if let steps, steps > 0, let step { return "\(min(step, steps))/\(steps)" }
        case .timer, .workout, .progress:
            return until(endsAt) ?? since(startedAt)
        }
        return nil
    }

    /// What the wing tries for the value `text`, in order: the full text, its short form, then
    /// a glyph (or nothing), each in the wing's one type size.
    /// - Parameters:
    ///   - narrow: the wing is narrower than `NarrowValue.wordRoom`, where a status word goes
    ///     straight to its glyph.
    ///   - leading: the symbol on the other side of the notch; a glyph that repeats it is left out.
    public func wingPlan(text: String, narrow: Bool, leading: String?, now: Date) -> WingPlan {
        let news = state == .waiting || state == .warning || state == .failure || state == .success
        // A status word ("Waiting", "Failed"), or no value at all where the state is news.
        // Work under way or plain information with no value shows nothing, at every width.
        let word = text.isEmpty && !news ? nil : NarrowValue.glyph(for: text, state: state)
        // A status word says more as its glyph than as a count would; only work under way
        // falls back to its count ("3/7") first.
        let statusWord = word != nil && state != .running && compactShort == nil
        let short = statusWord ? nil : wingShort(now: now)
        // Last of all an urgent value that fits in no form ("100%" in an icon-only wing) gives
        // way to its state's glyph rather than to nothing.
        let urgent = news && state != .success ? NarrowValue.glyph(for: "", state: state) : nil
        // The glyph that repeats the mark beside the notch ("Done" beside a checkmark) is left
        // out; the word is tried instead, even in a narrow wing.
        func shown(_ g: String?) -> String? { g.flatMap { NarrowValue.repeats($0, leading: leading) ? nil : $0 } }
        let glyph = shown(word)
        return WingPlan(full: text.isEmpty || (narrow && glyph != nil) ? nil : text,
                        short: short == text ? nil : short,
                        glyph: glyph ?? shown(urgent))
    }
}

/// The forms a wing's value can take, tried in order until one fits (`Activity.wingPlan`).
public struct WingPlan: Equatable, Sendable {
    /// The full value, unless the wing skips it.
    public var full: String?
    /// The short form ("18m") to try when the full value doesn't fit.
    public var short: String?
    /// The glyph to draw when neither fits; nil leaves the wing empty.
    public var glyph: String?

    public init(full: String?, short: String?, glyph: String?) {
        self.full = full
        self.short = short
        self.glyph = glyph
    }
}

/// Text formats used by the templates.
public enum TemplateFormat {
    /// Longest span the formats count (about 31 years). Dates come from API clients, and
    /// converting a larger number of seconds to `Int` would trap.
    static let maxSeconds: Double = 1e9

    /// Seconds from `start` to `end`, at least 0 and at most `maxSeconds`.
    static func span(_ start: Date, _ end: Date) -> Double {
        min(maxSeconds, max(0, end.timeIntervalSince(start)))
    }

    /// ETA style: "4 min", "Now" when due, whole hours beyond 99 minutes.
    public static func minutes(until date: Date, now: Date) -> String {
        let remaining = span(now, date)
        guard remaining > 0 else { return "Now" }
        let mins = Int((remaining / 60).rounded(.up))
        return mins < 100 ? "\(mins) min" : "\(Int((remaining / 3600).rounded())) h"
    }

    /// Departure board style: "0:42", "13:05", or days beyond 99 hours.
    public static func hoursMinutes(until date: Date, now: Date) -> String {
        let remaining = span(now, date)
        let mins = Int((remaining / 60).rounded(.up))
        if mins >= 100 * 60 { return "\(Int((remaining / 86400).rounded())) d" }
        return String(format: "%d:%02d", mins / 60, mins % 60)
    }

    /// Bubble style: "45s", "5m", "2h".
    public static func shortDuration(until date: Date, now: Date) -> String {
        short(span(now, date), roundUp: true)
    }

    /// Bubble style for a count-up: "12m".
    public static func shortDuration(since date: Date, now: Date) -> String {
        short(span(date, now), roundUp: false)
    }

    static func short(_ seconds: Double, roundUp: Bool) -> String {
        let round: FloatingPointRoundingRule = roundUp ? .up : .down
        if seconds < 60 { return "\(Int(seconds.rounded(round)))s" }
        // Minutes up to 99, as `minutes(until:)` counts them: 72 minutes is "72m", not a
        // rounded-up "2h".
        let minutes = Int((seconds / 60).rounded(round))
        if minutes < 100 { return "\(minutes)m" }
        return "\(Int((seconds / 3600).rounded(round)))h"
    }

    /// A value sent in words, in the same few characters: "4 min" → "4m", "2 hours" → "2h",
    /// "45 sec" → "45s". Nil for anything else.
    public static func compactUnits(_ text: String) -> String? {
        let parts = text.split(separator: " ")
        guard parts.count == 2, Double(parts[0]) != nil else { return nil }
        let unit = parts[1].lowercased()
        let short: String
        switch unit {
        case "min", "mins", "minute", "minutes": short = "m"
        case "h", "hr", "hrs", "hour", "hours": short = "h"
        case "s", "sec", "secs", "second", "seconds": short = "s"
        default: return nil
        }
        let shortened = String(parts[0]) + short
        return shortened.count <= TemplateLimits.compactShort ? shortened : nil
    }
}
