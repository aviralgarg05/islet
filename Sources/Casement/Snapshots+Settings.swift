import AppKit
import CasementCore
import CasementSystem
import SwiftUI

/// `Casement --settings-snapshot <dir>` draws the Settings window without showing it: every page
/// in light and dark at the default size, and one page of search results. With
/// `CASEMENT_SNAPSHOT_EXTRA=1` it also draws, in `<dir>/extra`, every page at the minimum size, a
/// search with no results, a result opened at its row and the Apps page with no apps.
///
/// It runs in a child process whose home, config and support folders are temporary (set up in
/// main.swift), with sample settings and an API key kept in memory, so nothing real is read
/// or written.
@MainActor
enum SettingsSnapshots {
    static func render(to dir: URL, home: URL) -> Bool {
        // Never draw from the real home folder: the pages read ~/.claude, ~/.codex and ~/.cursor.
        guard CasementPaths.home.standardizedFileURL.path == home.standardizedFileURL.path,
              NSHomeDirectory() == home.path else {
            print("Settings snapshots need a temporary home folder, and the real one is in use. Nothing was rendered.")
            return false
        }
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        AppActions.bundleURL = URL(fileURLWithPath: "/Applications/Casement.app")
        // As if Casement were installed there, so connected agents read as connected.
        AppActions.isExecutable = { _ in true }
        seedAgents(home: home)

        let secrets = MemorySecretStore([AskProviderKind.anthropic.keyAccount ?? "": "snapshot-sample-0000",
                                         ToolUsageSource.openRouter.keyAccount ?? "": "snapshot-sample-0001",
                                         SalesStore.stripe.keyAccount: "snapshot-sample-0002",
                                         SalesStore.shopify.keyAccount: "snapshot-sample-0003"])
        let model = AppModel(settings: sampleSettings, ask: AskController(service: AskService(secrets: secrets)), secrets: secrets,
                             scriptFile: nil)
        model.teleprompter.setScript(Snapshots.teleprompterDemo)
        model.apiStatus = "Listening on 127.0.0.1:\(model.settings.apiPort)"
        // Drawn as if macOS allowed calendars and reminders; the other states have shots of their own.
        model.setCalendarAccessForSnapshot(events: .fullAccess, reminders: .fullAccess)
        let navigation = SettingsNavigation()
        let window = SettingsWindow.make(model: model, navigation: navigation, window: OffscreenWindow(), snapshot: true)
        window.setFrameOrigin(NSPoint(x: -20000, y: -20000))

        func shoot(_ name: String, in folder: URL = dir, light: Bool = true, dark: Bool = true) {
            if light { capture(window, appearance: .aqua, to: folder.appendingPathComponent("\(name)-light.png")) }
            if dark { capture(window, appearance: .darkAqua, to: folder.appendingPathComponent("\(name)-dark.png")) }
        }

        for (i, page) in SettingsPage.allCases.enumerated() {
            navigation.open(page)
            shoot(String(format: "%02d-%@", i + 1, page.rawValue))
        }
        // Increase Contrast: the picture tiles, swatches and search field get a firmer edge.
        let contrast = SettingsWindow.make(model: model, navigation: navigation, window: OffscreenWindow(), snapshot: true,
                                           increasedContrast: true)
        contrast.setFrameOrigin(NSPoint(x: -20000, y: -20000))
        navigation.open(.appearance)
        capture(contrast, appearance: .accessibilityHighContrastAqua, to: dir.appendingPathComponent("appearance-increased-contrast-light.png"))
        capture(contrast, appearance: .accessibilityHighContrastDarkAqua, to: dir.appendingPathComponent("appearance-increased-contrast-dark.png"))
        navigation.query = "colour"
        capture(window, appearance: .aqua, to: dir.appendingPathComponent("search-results.png"))
        // Calendar access that explains itself: "Add events only" for calendars, reminders turned
        // off in System Settings, on the Calendar page and on Permissions.
        model.setCalendarAccessForSnapshot(events: .writeOnly, reminders: .denied)
        navigation.query = ""
        navigation.open(.calendar)
        shoot("calendar-access-write-only", dark: false)
        navigation.open(.permissions)
        shoot("permissions-calendar-write-only", dark: false)
        model.setCalendarAccessForSnapshot(events: .notDetermined, reminders: .restricted)
        navigation.open(.calendar)
        shoot("calendar-access-not-asked", dark: false)
        model.setCalendarAccessForSnapshot(events: .fullAccess, reminders: .fullAccess)

        // The GIF look on Now Playing: Casement's stickers and one of your own (made from a
        // built-in, in the temporary support folder), with the position, size and idle rows.
        if let notes = model.stickers.url(for: .builtIn(.notes)) { _ = try? model.stickers.store.add(from: notes) }
        model.stickers.reload()
        var gif = sampleSettings
        gif.visualiserStyle = .gif
        gif.sticker = StickerSettings(id: "jelly", offsetX: -2, offsetY: 0, scale: 1.1, whenIdle: true)
        model.settings = gif
        window.setContentSize(NSSize(width: SettingsWindow.defaultSize.width, height: 2150))
        navigation.open(.nowPlaying)
        shoot("now-playing-gif")
        contrast.setContentSize(NSSize(width: SettingsWindow.defaultSize.width, height: 2150))
        capture(contrast, appearance: .accessibilityHighContrastDarkAqua, to: dir.appendingPathComponent("now-playing-gif-increased-contrast-dark.png"))
        contrast.orderOut(nil)
        model.stickers.problem = StickerImportError.tooLarge.message
        shoot("now-playing-gif-problem", dark: false)
        model.stickers.problem = nil
        gif.visualiserStyle = .vinyl
        model.settings = gif
        shoot("now-playing-vinyl", dark: false)
        model.settings = sampleSettings
        window.setContentSize(SettingsWindow.defaultSize)
        RunLoop.main.run(until: Date().addingTimeInterval(0.5))

        // Lyrics with music in a web browser too, opened at their rows.
        var lyricsOn = sampleSettings
        lyricsOn.lyricsEnabled = true
        lyricsOn.lyricsIncludeBrowsers = true
        model.settings = lyricsOn
        window.setContentSize(NSSize(width: SettingsWindow.defaultSize.width, height: 1400))
        navigation.open(.nowPlaying, at: "nowPlaying.lyrics")
        shoot("now-playing-lyrics")
        model.settings = sampleSettings
        navigation.open(.nowPlaying, at: "nowPlaying.lyrics")
        shoot("now-playing-lyrics-off", dark: false)
        window.setContentSize(SettingsWindow.defaultSize)
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))

        // The note tools and the pages in the switcher, each opened at its row in a tall window.
        // (How long the shelf keeps files and Send feedback show on their pages' own shots.)
        window.setContentSize(NSSize(width: SettingsWindow.defaultSize.width, height: 1400))
        for (name, page, anchor) in [("tools-note-tools", SettingsPage.tools, "tools.todos"),
                                     ("general-island-pages", .general, "general.pages")] {
            navigation.open(page, at: anchor)
            shoot(name, dark: name == "general-island-pages")
        }
        window.setContentSize(SettingsWindow.defaultSize)
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))

        // Opened from Downloads: General offers to move Casement to Applications, and the offer
        // itself, at launch and before connecting a coding agent.
        let installedAt = AppActions.bundleURL
        let runsAsApp = AppActions.runsAsApp
        AppActions.bundleURL = home.appendingPathComponent("Downloads/Casement.app")
        AppActions.runsAsApp = true
        navigation.open(.appearance)
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))
        navigation.open(.general)
        shoot("general-move-to-applications", dark: false)
        let moments: [(String, AppLocation.MoveMoment)] = [("launch", .launch), ("connecting", .connecting("Claude Code"))]
        for (name, moment) in moments {
            let alert = AppActions.moveAlert(moment, folder: "Downloads", translocated: true,
                                             destination: URL(fileURLWithPath: "/Applications/Casement.app"), replacing: false)
            alert.window.appearance = NSAppearance(named: .aqua)
            alert.layout()
            if let view = alert.window.contentView?.superview ?? alert.window.contentView {
                capture(view, to: dir.appendingPathComponent("move-offer-\(name)-light.png"))
            }
        }
        AppActions.bundleURL = installedAt
        AppActions.runsAsApp = runsAsApp
        navigation.open(.appearance)
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))

        if ProcessInfo.processInfo.environment["CASEMENT_SNAPSHOT_EXTRA"] == "1" {
            let extra = dir.appendingPathComponent("extra")
            try? FileManager.default.createDirectory(at: extra, withIntermediateDirectories: true)
            navigation.query = "port"
            shoot("search-port", in: extra, light: false)
            navigation.query = "xylophone"
            shoot("search-nothing", in: extra, dark: false)
            if let entry = SettingsIndex.entries.first(where: { $0.id == "notifications.privacy" }) {
                navigation.open(entry)
                shoot("search-opened-row", in: extra, dark: false)
            }
            let rules = model.settings.appRules
            model.settings.appRules = []
            navigation.open(.apps)
            shoot("apps-empty", in: extra)
            model.settings.appRules = rules
            var custom = model.settings
            custom.theme = .graphite
            custom.sizePreset = .custom
            custom.expandedWidth = 760
            custom.expandedHeight = 260
            custom.wingWidth = 120
            custom.accentColor = "#34C759"
            custom.musicColour = .accent
            custom.songProgressRing = true
            custom.visualiserStyle = .dots
            model.settings = custom
            // Tall enough to show the accent swatches, the picked colour among them.
            window.setContentSize(NSSize(width: SettingsWindow.defaultSize.width, height: 760))
            navigation.open(.appearance)
            shoot("appearance-custom", in: extra)
            window.setContentSize(SettingsWindow.defaultSize)
            // Opening on click: the peek at what's playing takes the hover delay's place.
            var click = sampleSettings
            click.hoverToOpen = false
            model.settings = click
            navigation.open(.general)
            shoot("general-click", in: extra, dark: false)
            model.settings = sampleSettings
            // Let the save that change queued go first: a save that works clears the problem.
            RunLoop.main.run(until: Date().addingTimeInterval(0.5))
            // config.json with an error: the last good settings stay, and Advanced says so.
            model.setSettingsProblemForSnapshot(FileProblem(line: 12, message: "Badly formed object around line 12, column 3."))
            window.setContentSize(NSSize(width: SettingsWindow.defaultSize.width, height: 1500))
            navigation.open(.advanced, at: "advanced.config")
            shoot("advanced-config-error", in: extra)
            // Already broken at launch, with no copy of a good one: the defaults, said plainly.
            model.setSettingsProblemForSnapshot(FileProblem(line: 3, message: "Unexpected character around line 3, column 1."),
                                                origin: .defaults)
            shoot("advanced-config-error-defaults", in: extra, dark: false)
            model.setSettingsProblemForSnapshot(nil)
            // Live Activities on a macOS before 26: the page says why its switch is off.
            window.setContentSize(SettingsWindow.defaultSize)
            let liveActivitiesSupported = model.liveActivitiesSupported
            model.liveActivitiesSupported = false
            navigation.open(.liveActivities)
            shoot("live-activities-before-macos-26", in: extra, dark: false)
            model.liveActivitiesSupported = liveActivitiesSupported
            // Battery and timers muted from the island: their pages list them with Unmute, and
            // say what still shows.
            var muted = sampleSettings
            muted.mutedSources += ["battery", TimerEngine.source]
            model.settings = muted
            navigation.open(.notifications)
            shoot("notifications-muted", in: extra, dark: false)
            navigation.open(.timers)
            shoot("timers-muted", in: extra, dark: false)
            model.settings = sampleSettings
            RunLoop.main.run(until: Date().addingTimeInterval(0.5))
            // Casement.app moved since Claude Code was connected: it runs from a new place, and the
            // casementctl the hooks call is gone. Needs an update, and a dot.
            window.setContentSize(SettingsWindow.defaultSize)
            let installed = AppActions.bundleURL
            AppActions.bundleURL = URL(fileURLWithPath: "/Users/Shared/Apps/Casement.app")
            let movedCLI = AppActions.cliPath
            AppActions.isExecutable = { $0 == movedCLI }
            navigation.open(.general)
            RunLoop.main.run(until: Date().addingTimeInterval(0.2))
            navigation.open(.agents)
            shoot("agents-moved", in: extra, dark: false)
            AppActions.bundleURL = installed
            AppActions.isExecutable = { _ in true }
            navigation.open(.general)
            RunLoop.main.run(until: Date().addingTimeInterval(0.2))
            navigation.open(.agents)
            RunLoop.main.run(until: Date().addingTimeInterval(0.5))
            // Requests from apps turned off: connected agents can't reach Casement, and the iPhone
            // bridge says what it needs.
            var apiOff = sampleSettings
            apiOff.apiEnabled = false
            apiOff.lanBridgeEnabled = true
            model.settings = apiOff
            navigation.open(.general)
            RunLoop.main.run(until: Date().addingTimeInterval(0.2))
            navigation.open(.agents)
            shoot("agents-api-off", in: extra, dark: false)
            navigation.open(.advanced, at: "advanced.bridge")
            shoot("advanced-bridge-api-off", in: extra, dark: false)
            model.settings = sampleSettings
            RunLoop.main.run(until: Date().addingTimeInterval(0.5))
            // What Connect and Show usage… ask before changing an agent's settings, folded and open.
            if let plan = try? AgentHookSetup.plan(.codex, home: home, executable: AppActions.cliPath, wait: 300) {
                for open in [false, true] {
                    shootSheet(open ? "sheet-connect-codex-open" : "sheet-connect-codex", in: extra,
                               AgentConnectSheet(plan: plan, showsChange: open, onConfirm: {}, onCancel: {}))
                }
            }
            if let edit = try? ClaudeStatusLineSetup.install(into: Data("{\"statusLine\": {\"type\": \"command\", \"command\": \"~/bin/prompt\"}}".utf8),
                                                            cli: AppActions.cliPath) {
                let change = PendingStatusLineEdit(install: true, edit: edit)
                let file = home.appendingPathComponent(".claude/settings.json")
                for open in [false, true] {
                    shootSheet(open ? "sheet-status-line-open" : "sheet-status-line", in: extra,
                               StatusLineChangeSheet(change: change, file: file, showsChange: open, onConfirm: {}, onCancel: {}))
                }
            }
            window.setContentSize(SettingsWindow.minimumSize)
            for (i, page) in SettingsPage.allCases.enumerated() {
                navigation.open(page)
                capture(window, appearance: .aqua, to: extra.appendingPathComponent(String(format: "minimum-%02d-%@.png", i + 1, page.rawValue)))
            }
            // Whole pages, to check what is below the fold.
            window.setContentSize(NSSize(width: SettingsWindow.defaultSize.width, height: 2300))
            for (i, page) in SettingsPage.allCases.enumerated() {
                navigation.open(page)
                capture(window, appearance: .darkAqua, to: extra.appendingPathComponent(String(format: "full-%02d-%@.png", i + 1, page.rawValue)))
            }
        }
        print("Rendered Settings snapshots to \(dir.path)")
        return true
    }

    /// Settings with something to show on every page.
    static var sampleSettings: CasementSettings {
        var s = CasementSettings()
        s.clipboardEnabled = true
        s.clipboardIgnoredApps = ["com.apple.Notes"]
        s.hiddenMediaApps = ["com.apple.TV"]
        // The volume HUD on without replacing macOS's display, so the "shows two" note shows.
        s.hudEnabled = true
        s.mutedSources = ["live-activity:uber-eats", "live-activity:doordash", "github-actions", "cli"]
        s.remindersEnabled = true
        s.pluginsEnabled = true
        s.weatherEnabled = true
        s.weatherPlace = WeatherPlace(name: "London", region: "England", country: "United Kingdom", latitude: 51.51, longitude: -0.13)
        // Every tool on, so the Tools page shows what each offers.
        s.mirror.enabled = true
        s.teleprompter.enabled = true
        s.stocks.enabled = true
        s.sales = SalesSettings(enabled: true, stores: [.stripe, .shopify], shopifyStore: "example.myshopify.com")
        s.openRouterUsageEnabled = true
        s.copilotUsageEnabled = true
        s.systemStatsEnabled = true
        s.todosEnabled = true
        s.noteEnabled = true
        s.converterEnabled = true
        s.emojiEnabled = true
        s.emojiTypes = true
        // To-dos moved into the capsule and Widgets left out, so the pages list shows both.
        s.islandPages.move(.todos, onto: .shelf)
        s.islandPages.setShown(.widgets, false)
        s.appRules = [
            // A colour from the colour panel shows as "Custom".
            AppRule(bundleID: "com.apple.Safari", tint: "#2F7CF6"),
            AppRule(bundleID: "com.apple.Music", showInFullscreen: true, priority: .high),
            AppRule(bundleID: "com.apple.MobileSMS", tint: "green", muteNotifications: true),
        ]
        return s
    }

    /// In the temporary home: Claude Code connected, Codex installed but not connected, and
    /// Cursor not installed.
    private static func seedAgents(home: URL) {
        if let plan = try? AgentHookSetup.plan(.claudeCode, home: home, executable: AppActions.cliPath, wait: 300) {
            try? AgentHookSetup.apply(plan)
        }
        try? FileManager.default.createDirectory(at: home.appendingPathComponent(".codex/sessions"), withIntermediateDirectories: true)
    }

    /// A sheet's content on its own, at the size it asks for, on the window background.
    private static func shootSheet<Content: View>(_ name: String, in folder: URL, _ content: Content) {
        let host = NSHostingView(rootView: content.background(Color(nsColor: .windowBackgroundColor)).environment(\.snapshotMode, true))
        let sheet = OffscreenWindow(contentRect: NSRect(origin: .zero, size: host.fittingSize), styleMask: [.borderless],
                                    backing: .buffered, defer: false)
        sheet.contentView = host
        sheet.setFrameOrigin(NSPoint(x: -20000, y: -20000))
        sheet.appearance = NSAppearance(named: .aqua)
        RunLoop.main.run(until: Date().addingTimeInterval(0.4))
        sheet.setContentSize(host.fittingSize)
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))
        capture(host, to: folder.appendingPathComponent("\(name)-light.png"))
        sheet.orderOut(nil)
    }

    private static func capture(_ window: NSWindow, appearance: NSAppearance.Name, to url: URL) {
        window.appearance = NSAppearance(named: appearance)
        // Let SwiftUI apply the change, lay out, and run the page's onAppear work.
        RunLoop.main.run(until: Date().addingTimeInterval(0.5))
        guard let frame = window.contentView?.superview else { return }
        capture(frame, to: url)
    }

    /// Draws a view, with everything inside it, to a PNG.
    private static func capture(_ frame: NSView, to url: URL) {
        frame.layoutSubtreeIfNeeded()
        guard let rep = frame.bitmapImageRepForCachingDisplay(in: frame.bounds) else { return }
        frame.cacheDisplay(in: frame.bounds, to: rep)
        guard let png = rep.representation(using: .png, properties: [:]) else {
            print("failed to render \(url.lastPathComponent)")
            return
        }
        try? png.write(to: url)
    }
}

/// A window that may sit off every screen, so drawing it never shows anything. It says it is
/// key, so controls draw in their active colours as they do in front of the user.
private final class OffscreenWindow: NSWindow {
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
    override var isKeyWindow: Bool { true }
    override var isMainWindow: Bool { true }

    // The snapshot process is never the active app (it must not take focus from whoever runs
    // it), and AppKit draws switches and checkboxes grey in a window of an app that isn't.
    // AppKit asks the window these, so they answer as a window in front would.
    @objc(_hasActiveAppearance) func snapshotHasActiveAppearance() -> Bool { true }
    @objc(_hasActiveAppearanceIgnoringKeyFocus) func snapshotHasActiveAppearanceIgnoringKeyFocus() -> Bool { true }
    @objc(_hasKeyAppearance) func snapshotHasKeyAppearance() -> Bool { true }
}
