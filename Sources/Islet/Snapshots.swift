import AppKit
import IsletCore
import IsletSystem
import SwiftUI

/// `Islet --snapshot <dir>` renders every island state to PNG, using demo data and the
/// geometry of a 14" MacBook Pro. Used for visual review and for the README.
@MainActor
enum Snapshots {
    static let screen = ScreenDescriptor(
        id: 1, name: "Built-in", frame: CGRect(x: 0, y: 0, width: 1512, height: 982),
        safeAreaTop: 32, auxiliaryLeftWidth: 663.5, auxiliaryRightWidth: 663.5, menuBarHeight: 33, isBuiltIn: true
    )

    static func render(to dir: URL) {
        _ = NSApplication.shared
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        var settings = IsletSettings()
        settings.clipboardEnabled = true
        settings.remindersEnabled = true
        // Static renders: no transitions, so nothing is captured mid-animation.
        settings.animationStyle = .off
        let model = AppModel(settings: settings)
        model.loadDemo(includeActivities: true)
        func metricsFor(_ s: IsletSettings) -> IslandMetrics {
            NotchGeometry.metrics(for: screen, expandedSize: CGSize(width: s.expandedSize.width, height: s.expandedSize.height),
                                  wingWidth: s.effectiveWingWidth)
        }
        var metrics = metricsFor(settings)
        let now = Date()
        var center = ActivityCenter()

        func activity(_ spec: ActivitySpec) -> Activity { try! center.apply(spec, now: now) }

        let waiting = activity(ActivitySpec(id: "claude-a", source: "claude-code", title: "Claude · islet",
                                            subtitle: "Claude needs your permission to use Bash", icon: .symbol("sparkle"),
                                            trailing: "Waiting", state: .waiting, tint: "#D97757", priority: .high))
        let build = activity(ActivitySpec(id: "build", source: "ci", title: "Release build", subtitle: "Compiling 142/310",
                                          icon: .symbol("hammer.fill"), progress: 0.46, state: .running, tint: "orange"))
        let timer = activity(ActivitySpec(id: "tea", source: "timer", title: "Tea", icon: .symbol("timer"), tint: "orange",
                                          endsAt: now.addingTimeInterval(272)))
        let done = activity(ActivitySpec(id: "deploy", source: "ci", title: "Deploy to production", subtitle: "Finished in 3:12",
                                         icon: .symbol("checkmark.circle.fill"), trailing: "Done", progress: 1, state: .success))
        let battery = BatteryEvent(kind: .pluggedIn, state: BatteryState(level: 76, isCharging: true, isPluggedIn: true, adapterWatts: 96), until: now.addingTimeInterval(3))

        model.setPlugins([
            PluginResult(path: "/p/uptime.1m.sh", name: "uptime", interval: 60,
                         output: ScriptPlugins.parse("⏱ Up 3 days | sfimage=clock\n---\nActivity Monitor | shell=/usr/bin/open"), lastRun: now),
            PluginResult(path: "/p/github.5m.sh", name: "github", interval: 300,
                         output: ScriptPlugins.parse("3 PRs need review | sfimage=arrow.triangle.pull color=#3FB950\n---\nFix login flow | href=https://example.com\nBump deps | href=https://example.com"), lastRun: now),
            PluginResult(path: "/p/disk.10m.sh", name: "disk", interval: 600,
                         output: ScriptPlugins.parse("Disk: 212 GB free | sfimage=internaldrive"), lastRun: now),
        ])

        let states: [(String, IslandPresentation, IslandTab)] = [
            ("01-compact-media", .compact(.nowPlaying(model.nowPlaying!)), .home),
            ("02-compact-agent-waiting", .compact(.activity(waiting, others: 2)), .home),
            ("03-compact-progress", .compact(.activity(build, others: 0)), .home),
            ("04-compact-timer", .compact(.activity(timer, others: 0)), .home),
            ("05-compact-battery", .compact(.battery(battery)), .home),
            ("06-hud-volume", .hud(HUDEvent(kind: .volume, value: 0.62, until: now.addingTimeInterval(2))), .home),
            ("07-hud-brightness", .hud(HUDEvent(kind: .brightness, value: 0.35, until: now.addingTimeInterval(2))), .home),
            ("08-sneak-agent", .sneak(waiting), .home),
            ("09-sneak-done", .sneak(done), .home),
            ("10-expanded-home", .expanded, .home),
            ("11-expanded-shelf", .expanded, .shelf),
            ("11b-expanded-today", .expanded, .today),
            ("12-expanded-widgets", .expanded, .widgets),
            ("13-expanded-clipboard", .expanded, .clipboard),
            ("14-expanded-stats", .expanded, .stats),
        ]

        func shoot(_ name: String) {
            let view = IslandView(model: model, display: 1, metrics: metrics)
                .frame(width: 760, height: metrics.expanded.height + 30)
                .background(Snapshots.backdrop(metrics: metrics))
            write(view, to: dir.appendingPathComponent("\(name).png"))
        }

        for (name, presentation, tab) in states {
            model.forcedPresentation = presentation
            model.tab = tab
            shoot(name)
        }

        // The same closed states beside the notch, as used when the menu bar has room.
        model.closedPlacements[1] = ClosedPlacement(layout: .wings(left: metrics.wingWidth, right: metrics.wingWidth),
                                                    leftSlack: .infinity, rightSlack: .infinity)
        for (name, presentation, tab) in states where !name.contains("expanded") {
            model.forcedPresentation = presentation
            model.tab = tab
            shoot("w" + name)
        }
        // Icon-only wings (a crowded menu bar) and the pill below the notch (no room at all).
        for (prefix, layout) in [("i", ClosedLayout.wings(left: MenuBarLayoutEngine.iconOnlyWing, right: MenuBarLayoutEngine.iconOnlyWing)),
                                 ("d", ClosedLayout.drop)] {
            model.closedPlacements[1] = ClosedPlacement(layout: layout, leftSlack: 0, rightSlack: 0)
            for (name, presentation, tab) in states where !name.contains("expanded") && !name.contains("sneak") {
                model.forcedPresentation = presentation
                model.tab = tab
                shoot(prefix + name)
            }
        }
        model.closedPlacements[1] = nil

        // A call with a live count-up timer, and the urgent glow on a failed deploy.
        let call = activity(ActivitySpec(id: "call", source: "com.apple.FaceTime", title: "FaceTime", subtitle: "Mom",
                                         icon: .symbol("phone.fill"), state: .running, tint: "green", startedAt: now.addingTimeInterval(-754)))
        model.forcedPresentation = .compact(.activity(call, others: 0))
        shoot("16-compact-call")
        let failed = activity(ActivitySpec(id: "ci", source: "github-actions", title: "CI failed on main", subtitle: "3 tests failed",
                                           state: .failure, priority: .high))
        model.forcedPresentation = .sneak(failed)
        shoot("17-sneak-failure-glow")

        // Agent plan with segmented steps, and a mirrored notification.
        let plan = activity(ActivitySpec(id: "plan", source: "claude-code", title: "Claude · islet", subtitle: "Step 3 of 5 · Writing tests",
                                         state: .running, steps: 5, step: 3))
        model.forcedPresentation = .sneak(plan)
        shoot("20-sneak-steps")
        let notif = MirroredNotification(appName: "Messages", bundleID: "com.apple.MobileSMS", title: "Alice", body: "Running 5 min late, order me a flat white?")
        model.forcedPresentation = .sneak(activity(notif.activity(rule: nil)))
        shoot("21-sneak-notification")

        // Themes and sizes.
        model.forcedPresentation = .expanded
        model.tab = .home
        model.settings.theme = .graphite
        shoot("18-expanded-graphite")
        model.settings.theme = .glass
        shoot("18b-expanded-glass")
        model.settings.theme = .black
        model.settings.sizePreset = .large
        metrics = metricsFor(model.settings)
        shoot("19-expanded-large")
        model.settings.sizePreset = .compact
        metrics = metricsFor(model.settings)
        renderTimers(model: model, now: now, shoot: shoot) { model.settings.sizePreset = $0; metrics = metricsFor(model.settings) }

        // Now Playing controls: the volume row on a short card, the roomy layout, and keep awake.
        model.controls.outputs = [
            AudioOutputDevice(id: 1, uid: "builtin", name: "MacBook Pro Speakers", transport: .builtIn),
            AudioOutputDevice(id: 2, uid: "airpods", name: "AirPods Pro", transport: .bluetooth),
        ]
        model.controls.defaultOutputID = 2
        model.controls.volume = 0.62
        model.controls.soundRowShown = true
        shoot("22-expanded-media-sound")
        model.controls.soundRowShown = false
        model.settings.sizePreset = .standard
        metrics = metricsFor(model.settings)
        shoot("23-expanded-media-standard")
        model.settings.sizePreset = .compact
        metrics = metricsFor(model.settings)
        let awake = KeepAwakeSession(since: now, until: now.addingTimeInterval(2 * 3600))
        model.controls.awake = awake
        let awakeActivity = activity(KeepAwake.activity(for: awake, sneak: false) { _ in "18:30" })
        model.forcedPresentation = .compact(.activity(awakeActivity, others: 0))
        shoot("24-compact-keep-awake")
        model.closedPlacements[1] = ClosedPlacement(layout: .wings(left: metrics.wingWidth, right: metrics.wingWidth),
                                                    leftSlack: .infinity, rightSlack: .infinity)
        shoot("w24-compact-keep-awake")
        model.closedPlacements[1] = nil
        model.forcedPresentation = .expanded
        shoot("25-expanded-keep-awake-on")
        model.controls.awake = nil

        // Home without media shows the Today card.
        model.clearNowPlayingForSnapshot()
        shoot("15-expanded-today")

        // Agent plan limits on Home, and the alert when a window crosses 90%.
        model.agentUsage.showDemo(now: now)
        model.settings.calendarEnabled = false
        model.remove(activityID: "build")
        model.settings.sizePreset = .standard
        metrics = metricsFor(model.settings)
        shoot("22-expanded-agents")
        model.remove(activityID: "claude-demo")
        model.settings.sizePreset = .compact
        metrics = metricsFor(model.settings)
        shoot("23-expanded-agents-compact")
        let crossing = UsageAlert(provider: .claude, window: UsageWindow(id: "five_hour", usedPercent: 90, windowMinutes: 300,
                                                                         resetsAt: now.addingTimeInterval(72 * 60)), threshold: 90)
        let usageAlert = activity(crossing.activity(now: now))
        model.forcedPresentation = .sneak(usageAlert)
        shoot("24-sneak-usage-alert")
        model.forcedPresentation = .compact(.activity(usageAlert, others: 0))
        shoot("25-compact-usage-alert")
        TemplateSnapshots.render(to: dir, model: model)
        renderApprovals(model: model, shoot: shoot)
        print("Rendered snapshots to \(dir.path)")
    }

    /// A wallpaper-ish backdrop with a menu bar strip and the hardware notch, so the
    /// island's edges are visible in the images.
    static func backdrop(metrics: IslandMetrics) -> some View {
        ZStack(alignment: .top) {
            LinearGradient(colors: [Color(red: 0.36, green: 0.42, blue: 0.62), Color(red: 0.62, green: 0.45, blue: 0.55)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            Rectangle().fill(Color.white.opacity(0.18)).frame(height: metrics.notch.height)
            UnevenRoundedRectangle(bottomLeadingRadius: 8, bottomTrailingRadius: 8)
                .fill(Color.black)
                .frame(width: metrics.notch.width, height: metrics.notch.height)
        }
    }

    static func write<V: View>(_ view: V, to url: URL) {
        let renderer = ImageRenderer(content: view.environment(\.colorScheme, .dark).environment(\.snapshotMode, true))
        renderer.scale = 2
        guard let image = renderer.nsImage, let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff), let png = rep.representation(using: .png, properties: [:]) else {
            print("failed to render \(url.lastPathComponent)")
            return
        }
        try? png.write(to: url)
    }
}
