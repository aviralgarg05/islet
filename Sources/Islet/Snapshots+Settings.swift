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
        seedAgents(home: home)

        let secrets = MemorySecretStore([AskProviderKind.anthropic.keyAccount ?? "": "snapshot-sample-0000"])
        let model = AppModel(settings: sampleSettings, ask: AskController(service: AskService(secrets: secrets)))
        model.apiStatus = "Listening on 127.0.0.1:\(model.settings.apiPort)"
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
            model.settings = sampleSettings
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
        s.remindersEnabled = true
        s.pluginsEnabled = true
        s.appRules = [
            AppRule(bundleID: "com.apple.Safari", tint: "blue"),
            AppRule(bundleID: "com.apple.Music", showInFullscreen: true),
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
