import Foundation

/// A page in the Settings window, in sidebar order.
public enum SettingsPage: String, CaseIterable, Sendable, Identifiable {
    case general, appearance, shortcuts
    case nowPlaying, liveActivities, calendar, timers, notifications, shelf, downloads, ai, agents, tools
    case apps, permissions, about
    case advanced

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .general: return "General"
        case .appearance: return "Appearance"
        case .shortcuts: return "Shortcuts"
        case .nowPlaying: return "Now Playing"
        case .liveActivities: return "Live Activities"
        case .calendar: return "Calendar & Reminders"
        case .timers: return "Timers"
        case .notifications: return "Notifications & HUDs"
        case .shelf: return "Shelf & Clipboard"
        case .downloads: return "Downloads"
        case .ai: return "Ask & AI"
        case .agents: return "Coding agents"
        case .tools: return "Tools"
        case .apps: return "Apps"
        case .permissions: return "Permissions"
        case .about: return "About"
        case .advanced: return "Advanced"
        }
    }

    /// One plain line under the page title.
    public var summary: String {
        switch self {
        case .general: return "Where the island shows, and how it opens and closes."
        case .appearance: return "How the island looks and moves."
        case .shortcuts: return "Keys that work from any app."
        case .nowPlaying: return "What's playing in Music, Spotify, your browser and other apps, with controls."
        case .liveActivities: return "Rides, deliveries, scores and flights from your iPhone, in the island."
        case .calendar: return "Your next event with a Join button, and today's reminders."
        case .timers: return "Timers and Pomodoro rounds that ring in the island."
        case .notifications: return "Notifications, volume, brightness, battery, calls, camera and microphone."
        case .shelf: return "Keep files handy, share them, and find what you copied."
        case .downloads: return "Browser downloads with their progress, then Open and Show when they finish."
        case .ai: return "Ask a question from anywhere, answered on this Mac or by Claude or ChatGPT."
        case .agents: return "See what your coding agents are doing and answer their questions in the notch."
        case .tools: return "A camera mirror, a teleprompter, stocks and today's sales, each a page under More. All start off."
        case .apps: return "Give an app a colour or a priority, hide the island for it, or mute its notifications."
        case .permissions: return "What Islet may use, and what uses it. None is needed to run."
        case .about: return "Version and licence."
        case .advanced: return "For scripts, other apps and troubleshooting. Nothing here is needed for everyday use."
        }
    }

    /// SF Symbol for the sidebar tile.
    public var symbol: String {
        switch self {
        case .general: return "gearshape.fill"
        case .appearance: return "paintbrush.fill"
        case .shortcuts: return "command"
        case .nowPlaying: return "play.fill"
        case .liveActivities: return "iphone.gen3"
        case .calendar: return "calendar"
        case .timers: return "timer"
        case .notifications: return "bell.badge.fill"
        case .shelf: return "tray.full.fill"
        case .downloads: return "arrow.down"
        case .ai: return "sparkles"
        case .agents: return "chevron.left.forwardslash.chevron.right"
        case .tools: return "rectangle.3.group.fill"
        case .apps: return "square.grid.2x2.fill"
        case .permissions: return "hand.raised.fill"
        case .about: return "info"
        case .advanced: return "wrench.and.screwdriver.fill"
        }
    }

    /// Tile colour, as a name the app maps to a system colour.
    public var tint: String {
        switch self {
        case .general, .about: return "grey"
        case .appearance, .permissions: return "blue"
        case .shortcuts: return "indigo"
        case .nowPlaying: return "pink"
        case .liveActivities: return "green"
        case .calendar, .notifications: return "red"
        case .timers: return "orange"
        case .shelf: return "cyan"
        case .downloads: return "teal"
        case .ai: return "purple"
        case .agents: return "brown"
        case .tools: return "yellow"
        case .apps: return "mint"
        case .advanced: return "graphite"
        }
    }

    public var group: SettingsPageGroup {
        switch self {
        case .general, .appearance, .shortcuts: return .basics
        case .nowPlaying, .liveActivities, .calendar, .timers, .notifications, .shelf, .downloads, .ai, .agents, .tools: return .features
        case .apps, .permissions, .about: return .system
        case .advanced: return .advanced
        }
    }
}

/// Sidebar groups. Only Features has a heading; the others are set apart by space alone.
public enum SettingsPageGroup: String, CaseIterable, Sendable, Identifiable {
    case basics, features, system, advanced

    public var id: String { rawValue }

    public var title: String? { self == .features ? "Features" : nil }

