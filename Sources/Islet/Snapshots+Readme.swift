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
                                         icon: .symbol("sparkle"), state: .running, tint: "#D97757", steps: 5, step: 3))
        // The alert as the app makes it: Claude's mark in its own colour, the share used in the wing.
        let alert = UsageAlert(provider: .claude, window: UsageWindow(id: "five_hour", usedPercent: 90, windowMinutes: 300,
                                                                      resetsAt: now.addingTimeInterval(72 * 60)), threshold: 90)
        let usage = activity(alert.activity(now: now))

        // Three states, not every state. Beside a notch the compact island has room for an icon
        // and a value, so a ride, a score and a timer all look alike there; one of each kind says
        // more than a sheet of them, and the pages they live on are where the detail belongs.
        _ = (score, timer, waiting, usage)
        let rows: [(String, IslandPresentation, CGFloat)] = [
            ("Music, with everything else in bubbles", .compact(.nowPlaying(model.nowPlaying!)), 42),
            ("A ride from your iPhone", .compact(.activity(ride, others: 0)), 42),
            ("An agent's plan, step 3 of 5", .sneak(plan), 100),
        ]
        model.closedPlacements[1] = ClosedPlacement(wing: metrics.wingWidth, slack: .infinity)
        var images: [(String, NSImage)] = []
        for (caption, presentation, height) in rows {
            model.forcedPresentation = presentation
            // Room below the island so it sits in the strip rather than being cut off by it.
            let view = IslandView(model: model, display: 1, metrics: metrics)
                .frame(width: Readme.strip, height: height + Readme.room, alignment: .top)
                .background(readmeBackdrop(metrics: metrics))
                .clipped()
            if let image = image(view) { images.append((caption, image)) }
        }
        // One state to a card, each the same width, with the caption quiet above it. The space
        // between them is what makes a list of seven things read calmly.
        let sheet = VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(images.enumerated()), id: \.offset) { index, row in
                Text(row.0)
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.45))
                    .padding(.top, index == 0 ? 0 : 26)
                    .padding(.bottom, 9)
                Image(nsImage: row.1).clipShape(RoundedRectangle(cornerRadius: Readme.corner, style: .continuous))
            }
        }
        .padding(Readme.margin)
        .frame(width: Readme.strip + Readme.margin * 2, alignment: .leading)
        .background(Readme.page)
        writeOpaque(sheet, to: out.appendingPathComponent("closed-states.png"))

        // The expanded island at each size, on Home.
        model.closedPlacements[1] = nil
        model.forcedPresentation = .expanded
        model.tab = .home
        for (name, preset) in [("expanded-home", SizePreset.standard), ("expanded-compact", .compact), ("expanded-large", .large)] {
            model.settings.sizePreset = preset
            let m = NotchGeometry.metrics(for: screen, expandedSize: CGSize(width: model.settings.expandedSize.width, height: model.settings.expandedSize.height),
                                          wingWidth: model.settings.effectiveWingWidth)
            // Wider than the island and taller than it needs, so it has somewhere to sit.
            let view = IslandView(model: model, display: 1, metrics: m)
                .frame(width: m.expanded.width + 240, height: m.expanded.height + 38 + PageSwitcher.band, alignment: .top)
                .background(readmeBackdrop(metrics: m))
                .clipShape(RoundedRectangle(cornerRadius: Readme.corner, style: .continuous))
                .padding(Readme.margin)
                .background(Readme.page)
            writeOpaque(view, to: out.appendingPathComponent("\(name).png"))
        }
    }

    /// The README's images are drawn on an opaque page, so they are rendered without an alpha
    /// channel: a third off the file a stranger downloads before reading a word.
    static func writeOpaque<V: View>(_ view: V, to url: URL) {
        let renderer = ImageRenderer(content: view.environment(\.colorScheme, .dark).environment(\.snapshotMode, true))
        renderer.scale = 2
        renderer.isOpaque = true
        guard let image = renderer.nsImage, let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else { return write(view, to: url) }
        try? png.write(to: url)
    }

    private static func image<V: View>(_ view: V) -> NSImage? {
        let renderer = ImageRenderer(content: view.environment(\.colorScheme, .dark).environment(\.snapshotMode, true))
        renderer.scale = 2
        return renderer.nsImage
    }
}

/// The look of the README's pictures: one page colour, one card radius, one margin, and a
/// backdrop quiet enough that the island is the thing you look at. Kept here rather than in the
/// island's own styles because it describes the page the pictures sit on, not the app.
enum Readme {
    static let page = Color(red: 0.055, green: 0.055, blue: 0.063)
    static let corner: CGFloat = 12
    static let margin: CGFloat = 22
    /// How wide one closed-island card is, and how much room the island is given below it.
    static let strip: CGFloat = 560
    static let room: CGFloat = 9
}

@MainActor
extension Snapshots {
    /// A desktop behind the island. Nearly one colour, a little lighter at the top as a real
    /// wallpaper is under the menu bar, with a soft lift behind the island so it sits in light
    /// rather than on a stripe. Restraint is the point: the island is the only thing with hue in
    /// it, so the page it sits on should have almost none.
    static func readmeBackdrop(metrics: IslandMetrics) -> some View {
        ZStack(alignment: .top) {
            LinearGradient(colors: [Color(red: 0.227, green: 0.247, blue: 0.298), Color(red: 0.133, green: 0.145, blue: 0.180)],
                           startPoint: .top, endPoint: .bottom)
            RadialGradient(colors: [Color.white.opacity(0.07), Color.white.opacity(0)],
                           center: .top, startRadius: 0, endRadius: 320)
            Rectangle().fill(Color.white.opacity(0.05)).frame(height: metrics.notch.height)
            UnevenRoundedRectangle(bottomLeadingRadius: 8, bottomTrailingRadius: 8)
                .fill(Color.black)
                .frame(width: metrics.notch.width, height: metrics.notch.height)
        }
    }
}

private extension ActivitySpec {
    func with(_ change: (inout ActivitySpec) -> Void) -> ActivitySpec {
        var copy = self
        change(&copy)
        return copy
    }
}
