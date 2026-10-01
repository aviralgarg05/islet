import Foundation

/// Which displays get an island.
public enum DisplayMode: String, Codable, Sendable, CaseIterable {
    /// The built-in notched display if there is one, otherwise the main display.
    case notchedScreen
    /// Whichever display currently has the menu bar / key focus.
    case mainScreen
    /// Every connected display.
    case allScreens
}

/// What the island does while an app is in full screen on its display.
public enum FullscreenBehaviour: String, Codable, Sendable, CaseIterable {
    /// It stays as it is.
    case show
    /// Music goes; activities, timers and HUDs stay.
    case hideMusic
    /// It hides, except for HUDs and critical alerts.
    case hide
}

/// How the island looks on a display without a notch.
public enum NotchlessStyle: String, Codable, Sendable, CaseIterable {
    /// A pill floating in the menu bar, clear of the screen's top edge.
    case pill
    /// A notch drawn at the top edge, like a MacBook's.
    case notch
    /// Nothing until the pointer reaches the top edge, then the pill.
    case hover
    /// No island on displays without a notch.
    case hidden

    /// Whether the closed island floats as a pill rather than hanging from the top edge.
    public var floats: Bool { self == .pill || self == .hover }
}

/// Overall island size.
public enum SizePreset: String, Codable, Sendable, CaseIterable {
    case compact, standard, large, custom

    /// (expanded width, expanded height, wing width) in points.
    public var dimensions: (width: Double, height: Double, wing: Double)? {
        switch self {
        case .compact: return (468, 150, 52)
        case .standard: return (560, 180, 66)
        case .large: return (660, 224, 84)
        case .custom: return nil
        }
    }
}

/// How the island moves between states.
public enum AnimationStyle: String, Codable, Sendable, CaseIterable {
    /// Springy morphing with a little overshoot, like the iPhone.
    case fluid
    /// Quick and tight.
    case snappy
    /// Soft, no overshoot.
    case smooth
    /// Short fades only.
    case minimal
    /// No animation at all.
    case off
}

/// How quickly the island moves, whatever the animation style.
public enum AnimationSpeed: String, Codable, Sendable, CaseIterable {
    case relaxed, normal, quick

    /// How long each move takes against Normal: springs and fades are this much longer.
    public var multiplier: Double {
        switch self {
        case .relaxed: return 1.25
        case .normal: return 1
        case .quick: return 0.8
        }
    }
}

/// When the trackpad taps.
public enum HapticsMode: String, Codable, Sendable, CaseIterable {
    case off
    /// Only when you act on the island (open, press, drop). Recommended.
    case direct
    /// Also when something important arrives (your hand may be on the trackpad for other work).
    case all
}

/// Which side of the notch extra activities appear on.
public enum BubblePlacement: String, Codable, Sendable, CaseIterable {
    case right, left
}

/// Island surface.
public enum IslandTheme: String, Codable, Sendable, CaseIterable {
    /// Pure black, blends with the hardware notch.
    case black
    /// Dark graphite with a hairline edge.
    case graphite
    /// Dynamic Glass: the menu bar row stays black over the notch and the open island melts
    /// into Liquid Glass below it. `glassLevel` sets how far down the black reaches.
    case glass
}

/// How the playing indicator beside the notch looks.
public enum VisualiserStyle: String, Codable, Sendable, CaseIterable {
    /// Four bars.
    case bars
    /// Six thin bars.
    case slim
    /// Three bobbing dots.
    case dots
    /// One flowing line, like a sound wave.
    case wave
    /// A dot with a ring that ripples out from it.
    case pulse
    /// No indicator: the artwork alone shows what's playing.
    case off
}

/// Where the music's colour comes from: the playing indicator, the song progress ring and the
/// open island's progress bar, shuffle and repeat. Replaces `visualiserColour`, which coloured
/// the indicator alone.
public enum MusicColour: String, Codable, Sendable, CaseIterable {
    /// The artwork's main colour.
    case artwork
    /// The accent colour from Appearance.
    case accent
    case white
}

/// What colour the volume, brightness and other HUDs take.
public enum HUDColour: String, Codable, Sendable, CaseIterable {
    /// White, like the rest of the closed island.
    case white
    /// The accent colour from Appearance.
    case accent
    /// One colour per kind: volume green, brightness yellow, keyboard light blue, microphone orange.
    case colourful

