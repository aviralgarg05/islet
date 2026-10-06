import Foundation

public struct BatteryState: Codable, Equatable, Sendable {
    /// 0...100
    public var level: Int
    public var isCharging: Bool
    public var isPluggedIn: Bool
    /// Minutes to empty (on battery) or to full (charging); nil while macOS is still estimating.
    public var minutesRemaining: Int?
    public var lowPowerMode: Bool
    /// Rated power of the connected adapter, when macOS reports it.
    public var adapterWatts: Int?

    public init(level: Int, isCharging: Bool, isPluggedIn: Bool, minutesRemaining: Int? = nil, lowPowerMode: Bool = false,
                adapterWatts: Int? = nil) {
        self.level = max(0, min(100, level))
        self.isCharging = isCharging
        self.isPluggedIn = isPluggedIn
        self.minutesRemaining = minutesRemaining
        self.lowPowerMode = lowPowerMode
        self.adapterWatts = adapterWatts
    }

    public var isFull: Bool { level >= 100 || (isPluggedIn && !isCharging && level >= 95) }

    /// One line for the expanded views: time to full or empty, "On hold" when plugged in but
    /// not charging (a charge limit or Optimised Charging), and the adapter's watts. Nil when
    /// macOS reports none of these.
    public var detail: String? {
        var parts: [String] = []
        if isCharging {
            if let t = Format.batteryTime(minutes: minutesRemaining) { parts.append("full in \(t)") }
        } else if isPluggedIn {
            parts.append(isFull ? "Charged" : "On hold")
        } else if let t = Format.batteryTime(minutes: minutesRemaining) {
            parts.append("\(t) left")
        }
        if isPluggedIn, let w = adapterWatts, w > 0 { parts.append("\(w) W") }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}

public enum BatteryEventKind: String, Codable, Sendable {
    case pluggedIn, unplugged, low, critical, full, lowPowerOn, lowPowerOff
    /// Charging reached the level set in `batteryChargedAlert`.
    case charged
}

public struct BatteryEvent: Equatable, Sendable {
    public var kind: BatteryEventKind
    public var state: BatteryState
    public var until: Date

    public init(kind: BatteryEventKind, state: BatteryState, until: Date) {
        self.kind = kind
        self.state = state
        self.until = until
    }
}

/// Turns a stream of battery readings into the few moments worth showing.
public struct BatteryEventDetector: Sendable {
    public var lowThreshold: Int
    public var criticalThreshold: Int
    /// Announce when charging reaches this level (nil = off).
    public var chargedLevel: Int?
    public var displayDuration: TimeInterval
    public private(set) var last: BatteryState?

    public init(lowThreshold: Int = 20, criticalThreshold: Int = 10, chargedLevel: Int? = nil, displayDuration: TimeInterval = 3) {
        self.lowThreshold = lowThreshold
        self.criticalThreshold = criticalThreshold
        self.chargedLevel = chargedLevel
        self.displayDuration = displayDuration
    }

    /// Take the thresholds from the user's settings.
    public mutating func configure(with settings: CasementSettings) {
        lowThreshold = settings.batteryLowThreshold
        criticalThreshold = settings.batteryCriticalThreshold
        chargedLevel = settings.batteryChargedAlert > 0 ? settings.batteryChargedAlert : nil
    }

    public mutating func ingest(_ new: BatteryState, now: Date) -> BatteryEvent? {
        defer { last = new }
        guard let old = last else { return nil }
        func event(_ k: BatteryEventKind) -> BatteryEvent {
            BatteryEvent(kind: k, state: new, until: now.addingTimeInterval(displayDuration))
        }
        if !old.lowPowerMode && new.lowPowerMode { return event(.lowPowerOn) }
        if old.lowPowerMode && !new.lowPowerMode { return event(.lowPowerOff) }
        if !old.isPluggedIn && new.isPluggedIn { return event(.pluggedIn) }
        if old.isPluggedIn && !new.isPluggedIn { return event(.unplugged) }
        if !new.isPluggedIn {
            if old.level > criticalThreshold && new.level <= criticalThreshold { return event(.critical) }
            if old.level > lowThreshold && new.level <= lowThreshold { return event(.low) }
        }
        if let target = chargedLevel, new.isPluggedIn, old.level < target, new.level >= target { return event(.charged) }
        if new.isPluggedIn && !old.isFull && new.isFull { return event(.full) }
        return nil
    }
}
