import Foundation

public struct BatteryState: Codable, Equatable, Sendable {
    /// 0...100
    public var level: Int
    public var isCharging: Bool
    public var isPluggedIn: Bool
    /// Minutes to empty (on battery) or to full (charging); nil while macOS is still estimating.
    public var minutesRemaining: Int?
    public var lowPowerMode: Bool

    public init(level: Int, isCharging: Bool, isPluggedIn: Bool, minutesRemaining: Int? = nil, lowPowerMode: Bool = false) {
        self.level = max(0, min(100, level))
        self.isCharging = isCharging
        self.isPluggedIn = isPluggedIn
        self.minutesRemaining = minutesRemaining
        self.lowPowerMode = lowPowerMode
    }

    public var isFull: Bool { level >= 100 || (isPluggedIn && !isCharging && level >= 95) }
}

public enum BatteryEventKind: String, Codable, Sendable {
    case pluggedIn, unplugged, low, critical, full, lowPowerOn, lowPowerOff
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
    public var displayDuration: TimeInterval
    public private(set) var last: BatteryState?

    public init(lowThreshold: Int = 20, criticalThreshold: Int = 10, displayDuration: TimeInterval = 3) {
        self.lowThreshold = lowThreshold
        self.criticalThreshold = criticalThreshold
        self.displayDuration = displayDuration
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
        if new.isPluggedIn && !old.isFull && new.isFull { return event(.full) }
        return nil
    }
}