    /// The colour a HUD of `kind` takes in the colourful look, as hex (system colours for dark mode).
    public static func colourful(_ kind: HUDKind) -> String {
        switch kind {
        case .volume: return "#30D158"
        case .brightness: return "#FFD60A"
        case .keyboardBrightness: return "#64D2FF"
        case .microphone: return "#FF9F0A"
        }
    }
}

/// How the volume, brightness and other HUDs look.
public enum HUDStyle: String, Codable, Sendable, CaseIterable {
    /// In the wings beside the notch, inside the menu bar row.
    case compact
    /// Below the notch, with the level as a percentage. The row beside the notch stays clear.
    case detailed
}

/// Per-app customisation, keyed by bundle identifier.
public struct AppRule: Codable, Equatable, Sendable, Identifiable {
    public var bundleID: String
    /// Tint for activities and notifications from this app.
    public var tint: String?
    /// Icon override for this app's activities.
    public var icon: ActivityIcon?
    /// Hide the island while this app is frontmost.
    public var hideIsland: Bool?
    /// Keep the island visible when this app is fullscreen.
    public var showInFullscreen: Bool?
    /// Ignore this app's mirrored notifications.
    public var muteNotifications: Bool?
    /// Priority for this app's mirrored notifications.
    public var priority: ActivityPriority?

    public var id: String { bundleID }

    public init(bundleID: String, tint: String? = nil, icon: ActivityIcon? = nil, hideIsland: Bool? = nil,
                showInFullscreen: Bool? = nil, muteNotifications: Bool? = nil, priority: ActivityPriority? = nil) {
        self.bundleID = bundleID; self.tint = tint; self.icon = icon; self.hideIsland = hideIsland
        self.showInFullscreen = showInFullscreen; self.muteNotifications = muteNotifications; self.priority = priority
    }
}

extension AppRule {
    /// Rules with the given bundle ids switched on for fullscreen and for hiding the island.
    /// An id that already has a rule gets the flag on that rule; others get a new rule, once.
    public static func merging(_ rules: [AppRule], showInFullscreen: [String], hideIsland: [String]) -> [AppRule] {
        var rules = rules
        func update(_ bundleID: String, _ change: (inout AppRule) -> Void) {
            let id = bundleID.trimmingCharacters(in: .whitespaces)
            guard !id.isEmpty else { return }
            if let i = rules.firstIndex(where: { $0.bundleID == id }) {
                change(&rules[i])
            } else {
                var rule = AppRule(bundleID: id)
                change(&rule)
                rules.append(rule)
            }
        }
        for id in showInFullscreen { update(id) { $0.showInFullscreen = true } }
        for id in hideIsland { update(id) { $0.hideIsland = true } }
        return rules
    }
}

/// User settings, persisted as human-editable JSON at `~/.config/islet/config.json`
/// so they can live in a dotfiles repo. Loading is lenient: unknown keys are ignored and
/// a missing or malformed value falls back to its default without affecting the others.
public struct IsletSettings: Codable, Equatable, Sendable {
    // Placement & behaviour
    public var displayMode: DisplayMode = .notchedScreen
    /// How the island looks on displays without a notch. Replaces `showOnNonNotchDisplays`
    /// (false became `hidden`).
    public var notchlessStyle: NotchlessStyle = .pill
    public var hoverToOpen = true
    /// While the island opens on click, resting the pointer on the notch shows what's playing
    /// for as long as it stays there (a song peek without opening).
    public var peekOnHover = true
    public var openDelay: Double = 0.18
    public var closeDelay: Double = 0.35
    /// What the island does over an app in full screen. Replaces `hideInFullscreen` (false
    /// became `show`). An app's rule can keep the island in full screen whatever this says.
    public var fullscreenBehaviour: FullscreenBehaviour = .hide
    /// Exclude the island from screenshots and screen sharing.
    public var hideFromScreenCapture = false