    public var pages: [SettingsPage] { SettingsPage.allCases.filter { $0.group == self } }
}

/// One searchable row in Settings.
public struct SettingsEntry: Sendable, Hashable, Identifiable {
    public var id: String
    public var page: SettingsPage
    public var title: String
    /// The section heading the row sits under, if any.
    public var section: String?
    /// Other words people might search for.
    public var keywords: [String]
    /// The row to scroll to: its own id, or a nearby row that is always shown (for rows inside
    /// a disclosure group or shown only for some choices).
    public var anchor: String

    public init(_ id: String, _ page: SettingsPage, _ title: String, section: String? = nil, keywords: [String] = [],
                anchor: String? = nil) {
        self.id = id
        self.page = page
        self.title = title
        self.section = section
        self.keywords = keywords
        self.anchor = anchor ?? id
    }
}

/// The matches on one page.
public struct SettingsSearchGroup: Sendable, Equatable, Identifiable {
    public var page: SettingsPage
    public var entries: [SettingsEntry]
    public var id: String { page.id }
}

/// Every searchable setting, and the search over them. Kept beside the pages by hand: a new
/// control needs an entry here, and its row takes the entry's anchor as its `settingsAnchor`.
public enum SettingsIndex {
    public static let entries: [SettingsEntry] = general + appearance + shortcuts + features + system + advanced

    /// Entries matching every word of `query`, grouped by page. A word matches the start of a
    /// word in the entry's title, section, page or keywords; from three letters it also matches
    /// inside a word ("board" finds "Clipboard"). Matches in the row's or the page's title rank
    /// above matches elsewhere, and whole words above parts of words. Pages are ordered by
    /// their best match, then by sidebar order; rows by score, then by their order on the page.
    public static func search(_ query: String, in entries: [SettingsEntry] = entries) -> [SettingsSearchGroup] {
        let words = tokens(query)
        guard !words.isEmpty else { return [] }
        let phrase = words.joined(separator: " ")
        var hits: [SettingsPage: [(entry: SettingsEntry, score: Int)]] = [:]
        for entry in entries {
            guard let score = score(entry, words: words, phrase: phrase) else { continue }
            hits[entry.page, default: []].append((entry, score))
        }
        let groups = SettingsPage.allCases.compactMap { page -> (group: SettingsSearchGroup, best: Int)? in
            guard let list = hits[page] else { return nil }
            let ordered = list.enumerated().sorted { a, b in
                a.element.score != b.element.score ? a.element.score > b.element.score : a.offset < b.offset
            }
            return (SettingsSearchGroup(page: page, entries: ordered.map(\.element.entry)), list.map(\.score).max() ?? 0)
        }
        return groups.enumerated().sorted { a, b in
            a.element.best != b.element.best ? a.element.best > b.element.best : a.offset < b.offset
        }.map(\.element.group)
    }

    /// nil when a word matches nothing in the entry.
    static func score(_ entry: SettingsEntry, words: [String], phrase: String) -> Int? {
        let title = tokens(entry.title)
        let page = tokens(entry.page.title)
        let other = tokens(entry.section ?? "") + entry.keywords.flatMap(tokens)
        var total = 0
        for word in words {
            let inTitle = max(quality(word, title), quality(word, page))
            let elsewhere = quality(word, other)
            guard inTitle > 0 || elsewhere > 0 else { return nil }
            total += inTitle > 0 ? 10 + inTitle : elsewhere
        }
        if title.joined(separator: " ").hasPrefix(phrase) || page.joined(separator: " ").hasPrefix(phrase) { total += 5 }
        return total
    }

    /// 3 for a whole word, 2 for the start of a word, 1 for inside a word, 0 for no match.
    static func quality(_ word: String, _ words: [String]) -> Int {
        var best = 0
        for w in words {
            if w == word { return 3 }
            if w.hasPrefix(word) { best = max(best, 2) } else if word.count >= 3, w.contains(word) { best = max(best, 1) }
        }
        return best
    }

    static func matches(_ word: String, _ words: [String]) -> Bool { quality(word, words) > 0 }

    static func normalized(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_GB"))
            .replacingOccurrences(of: "&", with: " and ")
    }

    static func tokens(_ text: String) -> [String] {
        normalized(text).split { !$0.isLetter && !$0.isNumber }.map(String.init)
    }

    // MARK: Entries

