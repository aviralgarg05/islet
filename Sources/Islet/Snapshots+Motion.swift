import AppKit
import IsletCore
import SwiftUI

/// `Islet --snapshot-motion <dir>`: the island's transitions as contact sheets, one per
/// transition, each frame frozen at a point of the way through (0, 0.15, 0.3, 0.5, 0.7, 0.85
/// and 1 of its length). Snapshots can't run animations, so each frame drives the island by
/// an explicit time through `IslandView(frame:)`: the same views and the same transition
/// modifiers, with their progress worked out by `IslandMotion`, the maths the live springs
/// and fades use. Read the sheets for gaps, jumps, clipped content and goo left behind.
@MainActor
extension Snapshots {
    /// Where each frame sits in its transition.
    static let motionSteps: [Double] = [0, 0.15, 0.3, 0.5, 0.7, 0.85, 1]

    /// One transition: where it starts and ends, how long it takes and which part of the
    /// island to show.
    struct MotionStrip {
        var title: String
        var from: IslandPresentation
        var to: IslandPresentation
        var fromBubbles: BubbleSet? = nil
        var toBubbles: BubbleSet? = nil
        var duration: Double
        var height: CGFloat
        /// The part of the 760-point-wide frame to show (nil: all of it).
        var crop: ClosedRange<CGFloat>? = nil
        /// Snapshot times instead of `motionSteps` × `duration` (the first frames of a morph).
        var times: [Double]? = nil
        /// The display (nil: the 14-inch MacBook Pro's built-in one).
        var screen: ScreenDescriptor? = nil
        var notchless: NotchlessStyle = .notch
        /// The closed pill is glass too ("Glass on displays without a notch").
        var glassPill = false
        /// The theme (nil: the default, Glass).
        var theme: IslandTheme? = nil
    }

