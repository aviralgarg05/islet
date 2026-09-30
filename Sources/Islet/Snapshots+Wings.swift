import AppKit
import IsletCore
import SwiftUI

@MainActor
extension Snapshots {
    /// `<dir>/wings.png`: the closed island at every wing width the menu bar can leave it
    /// (icon only, crowded, measured and roomy), with music, a waiting agent, a timer and a peek.
    static func renderWings(to dir: URL) {
        var settings = IsletSettings()
        settings.animationStyle = .off
        let model = AppModel(settings: settings)
        model.loadDemo(includeActivities: true)
        let now = Date()
        var center = ActivityCenter()
        func activity(_ spec: ActivitySpec) -> Activity { try! center.apply(spec, now: now) }
        let waiting = activity(ActivitySpec(id: "claude-a", source: "claude-code", title: "Claude · islet",
                                            subtitle: "Claude needs your permission to use Bash", icon: .symbol("sparkle"),
                                            trailing: "Waiting", state: .waiting, tint: "#D97757", priority: .high))
        let timer = activity(ActivitySpec(id: "tea", source: "timer", title: "Tea", icon: .symbol("timer"), tint: "orange",
                                          endsAt: now.addingTimeInterval(272)))
        let states: [(String, IslandPresentation, CGFloat)] = [
            ("music", .compact(.nowPlaying(model.nowPlaying!)), 44),
            ("agent waiting", .compact(.activity(waiting, others: 0)), 44),
            ("timer", .compact(.activity(timer, others: 0)), 44),
            ("peek", .sneak(waiting), 88),
        ]
        var rows: [(String, NSImage)] = []
        for wing in [MenuBarLayoutEngine.iconOnlyWing, 36, 42.5, 52] as [CGFloat] {
            let metrics = NotchGeometry.metrics(for: screen, expandedSize: CGSize(width: settings.expandedSize.width, height: settings.expandedSize.height),
                                                wingWidth: wing)
            model.closedPlacements[1] = ClosedPlacement(layout: .wings(left: wing, right: wing), leftSlack: .infinity, rightSlack: .infinity)
            for (label, presentation, height) in states {
                model.forcedPresentation = presentation
                let view = IslandView(model: model, display: 1, metrics: metrics)
                    .frame(width: 440, height: height, alignment: .top)
                    .background(backdrop(metrics: metrics))
                    .clipped()
                let renderer = ImageRenderer(content: view.environment(\.colorScheme, .dark).environment(\.snapshotMode, true))
                renderer.scale = 2
                if let img = renderer.nsImage { rows.append(("\(label) · \(wing.formatted()) pt wings", img)) }
            }
        }
        let sheet = VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                Text(row.0)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.85))
                    .padding(.horizontal, 8)
                    .frame(maxWidth: .infinity, minHeight: 20, alignment: .leading)
                    .background(Color(white: 0.12))
                Image(nsImage: row.1)
            }
        }
        .frame(width: 440)
        write(sheet, to: dir.appendingPathComponent("wings.png"))
    }
}