    private static let general: [SettingsEntry] = [
        SettingsEntry("general.login", .general, "Launch at login", section: "Behaviour", keywords: ["startup", "login items", "start automatically"]),
        SettingsEntry("general.open", .general, "Open the island", section: "Behaviour", keywords: ["hover", "click"]),
        SettingsEntry("general.hoverDelay", .general, "Hover delay", section: "Behaviour", keywords: ["open delay", "wait"], anchor: "general.open"),
        SettingsEntry("general.peekOnHover", .general, "Peek at what's playing", section: "Behaviour",
                      keywords: ["hover", "quick peek", "song", "music", "point", "click"], anchor: "general.open"),
        SettingsEntry("general.closeDelay", .general, "Close delay", section: "Behaviour", keywords: ["collapse", "dismiss", "wait"]),
        SettingsEntry("general.display", .general, "Show the island on", section: "Placement", keywords: ["display", "screen", "monitor", "external", "notched"]),
        SettingsEntry("general.nonNotch", .general, "On displays without a notch", section: "Placement",
                      keywords: ["external", "monitor", "pill", "floating", "notch shape", "only on hover", "hidden", "don't show"]),
        SettingsEntry("general.fullscreen", .general, "In full screen", section: "Placement",
                      keywords: ["fullscreen", "games", "video", "hide music", "keep showing", "hide everything"]),
        SettingsEntry("general.capture", .general, "Hide from screenshots", section: "Placement",
                      keywords: ["screen recording", "screen sharing", "capture", "privacy"]),
        SettingsEntry("general.gestures", .general, "Two-finger swipes on the island", section: "Gestures", keywords: ["trackpad", "gesture", "swipe"]),
        SettingsEntry("general.swipeDown", .general, "Swipe down to open", section: "Gestures", keywords: ["gesture", "trackpad"], anchor: "general.gestures"),
        SettingsEntry("general.swipeUp", .general, "Swipe up to close", section: "Gestures", keywords: ["gesture", "trackpad"], anchor: "general.gestures"),
        SettingsEntry("general.swipeMedia", .general, "Swipe sideways over music", section: "Gestures",
                      keywords: ["next track", "previous track", "skip", "seek", "gesture"], anchor: "general.gestures"),
        SettingsEntry("general.swipeActivities", .general, "Swipe sideways to switch between activities", section: "Gestures",
                      keywords: ["cycle", "gesture"], anchor: "general.gestures"),
        SettingsEntry("general.reverseSwipes", .general, "Reverse sideways swipes", section: "Gestures",
                      keywords: ["invert", "direction", "natural", "swap", "gesture"], anchor: "general.gestures"),
        SettingsEntry("general.stats", .general, "System stats", section: "Island pages", keywords: ["CPU", "memory", "RAM", "performance"]),
    ]

