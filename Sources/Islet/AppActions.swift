import AppKit
import IsletCore
import IsletSystem
import SwiftUI

/// Actions triggered from views, the status menu and the URL scheme.
@MainActor
enum AppActions {
    static var openSettingsHandler: ((SettingsPage?, String?) -> Void)?

    /// Whether an `isletctl` is there to run. Settings snapshots, which show the installed
    /// location without an installed app, say yes.
    static var isExecutable: @Sendable (String) -> Bool = { FileManager.default.isExecutableFile(atPath: $0) }

    /// Open the Settings window on `page`, scrolled to the row `anchor` names (an id from
    /// `SettingsIndex`), or else on the page it showed last.
    static func openSettings(_ page: SettingsPage? = nil, at anchor: String? = nil) { openSettingsHandler?(page, anchor) }

    /// Whether an app is installed (for a meeting's call app icon).
    static var isInstalled: (String) -> Bool = { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) != nil }

    static func pluginsFolder(_ model: AppModel) -> URL {
        model.settings.pluginDirectory.map { URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath) } ?? IsletPaths.pluginsDirectory
    }

    static func openPluginsFolder(_ model: AppModel) {
        let dir = pluginsFolder(model)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        NSWorkspace.shared.open(dir)
    }

    /// Copy the bundled example plugins into the plugins folder.
    static func installExamplePlugins(_ model: AppModel) {
        let dir = pluginsFolder(model)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        for (name, body) in ExamplePlugins.all {
            let url = dir.appendingPathComponent(name)
            guard !FileManager.default.fileExists(atPath: url.path) else { continue }
            try? body.write(to: url, atomically: true, encoding: .utf8)
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        }
        model.pluginRunner?.rescan()
    }

    /// Plugin commands the user has agreed to run this session.
    private static var confirmedCommands: Set<String> = []

    static func runPluginLine(_ line: ScriptPlugins.Line, plugin: PluginResult, model: AppModel) {
        if let url = line.href { NSWorkspace.shared.open(url) }
        if let argv = line.shellCommand, let exe = argv.first, confirm(argv, plugin: plugin) {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: exe.hasPrefix("/") ? exe : "/usr/bin/env")
            p.arguments = exe.hasPrefix("/") ? Array(argv.dropFirst()) : argv
            p.currentDirectoryURL = URL(fileURLWithPath: plugin.path).deletingLastPathComponent()
            try? p.run()
        }
        if line.refreshOnClick { model.runPlugin(plugin.path) }
    }

    /// Show the exact command the first time a plugin's menu item would run it.
    private static func confirm(_ argv: [String], plugin: PluginResult) -> Bool {
        let key = plugin.path + "\u{0}" + argv.joined(separator: "\u{0}")
        if confirmedCommands.contains(key) { return true }
        let alert = NSAlert()
        alert.messageText = "Run this command from “\(plugin.name)”?"
        alert.informativeText = argv.map { $0.contains(" ") ? "'\($0)'" : $0 }.joined(separator: " ")
        alert.addButton(withTitle: "Run")
        alert.addButton(withTitle: "Cancel")
        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return false }
        confirmedCommands.insert(key)
        return true
    }

    static func setClipboard(_ model: AppModel, enabled: Bool) {
        model.settings.clipboardEnabled = enabled
        model.saveSettings()
        NotificationCenter.default.post(name: .isletSettingsChanged, object: nil)
    }

    /// Show a sample activity so appearance changes can be judged live.
    static func previewAppearance(_ model: AppModel) {
        model.remove(activityID: "preview")
        _ = try? model.commit(ActivitySpec(
            id: "preview", source: "preview", title: "Looking good", subtitle: "This is how new activities arrive",
            icon: .symbol("sparkles"), progress: 0.6, state: .running, ttl: 6, sneak: true
        ))
    }

    /// Hold the closed island on screen for a few seconds while "Fit to the notch" changes, so
    /// its edges can be matched against the notch by eye. No sneak peek and no bounce.
    static func previewNotchFit(_ model: AppModel) {
        _ = try? model.commit(ActivitySpec(
            id: "preview-fit", source: "preview", title: "Fit to the notch", icon: .symbol("arrow.left.and.right"),
            trailing: "Fit", state: .info, tint: "blue", priority: .high, ttl: 4, sneak: false
        ))
    }

    /// The token is a secret: concealed from clipboard history (including Islet's own) and kept
    /// off other devices.
    static func copyToken() {
        guard let d = APIDiscoveryStore.read() else { return }
        ClipboardMonitor.write(d.token, secret: true)
    }

    static var cliPath: String {
        bundleURL.appendingPathComponent("Contents/MacOS/isletctl").path
    }

    /// Where Islet.app is. Settings snapshots show the installed location, not the build folder.
    static var bundleURL = Bundle.main.bundleURL

    /// Whether this is the app itself rather than a build run from the command line, which has
    /// no Applications folder to belong in. Settings snapshots say yes to draw the offer to move.
    static var runsAsApp = Bundle.main.bundleIdentifier != nil && Bundle.main.bundlePath.hasSuffix(".app")

    // MARK: Moving to Applications

    enum MoveAnswer: Equatable {
        /// Islet is where it should be (or this moment doesn't ask).
        case notNeeded
        case declined
        /// Moved: Islet quits and opens again from Applications.
        case moving
    }

    /// Offer to move Islet to Applications when it runs from Downloads (`AppLocation`): at
    /// launch, before connecting a coding agent, or when asked in Settings. Moving copies Islet
    /// there, puts the downloaded copy in the Bin, and opens Islet again from its new place.
    @discardableResult
    static func offerMoveToApplications(_ moment: AppLocation.MoveMoment) -> MoveAnswer {
        let home = NSHomeDirectory()
        let bundle = bundleURL
        guard AppLocation.offersMove(bundlePath: bundle.path, home: home, isAppBundle: runsAsApp, moment: moment) else { return .notNeeded }
        let translocated = AppLocation.isTranslocated(bundlePath: bundle.path)
        // Where it was downloaded to; for a copy that wasn't translocated, the copy itself.
        let original = translocated ? AppMover.originalURL(of: bundle) : bundle
        let destination = URL(fileURLWithPath: AppLocation.destination(
            appName: bundle.lastPathComponent, home: home,
            canWriteSharedApplications: FileManager.default.isWritableFile(atPath: "/Applications")))
        let alert = moveAlert(moment, folder: original.map(folderName), translocated: translocated, destination: destination,
                              replacing: FileManager.default.fileExists(atPath: destination.path))
        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return .declined }
        do {
            try AppMover.move(bundle, to: destination, original: original, trash: AppMover.moveToBin)
            try AppMover.reopen(at: destination)
        } catch {
            let failed = NSAlert()
            failed.icon = alertIcon
            failed.messageText = "Islet couldn\u{2019}t move itself"
            failed.informativeText = "\(error.localizedDescription) You can drag Islet into Applications in Finder instead."
            failed.addButton(withTitle: "Show in Finder")
            failed.addButton(withTitle: "OK")
            if failed.runModal() == .alertFirstButtonReturn {
                NSWorkspace.shared.activateFileViewerSelecting([original ?? bundle])
            }
            return .declined
        }
        NSApp.terminate(nil)
        return .moving
    }

    /// The offer itself, also drawn by `--settings-snapshot`.
    static func moveAlert(_ moment: AppLocation.MoveMoment, folder: String?, translocated: Bool, destination: URL,
                          replacing: Bool) -> NSAlert {
        let words = AppLocation.prompt(for: moment, folder: folder, translocated: translocated, destination: destination.path,
                                       home: NSHomeDirectory(), replacing: replacing)
        let alert = NSAlert()
        alert.icon = alertIcon
        alert.messageText = words.title
        alert.informativeText = words.message
        alert.addButton(withTitle: words.confirm)
        alert.addButton(withTitle: words.cancel)
        return alert
    }

    /// The icon on Islet's own alerts: the app's icon, or, for a build run from the command line
    /// (which has none, so the alert would show an empty square), the tile from About.
    static var alertIcon: NSImage? {
        if let url = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"), let icon = NSImage(contentsOf: url) {
            return icon
        }
        // A little inset, as app icons have.
        let renderer = ImageRenderer(content: IsletTile(size: 56).padding(4))
        renderer.scale = 2
        return renderer.nsImage
    }

    /// The folder a copy sits in, as Finder names it ("Downloads").
    private static func folderName(_ url: URL) -> String {
        FileManager.default.displayName(atPath: url.deletingLastPathComponent().path)
    }

    /// Handle an `islet://` URL.
    static func handle(url: URL, model: AppModel) {
        do {
            switch try URLCommand.parse(url) {
            case .activity(let spec): try model.applyLocal(spec)
            case .dismiss(let id): model.remove(activityID: id)
            case .timer(let seconds, let title): try model.timers.perform(.start(seconds: seconds, title: title, id: nil))
            case .timerCommand(let command): try model.timers.perform(command)
            case .hud(let kind, let value): Task { await model.showHUD(kind: kind, value: value, muted: false, label: nil) }
            case .media(let cmd): model.send(cmd)
            case .focus(let name, let on): try model.applyLocal(FocusPill.activity(name: name, on: on))
            case .open: model.setExpanded(model.targetDisplay())
            case .awake(let change): model.setKeepAwake(change, announce: true)
            case .ask(let query, let provider): openAsk(model, query: query, provider: provider)
            case .close: model.setExpanded(nil)
            case .toggle: model.setExpanded(model.expandedScreen == nil ? model.targetDisplay() : nil)
            case .settings: openSettings()
            }
        } catch {
            // The command only, not the query: islet://ask carries the user's question.
            NSLog("Islet: bad URL %@://%@%@: %@", url.scheme ?? "", url.host ?? "", url.path, String(describing: error))
        }
    }
}

