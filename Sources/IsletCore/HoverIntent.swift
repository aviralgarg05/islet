import CoreGraphics
import Foundation

/// Decides when hovering should open or close the island.
///
/// Opening on the first mouse-over is the most common complaint about notch apps: you reach
/// for a menu-bar item or the top of a browser tab and the island pops open. We require the
/// pointer to *dwell* inside the zone and to be moving slowly, and we close only after the
/// pointer has been outside the expanded area for a grace period.
public struct HoverIntent: Sendable {
    public enum Decision: Equatable, Sendable { case none, open, close }

    public var openDelay: TimeInterval
    public var closeDelay: TimeInterval
    /// Pointer speed (points/second) above which a pass-through is ignored.
    public var maxOpenSpeed: CGFloat

    public private(set) var enteredAt: Date?
    public private(set) var exitedAt: Date?
    private var lastPoint: CGPoint?
    private var lastTime: Date?
    public private(set) var speed: CGFloat = 0

    public init(openDelay: TimeInterval = 0.18, closeDelay: TimeInterval = 0.35, maxOpenSpeed: CGFloat = 900) {
        self.openDelay = openDelay
        self.closeDelay = closeDelay
        self.maxOpenSpeed = maxOpenSpeed
    }

    /// Feed a pointer sample.
    /// - Parameters:
    ///   - inTrigger: pointer is within the (small) zone that arms opening.
    ///   - inExpanded: pointer is within the currently visible island (used for closing).
    ///   - isOpen: whether the island is expanded right now.
    public mutating func sample(point: CGPoint, now: Date, inTrigger: Bool, inExpanded: Bool, isOpen: Bool) -> Decision {
        if let lp = lastPoint, let lt = lastTime {
            let dt = now.timeIntervalSince(lt)
            if dt > 0 {
                let d = hypot(point.x - lp.x, point.y - lp.y)
                // Smooth so one jittery sample does not dominate.
                speed = speed * 0.5 + CGFloat(Double(d) / dt) * 0.5
            }
        }
        lastPoint = point
        lastTime = now

        if isOpen {
            enteredAt = nil
            if inExpanded || inTrigger {
                exitedAt = nil
                return .none
            }
            if exitedAt == nil { exitedAt = now }
            return now.timeIntervalSince(exitedAt!) >= closeDelay ? .close : .none
        }

        exitedAt = nil
        guard inTrigger else {
            enteredAt = nil
            return .none
        }
        if enteredAt == nil { enteredAt = now }
        if speed > maxOpenSpeed { return .none }
        return now.timeIntervalSince(enteredAt!) >= openDelay ? .open : .none
    }

    /// Called from a timer when no mouse events arrive (pointer resting still).
    public mutating func tick(now: Date, isOpen: Bool) -> Decision {
        if isOpen, let exitedAt, now.timeIntervalSince(exitedAt) >= closeDelay { return .close }
        if !isOpen, let enteredAt, now.timeIntervalSince(enteredAt) >= openDelay {
            speed = 0
            return .open
        }
        return .none
    }

    public mutating func reset() {
        enteredAt = nil
        exitedAt = nil
        lastPoint = nil
        lastTime = nil
        speed = 0
    }
}

/// Separates deliberate brightness changes (keys, Control Center slider) from ambient-light
/// auto-brightness drift, which reports through the same callback.
///
/// A burst of changes counts as deliberate once it moves the level by `threshold` within
/// `window` seconds. Once a burst is deliberate, every further change in it is shown.
public struct BrightnessChangeFilter: Sendable {
    public var threshold: Double
    public var window: TimeInterval
    private var baseline: Double?
    private var burstStart: Date?
    private var lastEvent: Date?
    private var deliberate = false
    private var lastValue: Double?

    public init(threshold: Double = 0.04, window: TimeInterval = 0.8) {
        self.threshold = threshold
        self.window = window
    }

    /// Returns true when this change should show the HUD.
    public mutating func ingest(_ value: Double, now: Date) -> Bool {
        defer {
            lastEvent = now
            lastValue = value
        }
        if let last = lastValue, abs(last - value) < 0.0005 { return false }
        if let t = lastEvent, now.timeIntervalSince(t) <= window, let start = burstStart, let base = baseline {
            if deliberate { return true }
            if abs(value - base) >= threshold, now.timeIntervalSince(start) <= window * 2 {
                deliberate = true
                return true
            }
            return false
        }
        // New burst.
        baseline = lastValue ?? value
        burstStart = now
        deliberate = abs(value - (lastValue ?? value)) >= threshold
        return deliberate
    }
}