    private static let appearance: [SettingsEntry] = [
        SettingsEntry("appearance.preview", .appearance, "Preview", keywords: ["sample", "try", "test", "play", "pause"]),
        SettingsEntry("appearance.theme", .appearance, "Theme", section: "Theme", keywords: ["glass", "black", "graphite", "dark", "liquid"]),
        SettingsEntry("appearance.glass", .appearance, "Glass level", section: "Theme", keywords: ["transparency", "blur", "liquid glass"],
                      anchor: "appearance.theme"),
        SettingsEntry("appearance.glassNotchless", .appearance, "Glass on displays without a notch", section: "Theme",
                      keywords: ["external", "monitor", "liquid glass", "pill", "transparent"], anchor: "appearance.theme"),
        SettingsEntry("appearance.outline", .appearance, "Subtle outline", section: "Theme",
                      keywords: ["border", "edge", "stroke", "hairline", "dark wallpaper", "increase contrast", "accessibility"]),
        SettingsEntry("appearance.accent", .appearance, "Accent colour", section: "Theme", keywords: ["color", "tint", "album art"]),
        SettingsEntry("appearance.rounded", .appearance, "Rounded text", section: "Theme", keywords: ["font", "typeface"]),
        SettingsEntry("appearance.smartIcons", .appearance, "Smart icons and colours for activities", section: "Theme", keywords: ["color", "tint"]),
        SettingsEntry("appearance.size", .appearance, "Island size", section: "Size", keywords: ["compact", "standard", "large", "custom", "bigger", "smaller"]),
        SettingsEntry("appearance.width", .appearance, "Open width", section: "Size", keywords: ["custom size", "expanded"]),
        SettingsEntry("appearance.height", .appearance, "Open height", section: "Size", keywords: ["custom size", "expanded"]),
        SettingsEntry("appearance.closed", .appearance, "Width", section: "Closed island",
                      keywords: ["closed island width", "menu bar", "fit", "full width", "wings", "layout", "beside the notch"]),
        SettingsEntry("appearance.wing", .appearance, "Wing width", section: "Closed island", keywords: ["wings", "closed size"]),
        SettingsEntry("appearance.fitNotch", .appearance, "Fit to the notch", section: "Closed island",
                      keywords: ["line up", "match", "align", "calibrate", "fine tune", "adjust", "hardware notch"]),
        SettingsEntry("appearance.fitWidth", .appearance, "Notch width", section: "Fit to the notch",
                      keywords: ["wider", "narrower", "adjust", "line up"], anchor: "appearance.fitNotch"),
        SettingsEntry("appearance.fitHeight", .appearance, "Notch height", section: "Fit to the notch",
                      keywords: ["taller", "shorter", "adjust", "line up"], anchor: "appearance.fitNotch"),
        SettingsEntry("appearance.animation", .appearance, "Animation", section: "Motion", keywords: ["fluid", "snappy", "smooth", "minimal", "spring"]),
        SettingsEntry("appearance.speed", .appearance, "Animation speed", section: "Motion",
                      keywords: ["slower", "faster", "relaxed", "quick", "spring", "pace"], anchor: "appearance.animation"),
        SettingsEntry("appearance.bounce", .appearance, "Bounce when something new arrives", section: "Motion", keywords: ["animation"]),
        SettingsEntry("appearance.glow", .appearance, "Glow while something needs you", section: "Motion", keywords: ["urgent", "attention"]),
        SettingsEntry("appearance.reduceMotion", .appearance, "Reduce motion", section: "Motion", keywords: ["accessibility", "animation"]),
        SettingsEntry("appearance.haptics", .appearance, "Trackpad haptics", section: "Motion", keywords: ["haptic", "feedback", "vibration"]),
        SettingsEntry("appearance.alertDuration", .appearance, "New activities stay open for", section: "Motion", keywords: ["duration", "seconds", "sneak peek"]),
        SettingsEntry("appearance.together", .appearance, "Activities shown together", section: "Several at once", keywords: ["bubbles", "multiple"]),
        SettingsEntry("appearance.bubbles", .appearance, "Extra activities appear", section: "Several at once", keywords: ["bubbles", "left", "right"]),
        SettingsEntry("appearance.artworkCorners", .appearance, "Artwork corners", section: "Now Playing",
                      keywords: ["album art", "cover", "rounded", "square", "round", "radius", "music"]),
        SettingsEntry("appearance.indicator", .appearance, "Playing indicator", section: "Now Playing",
                      keywords: ["music", "equaliser", "equalizer", "visualiser", "bars"]),
        SettingsEntry("appearance.reset", .appearance, "Back to the original look", section: "Reset",
                      keywords: ["reset appearance", "defaults", "restore", "start again"]),
    ]

    private static let shortcuts: [SettingsEntry] = [
        SettingsEntry("shortcuts.island", .shortcuts, "Open or close the island", keywords: ["hotkey", "keyboard", "key"]),
        SettingsEntry("shortcuts.ask", .shortcuts, "Open the Ask box", keywords: ["hotkey", "keyboard", "key", "AI"]),
    ]