enum ExamplePlugins {
    static let all: [(String, String)] = [
        ("uptime.1m.sh", """
        #!/bin/bash
        # Shows system uptime. xbar format: first line is the header.
        up=$(uptime | sed -E 's/.*up ([^,]*),.*/\\1/')
        echo "⏱ Up $up | sfimage=clock"
        echo "---"
        echo "Activity Monitor | shell=/usr/bin/open param1=-a param2='Activity Monitor'"
        """),
        ("disk.10m.sh", """
        #!/bin/bash
        # Free space on the startup disk.
        free=$(df -h / | awk 'NR==2 {print $4}')
        echo "Disk: $free free | sfimage=internaldrive"
        echo "---"
        echo "Storage Settings | href=x-apple.systempreferences:com.apple.settings.Storage"
        """),
        ("github-notifications.5m.sh", """
        #!/bin/bash
        # Unread GitHub notifications via the gh CLI (brew install gh; gh auth login).
        if ! command -v gh >/dev/null; then echo "GitHub: install gh | color=gray"; exit 0; fi
        n=$(gh api notifications --jq 'length' 2>/dev/null || echo "?")
        echo "GitHub: $n unread | sfimage=bell"
        echo "---"
        echo "Open notifications | href=https://github.com/notifications"
        """),
    ]
}