    // Size
    public var sizePreset: SizePreset = .compact
    /// Wings fitted to the free space in the menu bar, or always the full wing width. The closed
    /// island always sits beside the notch. The old `drop` value (a pill below the notch) is
    /// gone: it no longer decodes, so it loads as `auto` and isn't written back.
    public var closedLayout: ClosedLayoutPreference = .auto
    /// Used when `sizePreset` is `custom`.
    public var expandedWidth: Double = 468
    public var expandedHeight: Double = 150
    public var wingWidth: Double = 52
    /// Points added to the notch's width and height (negative to take away), so the closed
    /// island lines up with the hardware notch. Hit-testing and hover follow.
    public var notchWidthAdjust: Double = 0
    public var notchHeightAdjust: Double = 0

    // Look & feel
    public var theme: IslandTheme = .glass
    /// How much of the open island is glass in the Glass theme: 0 keeps it mostly black and
    /// melts only near the bottom, 1 turns to glass right below the menu bar row.
    public var glassLevel: Double = 0.6
    /// A faint edge round the island so it shows on a dark wallpaper. Always on with the
    /// system's Increase Contrast.
    public var outline = false
    /// With the Glass theme, the closed island on a display without a notch is glass too. On a
    /// notch it stays black, so it matches the hardware.
    public var glassOnNotchless = false
    public var animationStyle: AnimationStyle = .fluid
    /// Scales the one spring family (and the other styles' fades). The music indicator's loops
    /// keep their own pace.
    public var animationSpeed: AnimationSpeed = .normal
    /// Hex or named color, or "auto" to follow album art / activity tints.
    public var accentColor = "auto"
    public var roundedFont = true
    /// Pulse a soft glow around the island while something needs you (agent waiting, critical alert).
    public var urgentGlow = true
    /// Little "bounce" when a new live activity arrives.
    public var bounceOnActivity = true
    /// Replace spring animations with quick fades (also follows the system Reduce Motion setting).
    public var reduceMotion = false
    public var hapticsMode: HapticsMode = .direct
    /// How many activities can show at once in the closed island (1 = no bubbles).
    public var maxConcurrent = 3
    public var bubblePlacement: BubblePlacement = .right
    /// Seconds a new activity stays expanded before collapsing.
    public var alertDuration: Double = 2.5
    /// Seconds the volume/brightness HUD stays up.
    public var hudDuration: Double = 1.6
    /// "Welcome back" when the screen unlocks.
    public var unlockSplash = true

    // Modules
    public var mediaEnabled = true
    /// Seconds the closed island keeps paused music before it hides: 0 hides it right away and
    /// `neverHide` (-1) keeps it. Replaces `showPausedMedia` (true became `neverHide`).
    public var pausedMusicTimeout: Double = IsletSettings.standardPausedMusicTimeout
    /// Show a new song for a moment below the notch when the track changes (`SongPeek`).
    public var songChangePeek = true
    public var visualiserStyle: VisualiserStyle = .bars
    /// The music's colour (`MusicColour`). Read from `visualiserColour` in older configs.
    public var musicColour: MusicColour = .artwork
    /// A thin ring round the artwork beside the notch that fills as the song plays.
    public var songProgressRing = false
    /// Corner radius of the artwork beside the notch, in points: 0 is square and 10 is round.
    /// The song peek and the open island's artwork scale it to their size (`artworkCorner`).
    public var artworkCornerRadius: Double = IsletSettings.standardArtworkCorner
    public var disabledMediaSources: [MediaSourceKind] = []
    public var hudEnabled = true
    public var brightnessHUDEnabled = true
    public var keyboardHUDEnabled = true
    /// Mute and unmute from an app or script (the API's `microphone` HUD).
    public var microphoneHUDEnabled = true
    public var hudStyle: HUDStyle = .compact
    public var hudColour: HUDColour = .white
    /// Swallow the volume/brightness keys so only Islet's HUD shows. Needs Accessibility.
    public var replaceSystemHUD = false
    public var batteryEnabled = true
    public var calendarEnabled = true
    /// Reminders due today, with an alert at their due time. Asks for Reminders access.
    public var remindersEnabled = false
    /// Calendar identifiers the user hid.
    public var hiddenCalendars: [String] = []
    public var shelfEnabled = true
    /// Off by default: clipboard history is sensitive.
    public var clipboardEnabled = false
    public var clipboardLimit = 30
    public var privacyIndicatorsEnabled = true
    public var systemStatsEnabled = true
    /// Live call timer when a call app is using the microphone.
    public var callDetection = true
    /// Download progress from ~/Downloads (macOS asks for folder access once).
    public var downloadsEnabled = false
    /// Pick icons and colors for activities that don't set one.
    public var smartIcons = true
    /// Use on-device Apple Intelligence (when available) for icons and one-line summaries.
    public var aiAssist = true
    /// Sound when a timer ends: a system sound name ("Glass", "Ping", …) or "none".
    public var timerSound = "Glass"
    /// Pomodoro lengths in minutes and how often the long break comes.
    public var pomodoro = PomodoroSchedule()