    private static let features: [SettingsEntry] = [
        SettingsEntry("nowPlaying.enabled", .nowPlaying, "Now Playing", keywords: ["music", "media", "song"]),
        SettingsEntry("nowPlaying.preview", .nowPlaying, "Preview", keywords: ["play", "pause", "sample", "try"]),
        SettingsEntry("nowPlaying.status", .nowPlaying, "Try again", keywords: ["not working", "missing", "other apps", "helper"],
                      anchor: "nowPlaying.enabled"),
        SettingsEntry("nowPlaying.sources", .nowPlaying, "Sources", keywords: ["media apps", "players", "switch player", "several players"]),
        SettingsEntry("nowPlaying.music", .nowPlaying, "Music", section: "Sources", keywords: ["Apple Music"], anchor: "nowPlaying.sources"),
        SettingsEntry("nowPlaying.spotify", .nowPlaying, "Spotify", section: "Sources", anchor: "nowPlaying.sources"),
        SettingsEntry("nowPlaying.browsers", .nowPlaying, "Web browsers", section: "Sources", keywords: ["Safari", "Chrome", "YouTube"],
                      anchor: "nowPlaying.sources"),
        SettingsEntry("nowPlaying.other", .nowPlaying, "Other apps", section: "Sources", keywords: ["podcasts", "video"], anchor: "nowPlaying.sources"),
        SettingsEntry("nowPlaying.ignore", .nowPlaying, "Ignore apps", section: "Sources",
                      keywords: ["hide an app", "block", "autoplay", "games", "wrong player", "voice messages"]),
        SettingsEntry("nowPlaying.paused", .nowPlaying, "Hide paused music after", section: "Closed island",
                      keywords: ["pause", "artwork", "keep", "stay", "linger", "timeout", "seconds", "never"]),
        SettingsEntry("nowPlaying.peek", .nowPlaying, "Show the new song for a moment", section: "Closed island",
                      keywords: ["track change", "song change", "peek"]),
        SettingsEntry("nowPlaying.progressRing", .nowPlaying, "Show song progress", section: "Closed island",
                      keywords: ["ring", "elapsed", "time", "position", "progress bar"]),
        SettingsEntry("nowPlaying.remaining", .nowPlaying, "Show time left", section: "Open island", keywords: ["elapsed", "track length", "duration"]),
        SettingsEntry("nowPlaying.indicator", .nowPlaying, "Playing indicator", section: "Look",
                      keywords: ["equaliser", "equalizer", "visualiser", "bars", "dots", "wave", "waves", "pulse", "circle", "animation"]),
        SettingsEntry("nowPlaying.musicColour", .nowPlaying, "Music colour", section: "Look",
                      keywords: ["color", "artwork", "indicator colour", "progress bar", "scrubber", "tint"]),

        SettingsEntry("live.enabled", .liveActivities, "Show Live Activities",
                      keywords: ["iPhone", "rides", "deliveries", "scores", "flights", "Uber"]),
        SettingsEntry("live.hiddenOnly", .liveActivities, "Only when the notch hides them", section: "When to show them", keywords: ["menu bar", "twice"]),

        SettingsEntry("calendar.enabled", .calendar, "Calendar", keywords: ["events", "meetings", "join", "agenda"]),
        SettingsEntry("calendar.access", .calendar, "Calendar access",
                      keywords: ["permission", "privacy", "allow", "full access", "add events only", "write only", "stuck", "System Settings"]),
        SettingsEntry("calendar.shown", .calendar, "Calendars shown", keywords: ["hide calendar"], anchor: "calendar.enabled"),
        SettingsEntry("calendar.meetingLead", .calendar, "Remind me before meetings", section: "Meeting reminders",
                      keywords: ["meeting reminder", "alert", "countdown", "minutes", "join", "call", "Meet", "Teams", "Webex"]),
        SettingsEntry("calendar.keepReminding", .calendar, "Keep reminding until I join", section: "Meeting reminders",
                      keywords: ["meeting reminder", "stay", "nag", "urgent", "dismiss"]),
        SettingsEntry("calendar.needsLink", .calendar, "Only meetings with a call link", section: "Meeting reminders",
                      keywords: ["meeting reminder", "video call", "link", "Meet", "Teams", "declined", "cancelled", "all-day"]),
        SettingsEntry("calendar.reminders", .calendar, "Reminders due today", keywords: ["to-do", "tasks"]),
        SettingsEntry("calendar.remindersAccess", .calendar, "Reminders access", section: "Reminders",
                      keywords: ["permission", "privacy", "allow", "System Settings"]),

        SettingsEntry("timers.sound", .timers, "Sound when a timer ends", keywords: ["alarm", "chime", "ring"]),
        SettingsEntry("timers.focus", .timers, "Focus", section: "Pomodoro", keywords: ["work", "length"]),
        SettingsEntry("timers.shortBreak", .timers, "Short break", section: "Pomodoro", anchor: "timers.focus"),
        SettingsEntry("timers.longBreak", .timers, "Long break", section: "Pomodoro", anchor: "timers.focus"),
        SettingsEntry("timers.every", .timers, "Long break after", section: "Pomodoro", keywords: ["rounds"], anchor: "timers.focus"),

        SettingsEntry("notifications.mirror", .notifications, "Mirror notifications from every app", section: "Notifications",
                      keywords: ["banners", "iPhone", "messages"]),
        SettingsEntry("notifications.peek", .notifications, "Peek at new notifications", section: "Notifications",
                      keywords: ["banner", "sneak", "below the notch"]),
        SettingsEntry("notifications.welcome", .notifications, "Welcome back summary when you unlock", section: "Notifications",
                      keywords: ["unlock", "lock screen"]),
        SettingsEntry("notifications.volume", .notifications, "Volume", section: "HUDs", keywords: ["HUD", "sound", "level"]),
        SettingsEntry("notifications.brightness", .notifications, "Display brightness", section: "HUDs", keywords: ["HUD", "screen", "level"]),
        SettingsEntry("notifications.outputCard", .notifications, "Sound output changes", section: "HUDs",
                      keywords: ["AirPods", "headphones", "speaker", "connected", "audio device"]),
        SettingsEntry("notifications.keyboard", .notifications, "Keyboard brightness", section: "HUDs", keywords: ["HUD", "backlight", "keys"]),
        SettingsEntry("notifications.microphone", .notifications, "Microphone", section: "HUDs", keywords: ["HUD", "mic", "mute", "unmute"]),
        SettingsEntry("notifications.hudStyle", .notifications, "HUD style", section: "HUDs",
                      keywords: ["compact", "detailed", "percentage", "below the notch", "look"]),
        SettingsEntry("notifications.hudColour", .notifications, "HUD colour", section: "HUDs",
                      keywords: ["HUD", "color", "colourful", "green", "yellow", "accent", "tint", "keyboard"]),
        SettingsEntry("notifications.hudDuration", .notifications, "Stays on screen for", section: "HUDs",
                      keywords: ["HUD", "duration", "seconds"]),
        SettingsEntry("notifications.replaceHUD", .notifications, "Replace the system volume and brightness display", section: "HUDs",
                      keywords: ["HUD", "keys", "overlay", "accessibility"]),
        SettingsEntry("notifications.battery", .notifications, "Battery and charging", section: "Battery", keywords: ["power", "charger", "plugged in"]),
        SettingsEntry("notifications.batteryLow", .notifications, "Low battery warning", section: "Battery", keywords: ["percent"],
                      anchor: "notifications.battery"),
        SettingsEntry("notifications.batteryCritical", .notifications, "Critical battery warning", section: "Battery", keywords: ["percent"],
                      anchor: "notifications.battery"),
        SettingsEntry("notifications.batteryCharged", .notifications, "Tell me when charged to", section: "Battery",
                      keywords: ["battery", "charge limit"], anchor: "notifications.battery"),
        SettingsEntry("notifications.calls", .notifications, "Call timer", section: "Calls, camera and microphone",
                      keywords: ["FaceTime", "Zoom", "Meet", "Teams", "microphone"]),
        SettingsEntry("notifications.privacy", .notifications, "Camera and microphone in use", section: "Calls, camera and microphone",
                      keywords: ["mic", "privacy", "indicator"]),

        SettingsEntry("shelf.enabled", .shelf, "File shelf and AirDrop", section: "Shelf", keywords: ["drag", "drop", "files", "share"]),
        SettingsEntry("shelf.clipboard", .shelf, "Clipboard history", section: "Clipboard", keywords: ["copy", "paste", "pasteboard"]),
        SettingsEntry("shelf.clipboardLimit", .shelf, "Items kept", section: "Clipboard", keywords: ["history size", "clipboard"],
                      anchor: "shelf.clipboard"),
        SettingsEntry("shelf.clipboardSecrets", .shelf, "Skip passwords copied in a browser", section: "Clipboard",
                      keywords: ["password manager", "extension", "privacy", "clipboard"]),
        SettingsEntry("shelf.clipboardIgnore", .shelf, "Ignore apps", section: "Clipboard",
                      keywords: ["exclude", "privacy", "clipboard", "skip"]),

        SettingsEntry("downloads.enabled", .downloads, "Download progress", keywords: ["files", "Safari", "Chrome", "browser"]),

        SettingsEntry("ai.provider", .ai, "Answer with", section: "Ask", keywords: ["provider", "Claude", "ChatGPT", "on-device", "default"]),
        SettingsEntry("ai.effort", .ai, "Effort", section: "Ask", keywords: ["reasoning", "thinking"]),
        SettingsEntry("ai.followUps", .ai, "Keep follow-ups in memory", section: "Ask", keywords: ["history", "conversation"]),
        SettingsEntry("ai.anthropic", .ai, "Claude key", section: "Claude", keywords: ["API key", "Anthropic", "Keychain", "model"]),
        SettingsEntry("ai.openai", .ai, "ChatGPT key", section: "ChatGPT", keywords: ["API key", "OpenAI", "Keychain", "model", "GPT"]),
        SettingsEntry("ai.cli", .ai, "Claude Code and Codex apps", section: "Command-line tools", keywords: ["CLI", "terminal", "login"]),
        SettingsEntry("ai.apple", .ai, "Apple Intelligence", section: "Apple Intelligence", keywords: ["on-device", "smart icons", "summaries"]),
        SettingsEntry("ai.privacy", .ai, "What leaves this Mac", keywords: ["privacy", "data", "network"]),

        SettingsEntry("agents.claudeCode", .agents, "Connect Claude Code", section: "Connections", keywords: ["Anthropic", "set up"]),
        SettingsEntry("agents.codex", .agents, "Connect Codex", section: "Connections", keywords: ["OpenAI", "set up"]),
        SettingsEntry("agents.cursor", .agents, "Connect Cursor", section: "Connections", keywords: ["set up"]),
        SettingsEntry("agents.disconnect", .agents, "Disconnect or update an agent", section: "Connections",
                      keywords: ["remove hooks", "needs an update", "moved"], anchor: "agents.claudeCode"),
        SettingsEntry("agents.approvals", .agents, "Answer requests in the notch", section: "Approvals",
                      keywords: ["approve", "permission", "allow", "deny", "questions", "plans"]),
        SettingsEntry("agents.wait", .agents, "Hand back to the terminal after", section: "Approvals", keywords: ["timeout", "wait"]),
        SettingsEntry("agents.claudeUsage", .agents, "Claude Code limits", section: "Usage limits", keywords: ["usage", "plan", "5-hour", "weekly"]),
        SettingsEntry("agents.codexUsage", .agents, "Codex limits", section: "Usage limits", keywords: ["usage", "plan", "5-hour", "weekly"]),
        SettingsEntry("agents.openRouterUsage", .agents, "OpenRouter spending", section: "Usage limits",
                      keywords: ["usage", "credits", "limit", "key", "API key", "Keychain", "dollars"]),
        SettingsEntry("agents.ollamaUsage", .agents, "Ollama models", section: "Usage limits",
                      keywords: ["usage", "local models", "memory", "loaded", "LLM"]),
        SettingsEntry("agents.copilotUsage", .agents, "Copilot premium requests", section: "Usage limits",
                      keywords: ["usage", "GitHub", "key", "plan", "month", "Keychain"]),
        SettingsEntry("agents.copilotPlan", .agents, "Copilot plan", section: "Usage limits",
                      keywords: ["Free", "Pro", "Business", "Enterprise", "allowance"], anchor: "agents.copilotUsage"),

        SettingsEntry("tools.mirror", .tools, "Camera mirror", section: "Mirror",
                      keywords: ["camera", "webcam", "video call", "look", "hair", "check", "selfie"]),
        SettingsEntry("tools.mirrorFlip", .tools, "Flip like a mirror", section: "Mirror",
                      keywords: ["camera", "reverse", "horizontal"], anchor: "tools.mirror"),
        SettingsEntry("tools.teleprompter", .tools, "Teleprompter", section: "Teleprompter",
                      keywords: ["autocue", "script", "read", "presentation", "recording", "camera", "talk"]),
        SettingsEntry("tools.script", .tools, "Script", section: "Teleprompter",
                      keywords: ["teleprompter", "text", "paste", "words"], anchor: "tools.teleprompter"),
        SettingsEntry("tools.teleprompterSpeed", .tools, "Words a minute", section: "Teleprompter",
                      keywords: ["reading speed", "words per minute", "pace", "scroll", "faster", "slower"], anchor: "tools.teleprompter"),
        SettingsEntry("tools.teleprompterSize", .tools, "Text size", section: "Teleprompter",
                      keywords: ["teleprompter", "font", "bigger", "smaller"], anchor: "tools.teleprompter"),
        SettingsEntry("tools.seeThrough", .tools, "See-through while reading", section: "Teleprompter",
                      keywords: ["glass", "transparent", "clear", "teleprompter"], anchor: "tools.teleprompter"),
        SettingsEntry("tools.stocks", .tools, "Stocks", section: "Stocks",
                      keywords: ["shares", "watchlist", "prices", "market", "sparkline", "ticker", "index"]),
        SettingsEntry("tools.stockSymbols", .tools, "Watchlist", section: "Stocks",
                      keywords: ["symbols", "ticker", "add", "remove", "stocks"], anchor: "tools.stocks"),
        SettingsEntry("tools.sales", .tools, "Sales today", section: "Sales",
                      keywords: ["revenue", "takings", "money", "orders", "store", "shop"]),
        SettingsEntry("tools.salesStores", .tools, "Stores", section: "Sales",
                      keywords: SalesStore.allCases.map(\.title) + ["key", "connect", "Keychain", "read-only"], anchor: "tools.sales"),
    ]

