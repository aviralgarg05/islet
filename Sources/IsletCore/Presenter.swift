import Foundation

/// What the closed/compact island shows beside the notch.
public enum CompactContent: Equatable, Sendable {
    case nowPlaying(NowPlaying)
    case activity(Activity, others: Int)
    case battery(BatteryEvent)
}

/// The single source of truth for what the island looks like right now.
public enum IslandPresentation: Equatable, Sendable {
    /// Not drawn at all (e.g. a fullscreen app is in front and the user wants it out of the way).
    case hidden
    /// Just the notch, no wings.
    case idle
    case hud(HUDEvent)
    case sneak(Activity)
    case compact(CompactContent)
    case expanded
}

public struct PresenterInputs: Sendable {
    public var now: Date
    public var center: ActivityCenter
    public var nowPlaying: NowPlaying?
    public var batteryEvent: BatteryEvent?
    public var isExpanded: Bool
    /// A fullscreen app (or screen sharing, or a per-app rule) asked us to get out of the way.
    public var isSuppressed: Bool
    /// Show paused media in the compact island (off by default: paused music is noise).
    public var showPausedMedia: Bool

    public init(now: Date, center: ActivityCenter, nowPlaying: NowPlaying? = nil, batteryEvent: BatteryEvent? = nil,
                isExpanded: Bool = false, isSuppressed: Bool = false, showPausedMedia: Bool = false) {
        self.now = now; self.center = center; self.nowPlaying = nowPlaying; self.batteryEvent = batteryEvent
        self.isExpanded = isExpanded; self.isSuppressed = isSuppressed; self.showPausedMedia = showPausedMedia
    }
}

public enum Presenter {
    public static func present(_ i: PresenterInputs) -> IslandPresentation {
        let hud = i.center.currentHUD(now: i.now)
        let sneak = i.center.currentSneak(now: i.now)

        if i.isSuppressed {
            // In fullscreen we only surface what the user directly caused (HUD) or must see.
            if let hud { return .hud(hud) }
            if let sneak, sneak.priority == .critical { return .sneak(sneak) }
            return .hidden
        }
        if i.isExpanded { return .expanded }
        if let hud { return .hud(hud) }
        if let sneak { return .sneak(sneak) }

        let ordered = i.center.ordered(now: i.now)
        let others = max(0, ordered.count - 1)
        if let top = ordered.first, top.priority >= .high {
            return .compact(.activity(top, others: others))
        }
        if let b = i.batteryEvent, b.until > i.now {
            return .compact(.battery(b))
        }
        if let np = i.nowPlaying, np.isPlaying {
            return .compact(.nowPlaying(np))
        }
        if let top = ordered.first {
            return .compact(.activity(top, others: others))
        }
        if let np = i.nowPlaying, i.showPausedMedia {
            return .compact(.nowPlaying(np))
        }
        return .idle
    }
}
