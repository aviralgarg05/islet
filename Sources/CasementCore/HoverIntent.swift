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

/// What keeps the open island open while the pointer is away from it.
public struct IslandHold: Equatable, Sendable {
    /// Opened with the shortcut, a link or a script, or held by an approval card.
    public var pinned = false
    /// A file is being dragged onto the island.
    public var draggingIn = false
    /// A shelf file is being dragged out of it, and the button is still down.
    public var draggingOut = false
    /// A control holds it: a slider being dragged, or a menu it opened.
    public var control = false
    /// A menu is open, a right-click menu included.
    public var menu = false
    /// A text field in the island has the keyboard (Ask, the timer's own time).
    public var typing = false

    public init(pinned: Bool = false, draggingIn: Bool = false, draggingOut: Bool = false, control: Bool = false,
                menu: Bool = false, typing: Bool = false) {
        self.pinned = pinned; self.draggingIn = draggingIn; self.draggingOut = draggingOut
        self.control = control; self.menu = menu; self.typing = typing
    }

    /// Whether the pointer leaving may close the island now.
    public var allowsClose: Bool { !(pinned || draggingIn || draggingOut || control || menu || typing) }
}

extension HoverIntent {
    /// The island closed while the pointer rested on the notch: by a swipe, the shortcut, a
    /// menu, a link or Ask (closing because the pointer left can't happen there). Resting on
    /// the notch mustn't open it again until the pointer has left it.
    public static func blocksReopen(wasOpen: Bool, isOpen: Bool, pointerOnNotch: Bool) -> Bool {
        wasOpen && !isOpen && pointerOnNotch
    }

    /// Which island a pointer sample is about.
    public enum Subject: Equatable, Sendable {
        /// The island on the display under the pointer.
        case here
        /// The island open on another display, which the pointer has left.
        case leavingOpen(UInt32)
    }

    /// With an island on every display, the pointer can leave the open island for another
    /// display's. Away from that display's notch it is leaving the open one, which closes after
    /// the grace period as it would for any other leave; on that notch it arms opening there,
    /// which moves the island.
    public static func subject(pointerOn display: UInt32, open: UInt32?, inTrigger: Bool) -> Subject {
        if let open, open != display, !inTrigger { return .leavingOpen(open) }
        return .here
    }
}

/// A peek (an activity's sneak peek or a new song) can open below the notch right under the
/// pointer. Its body then neither opens the island nor takes a click meant for what is under
/// it (a browser tab, say) until the pointer has left it and come back.
public struct PeekPointerGuard: Equatable, Sendable {
    /// The peek on show (`IslandLayout.key`), nil for anything else.
    public private(set) var peek: String?
    /// The peek whose body is being ignored.
    public private(set) var ignoring: String?

    public init() {}

    /// What the island shows now and whether the pointer is over the peek's body. Returns
    /// whether the body takes the pointer.
    @discardableResult
    public mutating func update(peek next: String?, pointerInBody: Bool) -> Bool {
        if next != peek {
            peek = next
            ignoring = next != nil && pointerInBody ? next : nil
        } else if !pointerInBody {
            ignoring = nil
        }
        return peek != nil && ignoring != peek
    }

    /// While a body is ignored, the pointer has to be followed even though it is nowhere near
    /// anything that takes it: otherwise nothing notices it leave, and the body stays dead to
    /// clicks for as long as the peek shows.
    public var followsPointer: Bool { ignoring != nil }
}

/// Tells a volume change you made from one an app or a headset made, so only yours shows a HUD.
/// A new sound output sets its own level (AirPods connecting), so changes just after one don't
/// show. While Casement replaces the system display, the keys show their own HUD, and other
/// changes (an app setting the volume) show only just after a key Casement handled.
public struct VolumeChangeFilter: Sendable {
    /// Seconds after the output changes during which volume changes are its own.
    public var afterOutputChange: TimeInterval
    /// Seconds after a handled key during which a change is that key's.
    public var afterKey: TimeInterval
    private var outputChangedAt: Date?
    private var keyAt: Date?

    public init(afterOutputChange: TimeInterval = 2, afterKey: TimeInterval = 0.5) {
        self.afterOutputChange = afterOutputChange
        self.afterKey = afterKey
    }

    public mutating func outputChanged(at now: Date) { outputChangedAt = now }
    public mutating func keyHandled(at now: Date) { keyAt = now }

    /// Whether a volume change reported at `now` shows a HUD.
    /// - Parameter replacing: Casement replaces the system's volume display.
    public func shows(now: Date, replacing: Bool) -> Bool {
        if let o = outputChangedAt, now.timeIntervalSince(o) < afterOutputChange { return false }
        guard replacing else { return true }
        return keyAt.map { now.timeIntervalSince($0) <= afterKey } ?? false
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