    private static let system: [SettingsEntry] = [
        SettingsEntry("apps.add", .apps, "Add an app", keywords: ["app rules", "per-app", "application"]),
        SettingsEntry("apps.tint", .apps, "App colour", keywords: ["color", "tint", "per-app", "custom", "any colour", "colour panel"], anchor: "apps.add"),
        SettingsEntry("apps.hide", .apps, "Hide the island while an app is in front", keywords: ["per-app", "frontmost"], anchor: "apps.add"),
        SettingsEntry("apps.fullscreen", .apps, "Keep the island in full screen", keywords: ["per-app", "fullscreen", "games"], anchor: "apps.add"),
        SettingsEntry("apps.mute", .apps, "Mute an app's notifications and calls", keywords: ["per-app", "silence", "microphone"], anchor: "apps.add"),
        SettingsEntry("apps.muted", .apps, "Muted", keywords: ["unmute", "silenced", "right-click", "sources"]),
        SettingsEntry("apps.priority", .apps, "App priority", keywords: ["per-app", "urgent", "rank", "order", "first"], anchor: "apps.add"),
    ] + PermissionKind.allCases.map { kind in
        SettingsEntry("permissions.\(kind.rawValue)", .permissions, kind.title, keywords: ["privacy", "allow", "access"])
    } + [
        SettingsEntry("about.version", .about, "Version", keywords: ["licence", "license", "open source"]),
    ]

