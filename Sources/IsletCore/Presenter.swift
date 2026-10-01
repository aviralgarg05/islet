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
    /// A new song, shown for a moment below the notch (`SongPeek`).
    case songPeek(NowPlaying)
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
    /// How paused media shows in the compact island (`PausedMusic`). Hidden unless it was paused
    /// a moment ago or is kept for good: paused music is noise once the pause has been seen.
    public var pausedMedia: PausedMediaShow
    /// The activity the user brought forward by swiping; it stays in the compact island while it exists.
    public var focusedActivityID: String?
    /// A new song to show for a moment (`SongPeek.current`). It gives way to a HUD and to an
    /// activity's sneak peek, and never shows while the island is open or hidden.
    public var songPeek: NowPlaying?

    public init(now: Date, center: ActivityCenter, nowPlaying: NowPlaying? = nil, batteryEvent: BatteryEvent? = nil,
                isExpanded: Bool = false, isSuppressed: Bool = false, pausedMedia: PausedMediaShow = .hidden,
                focusedActivityID: String? = nil, songPeek: NowPlaying? = nil) {
        self.now = now; self.center = center; self.nowPlaying = nowPlaying; self.batteryEvent = batteryEvent
        self.isExpanded = isExpanded; self.isSuppressed = isSuppressed; self.pausedMedia = pausedMedia
        self.focusedActivityID = focusedActivityID; self.songPeek = songPeek
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
        if let song = i.songPeek { return .songPeek(song) }

        let ordered = i.center.ordered(now: i.now)
        let others = max(0, ordered.count - 1)
        // A swiped-to activity stays forward, except over a critical one (a critical battery warning, say).
        if let id = i.focusedActivityID, let focused = ordered.first(where: { $0.id == id }),
           focused.priority >= .critical || (ordered.first?.priority ?? .low) < .critical {
            return .compact(.activity(focused, others: others))
        }
        if let top = ordered.first, top.priority >= .high {
            return .compact(.activity(top, others: others))
        }
        if let b = i.batteryEvent, b.until > i.now {
            return .compact(.battery(b))
        }
        // Music paused a moment ago keeps its place, so the pause is seen before it goes.
        if let np = i.nowPlaying, np.isPlaying || i.pausedMedia == .recent {
            return .compact(.nowPlaying(np))
        }
        if let top = ordered.first {
            return .compact(.activity(top, others: others))
        }
        if let np = i.nowPlaying, i.pausedMedia == .kept {
            return .compact(.nowPlaying(np))
        }
        return .idle
    }
}
