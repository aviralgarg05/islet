import AppKit
import IsletCore
import IsletSystem
import SwiftUI

/// Actions triggered from views, the status menu and the URL scheme.
@MainActor
enum AppActions {
    static var openSettingsHandler: (() -> Void)?

    static func openSettings() { openSettingsHandler?() }

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

    static func runPluginLine(_ line: ScriptPlugins.Line, plugin: PluginResult, model: AppModel) {
        if let url = line.href { NSWorkspace.shared.open(url) }
        if let argv = line.shellCommand, let exe = argv.first {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: exe.hasPrefix("/") ? exe : "/usr/bin/env")
            p.arguments = exe.hasPrefix("/") ? Array(argv.dropFirst()) : argv
            p.currentDirectoryURL = URL(fileURLWithPath: plugin.path).deletingLastPathComponent()
            try? p.run()
        }
        if line.refreshOnClick { model.runPlugin(plugin.path) }
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

    static func copyToken() {
        guard let d = APIDiscoveryStore.read() else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(d.token, forType: .string)
    }

    static var cliPath: String {
        Bundle.main.bundleURL.appendingPathComponent("Contents/MacOS/isletctl").path
    }

    /// Handle an `islet://` URL.
    static func handle(url: URL, model: AppModel) {
        do {
            switch try URLCommand.parse(url) {
            case .activity(let spec): try model.applyLocal(spec)
            case .dismiss(let id): model.remove(activityID: id)
            case .timer(let seconds, let title):
                let now = Date()
                try model.applyLocal(ActivitySpec(
                    id: "timer-\(Int(now.timeIntervalSince1970))", source: "timer", title: title ?? "Timer",
                    icon: .symbol("timer"), state: .running, tint: "orange", ttl: seconds + 8,
                    endsAt: now.addingTimeInterval(seconds), sneak: true
                ))
            case .hud(let kind, let value): Task { await model.showHUD(kind: kind, value: value, muted: false, label: nil) }
            case .media(let cmd): model.send(cmd)
            case .focus(let name, let on): try model.applyLocal(FocusPill.activity(name: name, on: on))
            case .open: model.setExpanded(NSScreen.main?.displayID)
            case .close: model.setExpanded(nil)
            case .toggle: model.setExpanded(model.expandedScreen == nil ? NSScreen.main?.displayID : nil)
            case .settings: openSettings()
            }
        } catch {
            NSLog("Islet: bad URL %@: %@", url.absoluteString, String(describing: error))
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