    private static let advanced: [SettingsEntry] = [
        SettingsEntry("advanced.api", .advanced, "Accept requests from apps on this Mac", section: "Local API",
                      keywords: ["HTTP", "server", "scripts", "REST"]),
        SettingsEntry("advanced.apiPort", .advanced, "Local API port", section: "Local API"),
        SettingsEntry("advanced.token", .advanced, "Copy API token", section: "Local API",
                      keywords: ["bearer", "authorisation", "authorization", "API guide", "documentation"]),
        SettingsEntry("advanced.shareLive", .advanced, "Let scripts read Live Activities", section: "Local API", keywords: ["privacy", "mirrored"]),
        SettingsEntry("advanced.cli", .advanced, "Command-line tool", section: "Local API", keywords: ["isletctl", "PATH", "terminal"]),
        SettingsEntry("advanced.bridge", .advanced, "Accept requests from this network", section: "iPhone bridge",
                      keywords: ["iPhone", "Shortcuts", "network", "LAN", "Home Assistant"]),
        SettingsEntry("advanced.bridgePort", .advanced, "iPhone bridge port", section: "iPhone bridge"),
        SettingsEntry("advanced.bridgeToken", .advanced, "iPhone bridge token", section: "iPhone bridge", keywords: ["bearer", "new token"]),
        SettingsEntry("advanced.hooks", .advanced, "Agent hook commands", section: "Coding agents",
                      keywords: ["hooks", "Claude Code", "Codex", "Cursor", "settings.json", "config.toml", "notify", "JSON"]),
        SettingsEntry("advanced.mcp", .advanced, "MCP server", section: "Coding agents", keywords: ["Model Context Protocol", "Claude Desktop", "tools"]),
        SettingsEntry("advanced.scripts", .advanced, "Run scripts from the plugins folder", section: "Script widgets",
                      keywords: ["xbar", "SwiftBar", "widgets"]),
        SettingsEntry("advanced.pluginsFolder", .advanced, "Plugins folder", section: "Script widgets", keywords: ["scripts", "examples"]),
        SettingsEntry("advanced.urlScheme", .advanced, "Links that control Islet", section: "Links", keywords: ["URL scheme", "islet://"]),
        SettingsEntry("advanced.config", .advanced, "Settings file", section: "Settings file", keywords: ["config.json", "dotfiles", "JSON"]),
        SettingsEntry("advanced.configReplace", .advanced, "Replace a settings file with an error", section: "Settings file",
                      keywords: ["config.json", "broken", "invalid", "repair", "last good settings"], anchor: "advanced.config"),
        SettingsEntry("advanced.diagnostics", .advanced, "Diagnostics", section: "Diagnostics",
                      keywords: ["status", "debug", "troubleshoot", "Now Playing helper", "test activity"]),
        SettingsEntry("advanced.cliPaths", .advanced, "Where Claude Code and Codex were found", section: "Diagnostics",
                      keywords: ["not installed", "path", "folder", "CLI", "command-line", "Ask"]),
        SettingsEntry("advanced.reset", .advanced, "Reset all settings", section: "Reset", keywords: ["defaults", "restore"]),
    ]
}
