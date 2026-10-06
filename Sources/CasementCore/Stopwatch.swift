import Foundation

/// A stopwatch with laps, as a value with an injected clock. Nothing ticks: the elapsed time is
/// worked out from when it last started, and the island's count-up does the rest.
public struct Stopwatch: Codable, Equatable, Sendable {
    public static let activityID = "stopwatch"
    public static let source = "stopwatch"
    public static let maxLaps = 99

    /// When it last started or resumed; nil while paused or reset.
    public private(set) var runningSince: Date?
    /// Time counted before `runningSince`.
    public private(set) var banked: TimeInterval = 0
    /// The elapsed time at each lap press, oldest first.
    public private(set) var laps: [TimeInterval] = []

    public init() {}

    public var isRunning: Bool { runningSince != nil }
    /// Running, or paused with time on it.
    public var isActive: Bool { isRunning || banked > 0 }

    public func elapsed(at now: Date) -> TimeInterval {
        banked + (runningSince.map { max(0, now.timeIntervalSince($0)) } ?? 0)
    }

    /// Starts from zero, or carries on after a pause.
    public mutating func start(now: Date) {
        guard runningSince == nil else { return }
        runningSince = now
    }

    public mutating func pause(now: Date) {
        guard let since = runningSince else { return }
        banked += max(0, now.timeIntervalSince(since))
        runningSince = nil
    }

    public mutating func toggle(now: Date) {
        if isRunning { pause(now: now) } else { start(now: now) }
    }

    /// Notes the time. Only while running, and at most `maxLaps`.
    public mutating func lap(now: Date) {
        guard isRunning, laps.count < Self.maxLaps else { return }
        laps.append(elapsed(at: now))
    }

    public mutating func reset() {
        self = Stopwatch()
    }

    /// How long each lap took, oldest first.
    public var lapDurations: [TimeInterval] {
        laps.enumerated().map { i, t in t - (i == 0 ? 0 : laps[i - 1]) }
    }

    /// The activity that shows it beside the notch: a count-up while it runs, the time it stopped
    /// at while paused. Nil once reset.
    public func spec(now: Date) -> ActivitySpec? {
        guard isActive else { return nil }
        var spec = ActivitySpec(id: Self.activityID, source: Self.source, title: "Stopwatch", icon: .symbol("stopwatch.fill"),
                                tint: "teal", priority: .normal, ttl: 0, sneak: false)
        if let since = runningSince {
            spec.state = .running
            spec.startedAt = since.addingTimeInterval(-banked)
            spec.subtitle = laps.isEmpty ? nil : "Lap \(laps.count + 1)"
        } else {
            spec.state = .info
            spec.tint = "gray"
            spec.trailing = "Paused"
            spec.subtitle = Format.clock(banked)
        }
        return spec
    }

    // MARK: Storage

    public static func load(from url: URL) -> Stopwatch? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        let d = JSONDecoder()
        d.dateDecodingStrategy = .secondsSince1970
        return try? d.decode(Stopwatch.self, from: data)
    }

    public func save(to url: URL) throws {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .secondsSince1970
        e.outputFormatting = [.sortedKeys]
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try e.encode(self).write(to: url, options: .atomic)
    }
}