    // Now Playing controls, gestures and battery alerts
    /// Show the time left (rather than the track length) right of the scrubber. Tap the label to switch.
    public var mediaShowsRemainingTime = true
    /// Two-finger swipes on the island (no permissions needed).
    public var gesturesEnabled = true
    public var swipeDownToOpen = true
    public var swipeUpToClose = true
    /// Swipe sideways over playing media to change track (or seek, see `swipeMediaAction`).
    public var swipeMedia = true
    public var swipeMediaAction: MediaSwipeAction = .track
    /// Swipe sideways over a closed activity to bring the next one forward.
    public var swipeCyclesActivities = true
    /// Warn on battery at this level (percent).
    public var batteryLowThreshold = 20
    /// Warn again, more urgently, at this level.
    public var batteryCriticalThreshold = 10
    /// Tell me when charging reaches this level (0 = off), e.g. 80 to match a charge limit.
    public var batteryChargedAlert = 0
    /// The Ask box: default provider, models, effort, follow-ups. API keys live in the Keychain.
    public var ask = AskSettings()

    // Integrations
    public var apiEnabled = true
    public var apiPort = 47831
    /// Also listen on the local network (token required) so iPhone Shortcuts can push events.
    public var lanBridgeEnabled = false
    public var lanPort = 47832
    /// Run scripts from the plugins folder. Off until the user turns it on: they run with
    /// Islet's permissions.
    public var pluginsEnabled = false
    /// Show coding-agent permission requests, questions and plans as cards to answer in the notch.
    public var approvalsEnabled = true
    /// Seconds a card waits for an answer before the agent asks in the terminal instead.
    public var approvalWait: Double = 300
    /// Folder of script widgets; default `~/.config/islet/plugins`.
    public var pluginDirectory: String?
    /// Activity sources the user silenced (e.g. "github-actions").
    public var mutedSources: [String] = []
    /// Mirror every app's notification banners into the island. Needs Accessibility.
    public var notificationMirroring = false
    /// Show the Live Activities macOS puts in the menu bar (from your iPhone) in the island.
    /// Needs Accessibility.
    public var mirrorMenuBarActivities = true
    /// Mirror only the activities the notch hides (collapsed into the menu bar's overflow).
    public var mirrorOnlyHiddenActivities = false
    /// Include mirrored Live Activities, which often hold addresses, names and scores, in API responses.
    public var shareMirroredActivities = false
    /// Claude Code plan limits, from the status line (`isletctl statusline`). Local files only.
    public var claudeUsageEnabled = true
    /// Home offers to show Claude's usage while Claude Code is installed without Islet's status
    /// line (`ClaudeUsageHint`). Its "x" turns this off.
    public var claudeUsageHint = true
    /// Codex plan limits, from its session logs in `~/.codex/sessions`. Local files only.
    public var codexUsageEnabled = true
    /// Per-app tint, icon, visibility and notification handling. Replaces the old
    /// `fullscreenAllowList` and `hideForApps` lists, which are read once and folded in here.
    public var appRules: [AppRule] = []

    /// Global shortcut that opens or closes the island ("" to disable).
    public var hotkey = "ctrl+option+i"
    /// Global shortcut that opens the Ask box ready to type ("" to disable).
    public var askHotkey = "ctrl+option+a"

    public init() {}

