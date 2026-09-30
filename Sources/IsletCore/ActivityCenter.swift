import Foundation

/// Transient on-screen display (replaces the system volume/brightness bezel).
public enum HUDKind: String, Codable, Sendable, CaseIterable {
    case volume, brightness, keyboardBrightness, microphone
}

public struct HUDEvent: Equatable, Sendable, Codable {
    public var kind: HUDKind
    /// 0...1
    public var value: Double
    public var muted: Bool
    /// Optional label, e.g. the output device name ("AirPods Pro").
    public var label: String?
    public var until: Date

    public init(kind: HUDKind, value: Double, muted: Bool = false, label: String? = nil, until: Date) {
        self.kind = kind
        self.value = min(1, max(0, value))
        self.muted = muted
        self.label = label
        self.until = until
    }
}

/// Owns every live activity plus the transient HUD / sneak-peek state.
/// A value type with an injected clock, so every rule here is unit-testable.
public struct ActivityCenter: Sendable {
    public private(set) var activities: [String: Activity] = [:]
    public private(set) var hud: HUDEvent?
    /// The activity currently being "sneak peeked" (briefly expanded) and until when.
    public private(set) var sneak: (id: String, until: Date)?

    public var maxActivities: Int
    public var sneakDuration: TimeInterval
    public var hudDuration: TimeInterval
    /// Auto-dismiss delay applied when an activity reaches success/failure without an explicit ttl.
    public var finishedTTL: TimeInterval

    public init(maxActivities: Int = 64, sneakDuration: TimeInterval = 2.5, hudDuration: TimeInterval = 1.6, finishedTTL: TimeInterval = 10) {
        self.maxActivities = maxActivities
        self.sneakDuration = sneakDuration
        self.hudDuration = hudDuration
        self.finishedTTL = finishedTTL
    }

    public static func isValidID(_ id: String) -> Bool {
        guard (1...128).contains(id.count) else { return false }
        return id.unicodeScalars.allSatisfy { c in
            CharacterSet.alphanumerics.contains(c) && c.isASCII || "._:-".unicodeScalars.contains(c)
        }
    }

    /// Normalise progress: negative = indeterminate, (1, 100] is treated as a percentage.
    static func normalizeProgress(_ p: Double) throws -> Double {
        guard p.isFinite else { throw ActivityError.invalidProgress(p) }
        if p < 0 { return -1 }
        if p <= 1 { return p }
        if p <= 100 { return p / 100 }
        throw ActivityError.invalidProgress(p)
    }

    /// Create or update (upsert) an activity from a client spec.
    @discardableResult
    public mutating func apply(_ spec: ActivitySpec, now: Date, makeID: () -> String = { UUID().uuidString.lowercased() }) throws -> Activity {
        let id = spec.id ?? makeID()
        guard Self.isValidID(id) else { throw ActivityError.invalidID(id) }
        if let tint = spec.tint, RGBA.parse(tint) == nil { throw ActivityError.invalidTint(tint) }
        try spec.validateTemplateFields()
        let progress = try spec.progress.map(Self.normalizeProgress)

        if var existing = activities[id] {
            let previousState = existing.state
            existing.stretchTrack(to: spec.endsAt, now: now)
            if let v = spec.source { existing.source = v }
            if let v = spec.title { existing.title = v }
            if let v = spec.subtitle { existing.subtitle = v.isEmpty ? nil : v }
            if let v = spec.icon { existing.icon = v }
            if let v = spec.trailing { existing.trailing = v.isEmpty ? nil : v }
            if let v = progress { existing.progress = v }
            if let v = spec.state { existing.state = v }
            if let v = spec.tint { existing.tint = v }
            if let v = spec.priority { existing.priority = v }
            if let v = spec.endsAt { existing.endsAt = v }
            if let v = spec.startedAt { existing.startedAt = v }
            if let v = spec.url { existing.url = v }
            if let v = spec.staleAt { existing.staleAt = v }
            if let v = spec.relevance { existing.relevance = min(100, max(0, v)) }
            if let v = spec.steps { existing.steps = max(1, v) }
            if let v = spec.step { existing.step = max(0, v) }
            if let v = spec.actions { existing.actions = v }
            existing.mergeTemplateFields(spec)
            existing.expiresAt = expiry(ttl: spec.ttl, state: existing.state, previous: existing.expiresAt, now: now)
            existing.updatedAt = now
            activities[id] = existing
            let becameTerminal = existing.state != previousState && (existing.state == .success || existing.state == .failure)
            if spec.sneak == true || (spec.sneak != false && becameTerminal) {
                sneak = (id, now.addingTimeInterval(sneakDuration))
            }
            return existing
        }

        guard let title = spec.title, !title.isEmpty else { throw ActivityError.missingTitle }
        let state = spec.state ?? (progress != nil ? .running : .info)
        var activity = Activity(
            id: id,
            source: spec.source ?? "api",
            title: title,
            subtitle: spec.subtitle.flatMap { $0.isEmpty ? nil : $0 },
            icon: spec.icon,
            trailing: spec.trailing.flatMap { $0.isEmpty ? nil : $0 },
            progress: progress,
            state: state,
            tint: spec.tint,
            priority: spec.priority ?? .normal,
            endsAt: spec.endsAt,
            startedAt: spec.startedAt,
            url: spec.url,
            staleAt: spec.staleAt,
            relevance: spec.relevance.map { min(100, max(0, $0)) },
            steps: spec.steps.map { max(1, $0) },
            step: spec.step.map { max(0, $0) },
            expiresAt: expiry(ttl: spec.ttl, state: state, previous: nil, now: now),
            actions: spec.actions ?? [],
            createdAt: now,
            updatedAt: now
        )
        activity.mergeTemplateFields(spec)
        activity.stretchTrack(to: spec.endsAt, now: now)
        activities[id] = activity
        evictIfNeeded()
        if spec.sneak ?? (activity.priority >= .normal) {
            sneak = (id, now.addingTimeInterval(sneakDuration))
        }
        return activity
    }

