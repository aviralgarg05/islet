import AppKit
import IsletCore
import SwiftUI

/// `Islet --snapshot <dir>` also writes `<dir>/readme/`: the images the README shows, built from
/// the same views as the app so they can't drift from it.
@MainActor
extension Snapshots {
    static func renderReadme(to dir: URL) {
        let out = dir.appendingPathComponent("readme")
        try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        var settings = IsletSettings()
        settings.animationStyle = .off
        let model = AppModel(settings: settings)
        model.loadDemo(includeActivities: true)
        let metrics = NotchGeometry.metrics(for: screen, expandedSize: CGSize(width: settings.expandedSize.width, height: settings.expandedSize.height),
                                            wingWidth: settings.effectiveWingWidth)
        let now = Date()
        var center = ActivityCenter()
        func activity(_ spec: ActivitySpec) -> Activity { try! center.apply(spec, now: now) }

        let ride = activity(ActivitySpec(
            id: "ride", source: MenuBarLiveActivities.source, title: "Uber", subtitle: "Grey Prius · 7ABC123",
            icon: .symbol("car.fill"), state: .running, tint: "#FFFFFF", endsAt: now.addingTimeInterval(4 * 60 + 20)
        ).with { $0.template = "eta"; $0.trackerIcon = .symbol("car.fill"); $0.phase = "enroute" })
        let score = activity(ActivitySpec(id: "score", source: "sports", title: "Lakers at Celtics", subtitle: "Tatum makes 3-pt jump shot",
                                          icon: .symbol("sportscourt.fill"), state: .running, tint: "#FDB927")
            .with {
                $0.template = "score"
                $0.period = "Q4 2:31"
                $0.teams = [ActivityTeam(abbr: "LAL", name: "Lakers", score: "102", tint: "#FDB927"),
                            ActivityTeam(abbr: "BOS", name: "Celtics", score: "98", tint: "#007A33")]
            })
        let waiting = activity(ActivitySpec(id: "claude-a", source: "claude-code", title: "Claude · islet",
                                            subtitle: "Claude needs your permission to use Bash", icon: .symbol("sparkle"),
                                            trailing: "Waiting", state: .waiting, tint: "#D97757", priority: .high))
        let timer = activity(ActivitySpec(id: "tea", source: "timer", title: "Tea", icon: .symbol("timer"), tint: "orange",
                                          endsAt: now.addingTimeInterval(272)))
        let plan = activity(ActivitySpec(id: "plan", source: "claude-code", title: "Claude · islet", subtitle: "Writing tests",
                                         icon: .symbol("sparkles"), state: .running, tint: "#D97757", steps: 5, step: 3))
        let usage = activity(ActivitySpec(id: "usage", source: "agent-usage", title: "Claude 5-hour limit at 90%",
                                          subtitle: "Resets 16:40", icon: .symbol("sparkle"), state: .warning, tint: "#FF9F0A"))

        let rows: [(String, IslandPresentation, CGFloat)] = [
            ("Music playing, with other activities in bubbles", .compact(.nowPlaying(model.nowPlaying!)), 42),
            ("A ride from your iPhone, mirrored from the menu bar", .compact(.activity(ride, others: 0)), 42),
            ("A live score", .compact(.activity(score, others: 0)), 42),
            ("A coding agent waiting for you", .compact(.activity(waiting, others: 0)), 42),
            ("A timer", .compact(.activity(timer, others: 0)), 42),
            ("An agent's plan, step 3 of 5", .sneak(plan), 100),
            ("A usage limit alert", .sneak(usage), 98),
        ]
        model.closedPlacements[1] = ClosedPlacement(wing: metrics.wingWidth, slack: .infinity)
        var images: [(String, NSImage)] = []
        for (caption, presentation, height) in rows {
            model.forcedPresentation = presentation
            let view = IslandView(model: model, display: 1, metrics: metrics)
                .frame(width: 500, height: height, alignment: .top)
                .background(backdrop(metrics: metrics))
                .clipped()
            if let image = image(view) { images.append((caption, image)) }
        }
        let sheet = VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(images.enumerated()), id: \.offset) { _, row in
                Text(row.0)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.85))
                    .padding(.horizontal, 8)
                    .frame(maxWidth: .infinity, minHeight: 22, alignment: .leading)
                    .background(Color(white: 0.12))
                Image(nsImage: row.1)
            }
        }
        .frame(width: 500)
        write(sheet, to: out.appendingPathComponent("closed-states.png"))

        // The expanded island at each size, on Home.
        model.closedPlacements[1] = nil
        model.forcedPresentation = .expanded
        model.tab = .home
        for (name, preset) in [("expanded-home", SizePreset.standard), ("expanded-compact", .compact), ("expanded-large", .large)] {
            model.settings.sizePreset = preset
            let m = NotchGeometry.metrics(for: screen, expandedSize: CGSize(width: model.settings.expandedSize.width, height: model.settings.expandedSize.height),
                                          wingWidth: model.settings.effectiveWingWidth)
            let view = IslandView(model: model, display: 1, metrics: m)
                .frame(width: 760, height: m.expanded.height + 30)
                .background(backdrop(metrics: m))
            write(view, to: out.appendingPathComponent("\(name).png"))
        }
    }

    private static func image<V: View>(_ view: V) -> NSImage? {
        let renderer = ImageRenderer(content: view.environment(\.colorScheme, .dark).environment(\.snapshotMode, true))
        renderer.scale = 2
        return renderer.nsImage
    }
}

private extension ActivitySpec {
    func with(_ change: (inout ActivitySpec) -> Void) -> ActivitySpec {
        var copy = self
        change(&copy)
        return copy
    }
}