    static func renderMotion(to dir: URL) {
        _ = NSApplication.shared
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        Motion.pace = 1
        var settings = IsletSettings()
        settings.animationStyle = .fluid
        settings.reduceMotion = false
        settings.clipboardEnabled = true
        settings.remindersEnabled = true
        let model = AppModel(settings: settings)
        model.loadDemo(includeActivities: true)
        model.tab = .home
        let now = Date()
        var center = ActivityCenter()
        func activity(_ spec: ActivitySpec) -> Activity { try! center.apply(spec, now: now) }
        guard let np = model.nowPlaying else { return }
        let waiting = activity(ActivitySpec(id: "claude-a", source: "claude-code", title: "Claude · islet",
                                            subtitle: "Claude needs your permission to use Bash", icon: .symbol("sparkle"),
                                            trailing: "Waiting", state: .waiting, tint: "#D97757", priority: .high))
        let timer = activity(ActivitySpec(id: "tea", source: "timer", title: "Tea", icon: .symbol("timer"), tint: "orange",
                                          endsAt: now.addingTimeInterval(272)))
        let build = model.activities.first { $0.id == "build" }
        let agent = model.activities.first { $0.id == "claude-demo" }
        let bubbleA = build.map(IslandBubble.activity)
        let bubbleB = agent.map(IslandBubble.activity)
        func set(_ items: [IslandBubble?]) -> BubbleSet { BubbleSet(items: items.compactMap { $0 }, overflow: 0) }

        let media = IslandPresentation.compact(.nowPlaying(np))
        let bubbleCrop: ClosedRange<CGFloat> = 470...640
        let rowCrop: ClosedRange<CGFloat> = 190...570

        sheet("motion-bubble-split", zoom: 3, model: model, dir: dir, strips: [
            MotionStrip(title: "First bubble buds off", from: media, to: media, fromBubbles: set([]), toBubbles: set([bubbleA]),
                        duration: IslandMotion.splitDuration, height: 44, crop: bubbleCrop),
            MotionStrip(title: "Second bubble buds off", from: media, to: media, fromBubbles: set([bubbleA]),
                        toBubbles: set([bubbleA, bubbleB]), duration: IslandMotion.splitDuration, height: 44, crop: bubbleCrop),
            MotionStrip(title: "No notch, floating pill: first bubble buds off", from: media, to: media, fromBubbles: set([]),
                        toBubbles: set([bubbleA]), duration: IslandMotion.splitDuration, height: 44, crop: bubbleCrop,
                        screen: notchlessScreen, notchless: .pill),
            MotionStrip(title: "No notch, glass pill: first bubble buds off", from: media, to: media, fromBubbles: set([]),
                        toBubbles: set([bubbleA]), duration: IslandMotion.splitDuration, height: 44, crop: bubbleCrop,
                        screen: notchlessScreen, notchless: .pill, glassPill: true),
        ])
        sheet("motion-bubble-merge", zoom: 3, model: model, dir: dir, strips: [
            MotionStrip(title: "Last bubble absorbed", from: media, to: media, fromBubbles: set([bubbleA]), toBubbles: set([]),
                        duration: IslandMotion.mergeDuration, height: 44, crop: bubbleCrop),
            MotionStrip(title: "Outer bubble absorbed", from: media, to: media, fromBubbles: set([bubbleA, bubbleB]),
                        toBubbles: set([bubbleA]), duration: IslandMotion.mergeDuration, height: 44, crop: bubbleCrop),
        ])
        let open = metricsFor(model.settings, screen: screen).expanded.height + 30 + PageSwitcher.band
        sheet("motion-open", zoom: 1, model: model, dir: dir, strips: [
            MotionStrip(title: "Open from music, with two bubbles", from: media, to: .expanded, duration: 0.7, height: open),
        ])
        // The first frames of a close, where the black comes back over the glass (or the grey):
        // it covers the whole shape evenly, so the island shrinks into the notch as one shape.
        let closing: [Double] = [0, 0.02, 0.04, 0.06, 0.08, 0.1, 0.15, 0.3]
        sheet("motion-close", zoom: 1, model: model, dir: dir, strips: [
            MotionStrip(title: "Close to music; the bubbles bud off once the shell has closed", from: .expanded, to: media,
                        duration: 1.0, height: open),
            MotionStrip(title: "Glass: the first frames of the close", from: .expanded, to: media,
                        duration: 1.0, height: open, times: closing),
            MotionStrip(title: "Graphite: the first frames of the close", from: .expanded, to: media,
                        duration: 1.0, height: open, times: closing, theme: .graphite),
        ])
        sheet("motion-sneak-in", zoom: 2, model: model, dir: dir, strips: [
            MotionStrip(title: "Sneak peek of the waiting agent", from: .compact(.activity(waiting, others: 0)), to: .sneak(waiting),
                        fromBubbles: set([]), toBubbles: set([]), duration: 0.65, height: 92, crop: rowCrop),
            MotionStrip(title: "Sneak peek from the closed notch", from: .idle, to: .sneak(waiting),
                        duration: 0.65, height: 92, crop: rowCrop),
        ])
        sheet("motion-song-peek-in", zoom: 2, model: model, dir: dir, strips: [
            MotionStrip(title: "Song peek from music", from: media, to: .songPeek(np), fromBubbles: set([]), toBubbles: set([]),
                        duration: 0.65, height: 92, crop: rowCrop),
        ])
        // An activity growing out of the closed notch and going back into it. It grows on the open
        // spring alone, so its wings stay clear of the menu bar items beside them, and closing
        // pulls in a touch as a whole, never inside the notch, staying one shape in the row.
        let waitingCompact = IslandPresentation.compact(.activity(waiting, others: 0))
        sheet("motion-appear", zoom: 2, model: model, dir: dir, strips: [
            MotionStrip(title: "An activity grows out of the notch", from: .idle, to: waitingCompact,
                        fromBubbles: set([]), toBubbles: set([]), duration: 0.7, height: 44, crop: rowCrop),
            MotionStrip(title: "And goes back into it", from: waitingCompact, to: .idle,
                        fromBubbles: set([]), toBubbles: set([]), duration: 0.7, height: 44, crop: rowCrop),
            MotionStrip(title: "No notch, floating pill: an activity appears", from: .idle, to: waitingCompact,
                        fromBubbles: set([]), toBubbles: set([]), duration: 0.7, height: 44, crop: rowCrop,
                        screen: notchlessScreen, notchless: .pill),
        ])
        sheet("motion-glyph-morph", zoom: 3, model: model, dir: dir, strips: [
            MotionStrip(title: "Music gives way to a timer: the glyph bounces in, the equaliser morphs into the time",
                        from: media, to: .compact(.activity(timer, others: 0)), fromBubbles: set([]), toBubbles: set([]),
                        duration: 0.5, height: 44, crop: 230...530),
            MotionStrip(title: "A waiting agent gives way to a timer", from: .compact(.activity(waiting, others: 0)),
                        to: .compact(.activity(timer, others: 0)), fromBubbles: set([]), toBubbles: set([]),
                        duration: 0.5, height: 44, crop: 230...530),
        ])
        // The first frames of the compact-to-peek morph, close up on the shoulder: they must
        // never show square "ears" under the row, with or without a notch.
        let early: [Double] = [0, 0.01, 0.02, 0.035, 0.05, 0.08, 0.12, 0.2, 0.7]
        sheet("motion-peek-shoulders", zoom: 4, model: model, dir: dir, strips: [
            MotionStrip(title: "Notch: compact to peek", from: media, to: .songPeek(np), fromBubbles: set([]), toBubbles: set([]),
                        duration: 0.7, height: 84, crop: 220...330, times: early),
            MotionStrip(title: "No notch, floating pill: compact to peek", from: media, to: .songPeek(np),
                        fromBubbles: set([]), toBubbles: set([]), duration: 0.7, height: 84, crop: 220...330, times: early,
                        screen: notchlessScreen, notchless: .pill),
        ])
        print("Rendered motion contact sheets to \(dir.path)")
    }

