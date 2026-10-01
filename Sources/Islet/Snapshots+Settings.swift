import AppKit
import IsletCore
import IsletSystem
import SwiftUI

/// `Islet --settings-snapshot <dir>` draws the Settings window without showing it: every page
/// in light and dark at the default size, and one page of search results. With
/// `ISLET_SNAPSHOT_EXTRA=1` it also draws, in `<dir>/extra`, every page at the minimum size, a
/// search with no results, a result opened at its row and the Apps page with no apps.
///
/// It runs in a child process whose home, config and support folders are temporary (set up in
/// main.swift), with sample settings and an API key kept in memory, so nothing real is read
/// or written.
@MainActor
enum SettingsSnapshots {
    static func render(to dir: URL, home: URL) -> Bool {
        // Never draw from the real home folder: the pages read ~/.claude, ~/.codex and ~/.cursor.
        guard IsletPaths.home.standardizedFileURL.path == home.standardizedFileURL.path,
              NSHomeDirectory() == home.path else {
            print("Settings snapshots need a temporary home folder, and the real one is in use. Nothing was rendered.")
            return false
        }
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        AppActions.bundleURL = URL(fileURLWithPath: "/Applications/Islet.app")
        // As if Islet were installed there, so connected agents read as connected.
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

        if ProcessInfo.processInfo.environment["ISLET_SNAPSHOT_EXTRA"] == "1" {
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
            navigation.open(.appearance)
            shoot("appearance-custom", in: extra)
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
            // Islet.app moved since Claude Code was connected: it runs from a new place, and the
            // isletctl the hooks call is gone. Needs an update, and a dot.
            window.setContentSize(SettingsWindow.defaultSize)
            let installed = AppActions.bundleURL
            AppActions.bundleURL = URL(fileURLWithPath: "/Users/Shared/Apps/Islet.app")
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
    static var sampleSettings: IsletSettings {
        var s = IsletSettings()
        s.clipboardEnabled = true
        s.clipboardIgnoredApps = ["com.apple.Notes"]
        s.remindersEnabled = true
        s.pluginsEnabled = true
        // Every tool on, so the Tools page shows what each offers.
        s.mirror.enabled = true
        s.teleprompter.enabled = true
        s.stocks.enabled = true
        s.sales = SalesSettings(enabled: true, stores: [.stripe, .shopify], shopifyStore: "example.myshopify.com")
        s.openRouterUsageEnabled = true
        s.copilotUsageEnabled = true
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

    private static func capture(_ window: NSWindow, appearance: NSAppearance.Name, to url: URL) {
        window.appearance = NSAppearance(named: appearance)
        // Let SwiftUI apply the change, lay out, and run the page's onAppear work.
        RunLoop.main.run(until: Date().addingTimeInterval(0.5))
        guard let frame = window.contentView?.superview else { return }
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
}
