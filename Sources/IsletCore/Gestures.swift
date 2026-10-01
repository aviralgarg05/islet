import Foundation

/// Phase of a scroll event, mirroring `NSEvent.Phase` without AppKit.
public enum ScrollEventPhase: Sendable, Equatable {
    case none, mayBegin, began, changed, stationary, ended, cancelled
}

/// One scroll event, as delivered to a view.
public struct ScrollSample: Sendable, Equatable {
    /// `scrollingDeltaX/Y`: points on trackpads, lines on classic mouse wheels.
    public var dx: Double
    public var dy: Double
    public var phase: ScrollEventPhase
    public var momentum: ScrollEventPhase
    /// `hasPreciseScrollingDeltas` (trackpads, Magic Mouse).
    public var precise: Bool
    /// `isDirectionInvertedFromDevice` (natural scrolling).
    public var inverted: Bool
    /// Seconds, any monotonic clock (`NSEvent.timestamp`).
    public var time: TimeInterval

    public init(dx: Double, dy: Double, phase: ScrollEventPhase = .none, momentum: ScrollEventPhase = .none,
                precise: Bool = true, inverted: Bool = true, time: TimeInterval) {
        self.dx = dx; self.dy = dy; self.phase = phase; self.momentum = momentum
        self.precise = precise; self.inverted = inverted; self.time = time
    }

    /// Movement of the fingers (or wheel) in screen terms, whatever the scroll direction
    /// setting: positive x is rightwards, positive y is downwards.
    public var travel: (x: Double, y: Double) {
        inverted ? (dx, dy) : (-dx, -dy)
    }
}

/// Direction the fingers moved.
public enum SwipeDirection: String, Sendable, Equatable, CaseIterable {
    case up, down, left, right
}

/// Turns scroll events into discrete swipes. A swipe fires once per gesture, as soon as the
/// fingers have travelled `threshold` points along one axis within `window` seconds.
/// Momentum (inertia) never fires, and a gesture that has fired stays quiet until it ends,
/// so one flick is one action.
public struct SwipeRecognizer: Sendable {
    public var threshold: Double
    public var window: TimeInterval
    /// Points per line for classic wheels, which report lines rather than points.
    public var lineHeight: Double
    /// Wheels have no phases: a pause this long ends one wheel "gesture".
    public var wheelGap: TimeInterval
    /// The winning axis must be this much larger than the other one.
    public var dominance: Double

    private var tracking = false
    private var fired = false
    private var samples: [(time: TimeInterval, x: Double, y: Double)] = []
    private var lastWheel: TimeInterval?

    public init(threshold: Double = 24, window: TimeInterval = 0.25, lineHeight: Double = 8,
                wheelGap: TimeInterval = 0.3, dominance: Double = 1.5) {
        self.threshold = threshold
        self.window = window
        self.lineHeight = lineHeight
        self.wheelGap = wheelGap
        self.dominance = dominance
    }

    public mutating func feed(_ s: ScrollSample) -> SwipeDirection? {
        if s.momentum != .none { return nil }
        let t = s.travel
        if s.phase == .none {
            // Classic wheel (or a device without phases): gestures are separated by pauses.
            if let last = lastWheel, s.time - last <= wheelGap {
                if fired { lastWheel = s.time; return nil }
            } else {
                reset()
            }
            lastWheel = s.time
            let scale = s.precise ? 1 : lineHeight
            return add(time: s.time, x: t.x * scale, y: t.y * scale)
        }
        switch s.phase {
        case .mayBegin:
            reset()
            return nil
        case .began:
            reset()
            tracking = true
            return add(time: s.time, x: t.x, y: t.y)
        case .changed:
            guard tracking, !fired else { return nil }
            return add(time: s.time, x: t.x, y: t.y)
        case .ended, .cancelled:
            reset()
            return nil
        case .stationary, .none:
            return nil
        }
    }