    private static func metricsFor(_ s: IsletSettings, screen: ScreenDescriptor, notchless: NotchlessStyle = .notch) -> IslandMetrics {
        NotchGeometry.metrics(for: screen, expandedSize: CGSize(width: s.expandedSize.width, height: s.expandedSize.height),
                              wingWidth: s.effectiveWingWidth, adjust: s.notchAdjust, notchless: notchless)
    }

    /// Renders each strip's frames and stacks them, labelled, into `<dir>/<name>.png`.
    private static func sheet(_ name: String, zoom: CGFloat, model: AppModel, dir: URL, strips: [MotionStrip]) {
        var rows: [(label: String, image: NSImage, size: CGSize)] = []
        let saved = model.settings
        defer {
            model.settings = saved
            model.closedPlacements = [:]
        }
        for strip in strips {
            model.settings.notchlessStyle = strip.notchless
            model.settings.glassOnNotchless = strip.glassPill
            // Each strip in its own theme: none carries over from the strip before.
            model.settings.theme = strip.glassPill ? .glass : strip.theme ?? saved.theme
            let display = strip.screen ?? screen
            let metrics = metricsFor(model.settings, screen: display, notchless: strip.notchless)
            model.closedPlacements[display.id] = ClosedPlacement(wing: metrics.wingWidth, slack: .infinity)
            model.forcedPresentation = strip.to
            let times = strip.times ?? motionSteps.map { $0 * strip.duration }
            for (i, t) in times.enumerated() {
                let frame = MotionFrame(from: strip.from, t: t, fromBubbles: strip.fromBubbles, toBubbles: strip.toBubbles)
                let crop = strip.crop ?? 0...760
                let backdrop = Group {
                    if metrics.isSynthetic { notchlessBackdrop(metrics: metrics) } else { Snapshots.backdrop(metrics: metrics) }
                }
                let island = IslandView(model: model, display: display.id, metrics: metrics, frame: frame)
                    .frame(width: 760, height: strip.height, alignment: .top)
                    .background(backdrop)
                    .offset(x: -crop.lowerBound)
                    .frame(width: crop.upperBound - crop.lowerBound, height: strip.height, alignment: .topLeading)
                    .clipped()
                let renderer = ImageRenderer(content: island.environment(\.colorScheme, .dark).environment(\.snapshotMode, true))
                renderer.scale = zoom * 2
                guard let image = renderer.nsImage else { continue }
                let size = CGSize(width: (crop.upperBound - crop.lowerBound) * zoom, height: strip.height * zoom)
                let step = strip.times == nil ? String(format: "%.2f", motionSteps[i]) : "frame \(i + 1)"
                let label = i == 0 ? "\(strip.title) · \(step) · \(String(format: "%.3f", t)) s"
                                   : "\(step) · \(String(format: "%.3f", t)) s"
                rows.append((label, image, size))
            }
        }
        let sheet = VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                Text(row.label)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.85))
                    .padding(.horizontal, 8)
                    .frame(maxWidth: .infinity, minHeight: 18, alignment: .leading)
                    .background(Color(white: 0.12))
                Image(nsImage: row.image)
                    .resizable()
                    .frame(width: row.size.width, height: row.size.height)
            }
        }
        .frame(width: max(320, rows.map(\.size.width).max() ?? 0))
        write(sheet, to: dir.appendingPathComponent("\(name).png"))
    }
}