    // Allowed ranges, shared by `sanitized()` and the Settings sliders.
    public static let openDelayRange: ClosedRange<Double> = 0...1
    public static let closeDelayRange: ClosedRange<Double> = 0...2
    public static let expandedWidthRange: ClosedRange<Double> = 420...900
    public static let expandedHeightRange: ClosedRange<Double> = 130...360
    public static let wingWidthRange: ClosedRange<Double> = 40...140
    public static let alertDurationRange: ClosedRange<Double> = 1...6
    public static let hudDurationRange: ClosedRange<Double> = 0.8...4
    public static let glassLevelRange: ClosedRange<Double> = 0...1
    public static let artworkCornerRange: ClosedRange<Double> = 0...10
    /// The default `artworkCornerRadius`, which keeps every artwork at its designed corner.
    public static let standardArtworkCorner: Double = 5
    public static let notchWidthAdjustRange: ClosedRange<Double> = -20...20
    public static let notchHeightAdjustRange: ClosedRange<Double> = -4...4
    /// The default `pausedMusicTimeout`, the 10 seconds NotchNook shows.
    public static let standardPausedMusicTimeout: Double = 10
    /// `pausedMusicTimeout` for "never hide".
    public static let neverHide: Double = -1
    /// The longest `pausedMusicTimeout` short of never.
    public static let pausedMusicTimeoutRange: ClosedRange<Double> = 0...300
    /// The choices Settings offers for `pausedMusicTimeout`, in order.
    public static let pausedMusicChoices: [Double] = [0, 5, 10, 30, 60, 300, neverHide]
    public static let clipboardLimitRange: ClosedRange<Int> = 1...500
    /// Ports for the local API and the LAN bridge (unprivileged, and never the same one).
    public static let portRange: ClosedRange<Int> = 1024...65535

    /// Effective expanded size and wing width after applying the size preset.
    public var expandedSize: (width: Double, height: Double) {
        if let d = sizePreset.dimensions { return (d.width, d.height) }
        return (expandedWidth, expandedHeight)
    }

    public var effectiveWingWidth: Double { sizePreset.dimensions?.wing ?? wingWidth }

    /// What `notchWidthAdjust` and `notchHeightAdjust` add to the notch.
    public var notchAdjust: CGSize { CGSize(width: notchWidthAdjust, height: notchHeightAdjust) }

    /// Whether paused music stays in the closed island for good.
    public var keepsPausedMusic: Bool { pausedMusicTimeout < 0 }

    /// The corner for artwork `size` points wide whose corner is `standard` at the default
    /// setting: square at 0, `standard` at the default 5, round at 10. The closed island's
    /// 20 pt artwork has a standard of 5, so there the corner is the setting itself.
    public func artworkCorner(size: Double, standard: Double) -> Double {
        let v = Self.clamp(artworkCornerRadius, Self.artworkCornerRange)
        let mid = Self.standardArtworkCorner
        let round = max(standard, size / 2)
        if v <= mid { return standard * v / mid }
        return standard + (round - standard) * (v - mid) / (Self.artworkCornerRange.upperBound - mid)
    }

    /// Whether a HUD of `kind` shows (Settings → Notifications & HUDs). The keys still do
    /// their job when it doesn't.
    public func showsHUD(_ kind: HUDKind) -> Bool {
        switch kind {
        case .volume: return hudEnabled
        case .brightness: return brightnessHUDEnabled
        case .keyboardBrightness: return keyboardHUDEnabled
        case .microphone: return microphoneHUDEnabled
        }
    }

    /// Whether any HUD shows at all.
    public var showsAnyHUD: Bool { HUDKind.allCases.contains(where: showsHUD) }

    /// What full screen asks of the island on a display: nothing (`show`) unless an app is in
    /// full screen there and the front app's rule doesn't keep the island.
    public func fullscreenEffect(isFullscreen: Bool, frontApp: String?) -> FullscreenBehaviour {
        guard isFullscreen, rule(for: frontApp)?.showInFullscreen != true else { return .show }
        return fullscreenBehaviour
    }

    public func rule(for bundleID: String?) -> AppRule? {
        guard let bundleID else { return nil }
        return appRules.first { $0.bundleID == bundleID }
    }

    private static func clamp<T: Comparable>(_ value: T, _ range: ClosedRange<T>) -> T {
        min(range.upperBound, max(range.lowerBound, value))
    }