    private mutating func reset() {
        tracking = false
        fired = false
        samples.removeAll()
    }

    private mutating func add(time: TimeInterval, x: Double, y: Double) -> SwipeDirection? {
        guard !fired else { return nil }
        samples.append((time, x, y))
        samples.removeAll { time - $0.time > window }
        let sx = samples.reduce(0) { $0 + $1.x }
        let sy = samples.reduce(0) { $0 + $1.y }
        let direction: SwipeDirection?
        if abs(sy) >= threshold, abs(sy) >= abs(sx) * dominance {
            direction = sy > 0 ? .down : .up
        } else if abs(sx) >= threshold, abs(sx) >= abs(sy) * dominance {
            direction = sx > 0 ? .right : .left
        } else {
            direction = nil
        }
        if direction != nil {
            fired = true
            samples.removeAll()
        }
        return direction
    }
}

/// What a horizontal swipe on playing media does.
public enum MediaSwipeAction: String, Codable, Sendable, CaseIterable {
    /// Next or previous track.
    case track
    /// Jump 10 s forward or back.
    case seek
}

/// Where on the island a swipe happened.
public enum GestureSurface: Equatable, Sendable {
    /// Closed with nothing, a HUD or a battery event showing.
    case closed
    case sneak
    case compactMedia
    case compactActivity
    /// Open; `media` when the Home tab shows the Now Playing card.
    case expanded(media: Bool)

    public static func from(_ p: IslandPresentation, homeShowsMedia: Bool) -> GestureSurface? {
        switch p {
        case .hidden: return nil
        case .idle, .hud, .compact(.battery): return .closed
        case .sneak: return .sneak
        // A new song on show is music too: swiping sideways changes track.
        case .compact(.nowPlaying), .songPeek: return .compactMedia
        case .compact(.activity): return .compactActivity
        case .expanded: return .expanded(media: homeShowsMedia)
        }
    }
}

public enum GestureAction: Equatable, Sendable {
    case expand
    case collapse
    case nextTrack
    case previousTrack
    /// Seek by this many seconds.
    case seek(Double)
    /// Show the next (or previous) activity in the closed island.
    case cycle(forward: Bool)
}

/// The gesture grammar: which swipe does what, where. Swiping left moves forward (next track,
/// next activity), like paging.
public enum GestureMap {
    public static func action(for swipe: SwipeDirection, on surface: GestureSurface, settings s: IsletSettings) -> GestureAction? {
        guard s.gesturesEnabled else { return nil }
        switch swipe {
        case .down:
            if case .expanded = surface { return nil }
            return s.swipeDownToOpen ? .expand : nil
        case .up:
            if case .expanded = surface { return s.swipeUpToClose ? .collapse : nil }
            return nil
        case .left, .right:
            // Left moves forward, like paging, unless "Reverse sideways swipes" is on.
            let forward = (swipe == .left) != s.reverseSideSwipes
            switch surface {
            case .compactMedia, .expanded(media: true):
                guard s.swipeMedia else { return nil }
                switch s.swipeMediaAction {
                case .track: return forward ? .nextTrack : .previousTrack
                case .seek: return .seek(forward ? MediaSeek.swipeInterval : -MediaSeek.swipeInterval)
                }
            case .compactActivity:
                return s.swipeCyclesActivities ? .cycle(forward: forward) : nil
            default:
                return nil
            }
        }
    }
}

/// Swiping through the activities in the closed island (the compact one and its bubbles).
public enum CompactCycle {
    /// The activity to bring forward after `current`, or nil when there is nothing to cycle to.
    public static func next(after current: String?, in ordered: [Activity], forward: Bool) -> String? {
        guard ordered.count > 1 else { return nil }
        guard let current, let i = ordered.firstIndex(where: { $0.id == current }) else { return ordered.first?.id }
        let n = ordered.count
        return ordered[(i + (forward ? 1 : n - 1)) % n].id
    }
}
