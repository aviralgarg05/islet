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