    /// Clamp values into safe ranges.
    public func sanitized() -> IsletSettings {
        var s = self
        s.expandedWidth = Self.clamp(s.expandedWidth, Self.expandedWidthRange)
        s.expandedHeight = Self.clamp(s.expandedHeight, Self.expandedHeightRange)
        s.openDelay = Self.clamp(s.openDelay, Self.openDelayRange)
        s.closeDelay = Self.clamp(s.closeDelay, Self.closeDelayRange)
        s.clipboardLimit = Self.clamp(s.clipboardLimit, Self.clipboardLimitRange)
        s.wingWidth = Self.clamp(s.wingWidth, Self.wingWidthRange)
        s.maxConcurrent = min(3, max(1, s.maxConcurrent))
        s.alertDuration = Self.clamp(s.alertDuration, Self.alertDurationRange)
        s.hudDuration = Self.clamp(s.hudDuration, Self.hudDurationRange)
        s.glassLevel = Self.clamp(s.glassLevel, Self.glassLevelRange)
        s.artworkCornerRadius = Self.clamp(s.artworkCornerRadius, Self.artworkCornerRange)
        // Whole points and whole seconds, as Settings offers them: a hand-edited 2.7 would leave
        // the island's edges between pixels, and 7.5 seconds would show as "8 seconds".
        s.notchWidthAdjust = Self.clamp(s.notchWidthAdjust.rounded(), Self.notchWidthAdjustRange)
        s.notchHeightAdjust = Self.clamp(s.notchHeightAdjust.rounded(), Self.notchHeightAdjustRange)
        s.pausedMusicTimeout = s.pausedMusicTimeout < 0 ? Self.neverHide
            : Self.clamp(s.pausedMusicTimeout.rounded(), Self.pausedMusicTimeoutRange)
        s.batteryLowThreshold = min(50, max(5, s.batteryLowThreshold))
        s.batteryCriticalThreshold = min(s.batteryLowThreshold - 1, max(1, s.batteryCriticalThreshold))
        if s.batteryChargedAlert != 0 { s.batteryChargedAlert = min(100, max(50, s.batteryChargedAlert)) }
        s.approvalWait = min(3600, max(30, s.approvalWait))
        let d = IsletSettings()
        if !Self.portRange.contains(s.apiPort) { s.apiPort = d.apiPort }
        if !Self.portRange.contains(s.lanPort) || s.lanPort == s.apiPort {
            s.lanPort = s.apiPort == d.lanPort ? d.apiPort : d.lanPort
        }
        if s.accentColor != "auto", RGBA.parse(s.accentColor) == nil { s.accentColor = "auto" }
        // An app colour that isn't a colour name or a hex value means "its own colour".
        for i in s.appRules.indices where s.appRules[i].tint.map({ RGBA.parse($0) == nil }) ?? false {
            s.appRules[i].tint = nil
        }
        return s
    }