    private func expiry(ttl: Double?, state: ActivityState, previous: Date?, now: Date) -> Date? {
        if let ttl {
            return ttl > 0 ? now.addingTimeInterval(ttl) : nil
        }
        if previous == nil, state == .success || state == .failure {
            return now.addingTimeInterval(finishedTTL)
        }
        return previous
    }

    private mutating func evictIfNeeded() {
        guard activities.count > maxActivities else { return }
        // Drop the least important, least recently updated activities first.
        let victims = activities.values
            .sorted { ($0.priority, $0.updatedAt) < ($1.priority, $1.updatedAt) }
            .prefix(activities.count - maxActivities)
        for v in victims { activities[v.id] = nil }
    }

    @discardableResult
    public mutating func remove(id: String) -> Activity? {
        if sneak?.id == id { sneak = nil }
        return activities.removeValue(forKey: id)
    }

    /// Remove every activity posted by `source`; returns how many were removed.
    @discardableResult
    public mutating func removeAll(source: String) -> Int {
        let ids = activities.values.filter { $0.source == source }.map(\.id)
        for id in ids { remove(id: id) }
        return ids.count
    }

    public mutating func removeAll() {
        activities.removeAll()
        sneak = nil
    }

    /// Drop expired activities, HUD and sneak state. Returns ids of removed activities.
    @discardableResult
    public mutating func expire(now: Date) -> [String] {
        let dead = activities.values.filter { ($0.expiresAt ?? .distantFuture) <= now }.map(\.id)
        for id in dead { activities[id] = nil }
        if let h = hud, h.until <= now { hud = nil }
        if let s = sneak, s.until <= now || activities[s.id] == nil { sneak = nil }
        return dead.sorted()
    }

    /// Activities in display order: priority, then most recently updated.
    public func ordered(now: Date) -> [Activity] {
        activities.values
            .filter { ($0.expiresAt ?? .distantFuture) > now }
            .sorted { a, b in
                if a.priority != b.priority { return a.priority > b.priority }
                // Stale content sinks below fresh content of the same priority.
                let sa = a.isStale(at: now), sb = b.isStale(at: now)
                if sa != sb { return !sa }
                let ra = a.relevance ?? 50, rb = b.relevance ?? 50
                if ra != rb { return ra > rb }
                if a.updatedAt != b.updatedAt { return a.updatedAt > b.updatedAt }
                return a.id < b.id
            }
    }

    public func primary(now: Date) -> Activity? { ordered(now: now).first }

    public mutating func showHUD(_ kind: HUDKind, value: Double, muted: Bool = false, label: String? = nil, now: Date) {
        hud = HUDEvent(kind: kind, value: value, muted: muted, label: label, until: now.addingTimeInterval(hudDuration))
    }

    public func currentHUD(now: Date) -> HUDEvent? {
        guard let hud, hud.until > now else { return nil }
        return hud
    }

    public func currentSneak(now: Date) -> Activity? {
        guard let s = sneak, s.until > now else { return nil }
        return activities[s.id]
    }

    public mutating func cancelSneak() { sneak = nil }

    /// The next moment the visible state changes on its own. The app schedules one timer
    /// for this instead of polling, which keeps idle CPU at zero.
    public func nextDeadline(now: Date) -> Date? {
        var candidates: [Date] = activities.values.compactMap(\.expiresAt) + activities.values.compactMap(\.staleAt)
        if let h = hud { candidates.append(h.until) }
        if let s = sneak { candidates.append(s.until) }
        return candidates.filter { $0 > now }.min()
    }

    /// Whether any visible activity needs a once-per-second refresh (live countdown).
    public func needsClockTick(now: Date) -> Bool {
        activities.values.contains { a in
            if a.startedAt != nil { return true }
            guard let end = a.endsAt else { return false }
            return end > now.addingTimeInterval(-1)
        }
    }
}
