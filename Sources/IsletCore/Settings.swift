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
    /// Frosted glass when expanded (the closed island stays black over the notch).
    case glass
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

/// User settings, persisted as human-editable JSON at `~/.config/islet/config.json`
/// so they can live in a dotfiles repo. Loading is lenient: unknown keys are ignored and
/// a missing or malformed value falls back to its default without affecting the others.
public struct IsletSettings: Codable, Equatable, Sendable {
    // Placement & behaviour
    public var displayMode: DisplayMode = .notchedScreen
    public var showOnNonNotchDisplays = true
    public var hoverToOpen = true
    public var openDelay: Double = 0.18
    public var closeDelay: Double = 0.35
    public var hideInFullscreen = true
    /// Bundle ids that keep the island visible even in fullscreen (e.g. a video call app).
    public var fullscreenAllowList: [String] = []
    /// Bundle ids in front of which the island always hides (games, presentation apps).
    public var hideForApps: [String] = []
    /// Exclude the island from screenshots and screen sharing.
    public var hideFromScreenCapture = false

    // Size
    public var sizePreset: SizePreset = .compact
    /// Beside the notch, below it, or chosen automatically so menu bar icons stay uncovered.
    public var closedLayout: ClosedLayoutPreference = .auto
    /// Used when `sizePreset` is `custom`.
    public var expandedWidth: Double = 468
    public var expandedHeight: Double = 150
    public var wingWidth: Double = 52

    // Look & feel
    public var theme: IslandTheme = .black
    public var animationStyle: AnimationStyle = .fluid
    /// Hex or named color, or "auto" to follow album art / activity tints.
    public var accentColor = "auto"
    public var roundedFont = true
    /// Pulse a soft glow around the island while something needs you (agent waiting, critical alert).
    public var urgentGlow = true
    /// Little "bounce" when a new live activity arrives.
    public var bounceOnActivity = true
    /// Replace spring animations with quick fades (also follows the system Reduce Motion setting).
    public var reduceMotion = false
    public var hapticFeedback = true
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
    public var showPausedMedia = false
    public var disabledMediaSources: [MediaSourceKind] = []
    public var hudEnabled = true
    public var brightnessHUDEnabled = true
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

    // Integrations
    public var apiEnabled = true
    public var apiPort = 47831
    /// Also listen on the local network (token required) so iPhone Shortcuts can push events.
    public var lanBridgeEnabled = false
    public var lanPort = 47832
    public var pluginsEnabled = true
    /// Folder of script widgets; default `~/.config/islet/plugins`.
    public var pluginDirectory: String?
    /// Activity sources the user silenced (e.g. "github-actions").
    public var mutedSources: [String] = []
    /// Mirror every app's notification banners into the island. Needs Accessibility.
    public var notificationMirroring = false
    /// Show the Live Activities macOS puts in the menu bar (from your iPhone) in the island.
    /// Needs Accessibility.
    public var mirrorMenuBarActivities = true
    /// Claude Code plan limits, from the status line (`isletctl statusline`). Local files only.
    public var claudeUsageEnabled = true
    /// Codex plan limits, from its session logs in `~/.codex/sessions`. Local files only.
    public var codexUsageEnabled = true
    public var appRules: [AppRule] = []

    public var launchAtLogin = false
    /// Global shortcut that opens or closes the island ("" to disable).
    public var hotkey = "ctrl+option+i"

    public init() {}

    /// Effective expanded size and wing width after applying the size preset.
    public var expandedSize: (width: Double, height: Double) {
        if let d = sizePreset.dimensions { return (d.width, d.height) }
        return (expandedWidth, expandedHeight)
    }

    public var effectiveWingWidth: Double { sizePreset.dimensions?.wing ?? wingWidth }

    public func rule(for bundleID: String?) -> AppRule? {
        guard let bundleID else { return nil }
        return appRules.first { $0.bundleID == bundleID }
    }

    /// Clamp values into safe ranges.
    public func sanitized() -> IsletSettings {
        var s = self
        s.expandedWidth = min(1200, max(360, s.expandedWidth))
        s.expandedHeight = min(600, max(120, s.expandedHeight))
        s.openDelay = min(2, max(0, s.openDelay))
        s.closeDelay = min(5, max(0, s.closeDelay))
        s.clipboardLimit = min(500, max(1, s.clipboardLimit))
        s.wingWidth = min(200, max(40, s.wingWidth))
        s.maxConcurrent = min(3, max(1, s.maxConcurrent))
        s.alertDuration = min(10, max(0.5, s.alertDuration))
        s.hudDuration = min(5, max(0.5, s.hudDuration))
        let d = IsletSettings()
        if !(1024...65535).contains(s.apiPort) { s.apiPort = d.apiPort }
        if !(1024...65535).contains(s.lanPort) || s.lanPort == s.apiPort { s.lanPort = d.lanPort }
        if s.accentColor != "auto", RGBA.parse(s.accentColor) == nil { s.accentColor = "auto" }
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
        for key in user.keys.sorted() where known.contains(key) {
            var trial = merged
            trial[key] = user[key]
            if let d = try? JSONSerialization.data(withJSONObject: trial),
               (try? decoder.decode(IsletSettings.self, from: d)) != nil {
                merged = trial
            }
        }
        guard let d = try? JSONSerialization.data(withJSONObject: merged),
              let s = try? decoder.decode(IsletSettings.self, from: d) else { return IsletSettings() }
        return s.sanitized()
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