    /// Decode leniently: start from defaults and apply each user key only if it decodes.
    public static func decodeLenient(_ data: Data) -> IsletSettings {
        let encoder = JSONEncoder()
        guard let defaultsData = try? encoder.encode(IsletSettings()),
              var merged = (try? JSONSerialization.jsonObject(with: defaultsData)) as? [String: Any],
              let user = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            return IsletSettings()
        }
        let known = Set(Mirror(reflecting: IsletSettings()).children.compactMap(\.label))
        let decoder = JSONDecoder()
        // The user's keys that were read; the rest fell back to their defaults.
        var applied: Set<String> = []
        for key in user.keys.sorted() where known.contains(key) {
            var trial = merged
            trial[key] = user[key]
            if let d = try? JSONSerialization.data(withJSONObject: trial),
               (try? decoder.decode(IsletSettings.self, from: d)) != nil {
                merged = trial
                applied.insert(key)
            }
        }
        guard let d = try? JSONSerialization.data(withJSONObject: merged),
              var s = try? decoder.decode(IsletSettings.self, from: d) else { return IsletSettings() }
        // Older configs switched haptics off with `hapticFeedback: false`, whatever `hapticsMode` said
        // (the app wrote both keys). `hapticsMode` replaced it, and the old key isn't written back.
        if user["hapticFeedback"] as? Bool == false { s.hapticsMode = .off }
        // `showPausedMedia: true` kept paused music for good; `pausedMusicTimeout` replaced it.
        // false (or no key) now means the new default, and the old key isn't written back. A
        // `pausedMusicTimeout` that can't be read doesn't count, so the old choice still carries.
        if !applied.contains("pausedMusicTimeout"), user["showPausedMedia"] as? Bool == true { s.pausedMusicTimeout = Self.neverHide }
        // `hideInFullscreen` and `showOnNonNotchDisplays` were switches; their choices replaced
        // them. Only an explicit false changes anything, and the old keys aren't written back.
        if !applied.contains("fullscreenBehaviour"), user["hideInFullscreen"] as? Bool == false { s.fullscreenBehaviour = .show }
        if !applied.contains("notchlessStyle"), user["showOnNonNotchDisplays"] as? Bool == false { s.notchlessStyle = .hidden }
        // `visualiserColour` coloured the playing indicator alone; `musicColour` colours all the
        // music and takes its value. The old key isn't written back.
        if !applied.contains("musicColour"), let old = user["visualiserColour"] as? String, let colour = MusicColour(rawValue: old) {
            s.musicColour = colour
        }
        // Older configs kept two bundle id lists beside `appRules`. They are folded into the
        // rules and not written back. (`launchAtLogin` is gone too: Login Items is the truth.)
        s.appRules = AppRule.merging(s.appRules,
                                     showInFullscreen: user["fullscreenAllowList"] as? [String] ?? [],
                                     hideIsland: user["hideForApps"] as? [String] ?? [])
        return s.sanitized()
    }

    /// Why a port can't be used, or nil if it can: in `portRange` and not the other server's.
    public static func portProblem(_ port: Int?, other: Int) -> String? {
        guard let port, portRange.contains(port) else {
            return "Use a number from \(portRange.lowerBound) to \(portRange.upperBound)."
        }
        return port == other ? "The local API and the iPhone bridge need different ports." : nil
    }

    public static func load(from url: URL) -> IsletSettings {
        guard let data = try? Data(contentsOf: url) else { return IsletSettings() }
        return decodeLenient(data)
    }

    public func save(to url: URL) throws {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try e.encode(self).write(to: url, options: .atomic)
    }
}

/// Well-known file locations.
public enum IsletPaths {
    public static var home: URL { FileManager.default.homeDirectoryForCurrentUser }

    /// `$XDG_CONFIG_HOME/islet` or `~/.config/islet`.
    public static var configDirectory: URL {
        if let xdg = ProcessInfo.processInfo.environment["XDG_CONFIG_HOME"], !xdg.isEmpty {
            return URL(fileURLWithPath: xdg).appendingPathComponent("islet")
        }
        return home.appendingPathComponent(".config/islet")
    }

    public static var configFile: URL { configDirectory.appendingPathComponent("config.json") }
    public static var pluginsDirectory: URL { configDirectory.appendingPathComponent("plugins") }

    /// App state (API discovery file, shelf). `ISLET_SUPPORT_DIR` overrides it for tests.
    public static var supportDirectory: URL {
        if let dir = ProcessInfo.processInfo.environment["ISLET_SUPPORT_DIR"], !dir.isEmpty {
            return URL(fileURLWithPath: dir)
        }
        return home.appendingPathComponent("Library/Application Support/Islet")
    }

    /// Discovery file written by the app: `{"port": 47831, "token": "…"}` (mode 0600).
    public static var apiDiscoveryFile: URL { supportDirectory.appendingPathComponent("api.json") }
}

/// Contents of the API discovery file shared between the app and `isletctl`.
public struct APIDiscovery: Codable, Equatable, Sendable {
    public var port: Int
    public var token: String
    public var pid: Int32?

    public init(port: Int, token: String, pid: Int32? = nil) {
        self.port = port
        self.token = token
        self.pid = pid
    }

    public static func generateToken() -> String {
        var bytes = [UInt8](repeating: 0, count: 24)
        for i in bytes.indices { bytes[i] = UInt8.random(in: 0...255) }
        return bytes.map { String(format: "%02x", $0) }.joined()
    }
}
