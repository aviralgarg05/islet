import AppKit
import IsletCore
import SwiftUI

/// Layout of the island for each presentation. Shared by the view and the panel's hit-testing.
enum IslandLayout {
    static func size(for p: IslandPresentation, metrics m: IslandMetrics) -> CGSize {
        switch p {
        case .hidden, .idle: return m.notch
        case .compact, .hud: return m.compact
        case .sneak: return CGSize(width: max(m.compact.width + 40, 300), height: m.notch.height + 46)
        case .expanded: return m.expanded
        }
    }

    static func radii(for p: IslandPresentation, metrics m: IslandMetrics) -> (top: CGFloat, bottom: CGFloat) {
        switch p {
        case .expanded: return (10, 24)
        case .sneak: return (8, 20)
        default: return (6, min(12, m.notch.height / 2.4))
        }
    }

    /// Gap between the island and the second-activity bubble.
    static let bubbleGap: CGFloat = 6

    /// Whether anything is drawn (idle is invisible: the hardware notch is already there).
    static func isVisible(_ p: IslandPresentation) -> Bool {
        switch p {
        case .hidden, .idle: return false
        default: return true
        }
    }

    /// Changes only when the silhouette changes, so media ticks don't restart animations.
    static func key(_ p: IslandPresentation) -> String {
        switch p {
        case .hidden: return "hidden"
        case .idle: return "idle"
        case .hud: return "hud"
        case .sneak(let a): return "sneak-\(a.id)"
        case .compact(.nowPlaying): return "compact-media"
        case .compact(.activity(let a, _)): return "compact-\(a.id)"
        case .compact(.battery): return "compact-battery"
        case .expanded: return "expanded"
        }
    }
}

/// The detached circle that shows a second live activity next to the island (iPhone style).
enum IslandBubble: Equatable {
    case media(NowPlaying)
    case activity(Activity)

    var key: String {
        switch self {
        case .media: return "bubble-media"
        case .activity(let a): return "bubble-\(a.id)"
        }
    }
}

/// Extra activities shown as detached bubbles next to the island, and how many more exist.
struct BubbleSet: Equatable {
    var items: [IslandBubble]
    var overflow: Int

    static let none = BubbleSet(items: [], overflow: 0)
    var key: String { items.map(\.key).joined(separator: "|") + "+\(overflow)" }
}

extension AppModel {
    func bubbles(for p: IslandPresentation) -> BubbleSet {
        guard case .compact(let c) = p, settings.maxConcurrent > 1 else { return .none }
        var acts = activities
        var items: [IslandBubble] = []
        switch c {
        case .activity(let a, _):
            acts.removeAll { $0.id == a.id }
            if let np = nowPlaying, np.isPlaying, settings.mediaEnabled { items.append(.media(np)) }
        case .nowPlaying:
            break
        case .battery:
            return .none
        }
        items += acts.map(IslandBubble.activity)
        let room = settings.maxConcurrent - 1
        guard items.count > room else { return BubbleSet(items: items, overflow: 0) }
        return BubbleSet(items: Array(items.prefix(room)), overflow: items.count - room)
    }

    /// The activity the closed island is currently about, if any.
    func focusedActivity(for p: IslandPresentation) -> Activity? {
        switch p {
        case .compact(.activity(let a, _)), .sneak(let a): return a
        default: return nil
        }
    }
}

struct IslandView: View {
    let model: AppModel
    let display: CGDirectDisplayID
    let metrics: IslandMetrics
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.snapshotMode) private var snapshotMode
    @ViewState private var dropTargeted = false

    private var style: AnimationStyle {
        if model.settings.animationStyle == .off { return .off }
        return systemReduceMotion || model.settings.reduceMotion ? .minimal : model.settings.animationStyle
    }

    var body: some View {
        let p = model.presentation(for: display)
        let size = IslandLayout.size(for: p, metrics: metrics)
        let r = IslandLayout.radii(for: p, metrics: metrics)
        let visible = IslandLayout.isVisible(p) || dropTargeted
        let shape = IslandShape(topRadius: r.top, bottomRadius: r.bottom)
        let glow = model.urgentGlow(for: p)
        let bubbles = model.bubbles(for: p)
        let d = metrics.notch.height
        let left = model.settings.bubblePlacement == .left
        let stale = model.focusedActivity(for: p)?.isStale(at: Date()) ?? false

        HStack(alignment: .top, spacing: IslandLayout.bubbleGap) {
            // Bubbles on one side are balanced by invisible spacers on the other,
            // so the island itself stays centred on the notch.
            if left { bubbleViews(bubbles, diameter: d) } else { spacers(bubbles.items.count, diameter: d) }
            ZStack(alignment: .top) {
                if let glow {
                    if snapshotMode {
                        shape.fill(Color.black).shadow(color: glow.opacity(0.8), radius: 9)
                    } else {
                        GlowPulse(color: NSColor(glow), cornerRadius: r.bottom)
                            .frame(width: size.width + 2 * r.top, height: size.height)
                    }
                }
                model.settings.theme.background(expanded: p == .expanded, shape: shape)
                    .shadow(color: .black.opacity(p == .expanded ? 0.5 : 0), radius: 16, y: 8)
                content(p)
                    .opacity(stale ? 0.55 : 1)
                    .padding(.horizontal, r.top)
                    .frame(width: size.width + 2 * r.top, height: size.height, alignment: .top)
                    .clipShape(shape)
                    .id(IslandLayout.key(p))
                    .transition(style.contentTransition)
            }
            .frame(width: size.width + 2 * r.top, height: size.height)
            .keyframeAnimator(initialValue: CGFloat(1), trigger: model.pulse) { view, scale in
                view.scaleEffect(scale, anchor: .top)
            } keyframes: { _ in
                if style.bounces && model.settings.bounceOnActivity {
                    SpringKeyframe(1.05, duration: 0.16, spring: .snappy)
                    SpringKeyframe(1.0, duration: 0.45, spring: .bouncy)
                } else {
                    LinearKeyframe(1.0, duration: 0.01)
                }
            }
            .contextMenu { islandMenu(p) }
            if left { spacers(bubbles.items.count, diameter: d) } else { bubbleViews(bubbles, diameter: d) }
        }
        .opacity(visible ? 1 : 0)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(IslandLayout.isVisible(p) ? style.morph : style.collapse, value: IslandLayout.key(p))
        .animation(style.morph, value: bubbles.key)
        .modifier(ShelfDropTarget(enabled: !snapshotMode && model.settings.shelfEnabled, targeted: $dropTargeted) { urls in
            model.addToShelf(urls)
        })
        .onChange(of: dropTargeted) { _, targeted in
            if targeted {
                model.select(tab: .shelf)
                model.setExpanded(display)
            }
        }
        .onChange(of: IslandLayout.key(p) + bubbles.key) { _, _ in
            NotificationCenter.default.post(name: .isletLayoutChanged, object: nil)
        }
        .fontDesign(model.settings.roundedFont ? .rounded : .default)
        .environment(\.colorScheme, .dark)
    }

    @ViewBuilder
    private func spacers(_ count: Int, diameter: CGFloat) -> some View {
        ForEach(0..<count, id: \.self) { _ in Color.clear.frame(width: diameter, height: 1) }
    }

    @ViewBuilder
    private func bubbleViews(_ set: BubbleSet, diameter: CGFloat) -> some View {
        ForEach(Array(set.items.enumerated()), id: \.element.key) { i, bubble in
            BubbleView(bubble: bubble, model: model, diameter: diameter,
                       overflow: i == set.items.count - 1 ? set.overflow : 0)
                .transition(bubbleTransition)
                .onTapGesture { model.setExpanded(display) }
                .contextMenu {
                    if case .activity(let a) = bubble {
                        Button("Dismiss") { model.remove(activityID: a.id) }
                        Button("Mute “\(a.source)”") { model.mute(source: a.source) }
                    }
                }
        }
    }

    /// Bubbles appear to pinch off the island: they start squeezed against its edge and
    /// slide out as they round up, and slide back in when they go.
    private var bubbleTransition: AnyTransition {
        guard style != .off, style != .minimal else { return .opacity }
        let left = model.settings.bubblePlacement == .left
        let edge: UnitPoint = left ? .trailing : .leading
        let tuck = CGFloat(left ? 26 : -26)
        return AnyTransition.modifier(
            active: Squash(x: 0.35, y: 0.6, anchor: edge),
            identity: Squash(x: 1, y: 1, anchor: edge)
        )
        .combined(with: .offset(x: tuck))
        .combined(with: .opacity)
    }

    /// Clicking an activity with a link opens it; anything else expands the island.
    private func activate(_ p: IslandPresentation) {
        Haptics.play(.tap)
        if let a = model.focusedActivity(for: p), let url = a.url {
            NSWorkspace.shared.open(url)
        } else {
            model.setExpanded(display)
        }
    }

    @ViewBuilder
    private func islandMenu(_ p: IslandPresentation) -> some View {
        if let a = model.focusedActivity(for: p) {
            if let url = a.url { Button("Open") { NSWorkspace.shared.open(url) } }
            Button("Dismiss “\(a.title)”") { model.remove(activityID: a.id) }
            Button("Mute “\(a.source)”") { model.mute(source: a.source) }
            Divider()
        }
        Button(model.expandedScreen == nil ? "Open Island" : "Close Island") {
            model.setExpanded(model.expandedScreen == nil ? display : nil)
        }
        Button("Settings…") { AppActions.openSettings() }
    }

    @ViewBuilder
    private func content(_ p: IslandPresentation) -> some View {
        switch p {
        case .hidden, .idle:
            Color.clear
        case .hud(let hud):
            HUDContent(hud: hud, metrics: metrics)
        case .compact(let c):
            CompactContentView(content: c, metrics: metrics, model: model)
                .contentShape(Rectangle())
                .onTapGesture { activate(p) }
        case .sneak(let a):
            SneakView(activity: a, metrics: metrics, model: model)
                .contentShape(Rectangle())
                .onTapGesture { activate(p) }
        case .expanded:
            ExpandedView(model: model, metrics: metrics, dropTargeted: dropTargeted)
        }
    }
}

/// Non-uniform scale used by the bubble "pinch off" transition.
struct Squash: ViewModifier {
    var x: CGFloat
    var y: CGFloat
    var anchor: UnitPoint

    func body(content: Content) -> some View {
        content.scaleEffect(x: x, y: y, anchor: anchor)
    }
}

struct BubbleView: View {
    let bubble: IslandBubble
    let model: AppModel
    let diameter: CGFloat
    var overflow = 0

    var body: some View {
        ZStack {
            Circle().fill(Color.black)
            switch bubble {
            case .media(let np):
                ArtworkView(media: np, size: diameter - 10, corner: (diameter - 10) / 2)
            case .activity(let a):
                if a.clampedProgress != nil || a.isIndeterminate, a.endsAt == nil, a.startedAt == nil {
                    ProgressRing(progress: a.clampedProgress, tint: model.tint(for: a), size: diameter - 10, lineWidth: 2.5)
                    IconView(icon: model.icon(for: a), size: diameter - 20, tint: model.tint(for: a))
                } else {
                    IconView(icon: model.icon(for: a), size: diameter - 14, tint: model.tint(for: a))
                }
            }
        }
        .frame(width: diameter, height: diameter)
        .overlay(alignment: .bottomTrailing) {
            if overflow > 0 {
                Text("+\(overflow)")
                    .font(.system(size: 8.5, weight: .heavy, design: .rounded))
                    .foregroundStyle(.black)
                    .padding(.horizontal, 3)
                    .background(Capsule().fill(Color.white))
                    .offset(x: 3, y: 2)
            }
        }
        .contentShape(Circle())
    }
}

func loadFileURLs(_ providers: [NSItemProvider], completion: @escaping ([URL]) -> Void) {
    let group = DispatchGroup()
    var urls: [URL] = []
    let lock = NSLock()
    for provider in providers where provider.hasItemConformingToTypeIdentifier("public.file-url") {
        group.enter()
        _ = provider.loadObject(ofClass: URL.self) { url, _ in
            if let url {
                lock.lock()
                urls.append(url)
                lock.unlock()
            }
            group.leave()
        }
    }
    group.notify(queue: .main) { if !urls.isEmpty { completion(urls) } }
}

// MARK: - Compact

/// Two "wings" either side of the notch.
struct Wings<Leading: View, Trailing: View>: View {
    let metrics: IslandMetrics
    @ViewBuilder var leading: Leading
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: 0) {
            leading
                .padding(.leading, 12)
                .frame(width: metrics.wingWidth, height: metrics.notch.height, alignment: .leading)
            Spacer(minLength: 0)
            trailing
                .padding(.trailing, 12)
                .frame(width: metrics.wingWidth, height: metrics.notch.height, alignment: .trailing)
        }
        .frame(width: metrics.compact.width, height: metrics.notch.height)
    }
}

struct CompactContentView: View {
    let content: CompactContent
    let metrics: IslandMetrics
    let model: AppModel

    var body: some View {
        switch content {
        case .nowPlaying(let np):
            Wings(metrics: metrics) {
                ArtworkView(media: np, size: min(22, metrics.notch.height - 8), corner: 5)
            } trailing: {
                PlayingIndicator(tint: model.mediaAccent(np), playing: np.isPlaying)
            }
        case .activity(let a, let others):
            let tint = model.tint(for: a)
            Wings(metrics: metrics) {
                HStack(spacing: 5) {
                    IconView(icon: model.icon(for: a), size: 16, tint: tint)
                    // With bubbles off, count the other activities here instead.
                    if others > 0, model.settings.maxConcurrent == 1 {
                        Text("+\(others)").font(.system(size: 10, weight: .bold, design: .rounded)).foregroundStyle(Color.islandSecondary)
                    }
                }
            } trailing: {
                ActivityTrailing(activity: a, tint: tint)
            }
        case .battery(let ev):
            let tint: Color = ev.kind == .low || ev.kind == .critical ? .red : (ev.state.isPluggedIn ? .green : .white)
            Wings(metrics: metrics) {
                Image(systemName: BatteryGlyph.symbol(ev.state))
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(tint)
            } trailing: {
                Text("\(ev.state.level)%")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(tint)
                    .monospacedDigit()
            }
        }
    }
}

struct ActivityTrailing: View {
    let activity: Activity
    let tint: Color

    var body: some View {
        if activity.endsAt != nil || activity.startedAt != nil {
            TimelineView(.periodic(from: .now, by: 1)) { ctx in
                Text(activity.trailingText(now: ctx.date) ?? "")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(tint)
                    .contentTransition(.numericText(countsDown: activity.endsAt != nil))
            }
        } else if let text = activity.trailingText(now: Date()), activity.trailing != nil || activity.progress == nil {
            Text(text)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(tint)
                .lineLimit(1)
        } else if activity.progress != nil {
            ProgressRing(progress: activity.clampedProgress, tint: tint, size: 16)
        } else {
            EmptyView()
        }
    }
}

enum BatteryGlyph {
    static func symbol(_ s: BatteryState) -> String {
        if s.isCharging || s.isPluggedIn { return "battery.100percent.bolt" }
        switch s.level {
        case ..<13: return "battery.0percent"
        case ..<38: return "battery.25percent"
        case ..<63: return "battery.50percent"
        case ..<88: return "battery.75percent"
        default: return "battery.100percent"
        }
    }
}

// MARK: - Sneak peek

struct SneakView: View {
    let activity: Activity
    let metrics: IslandMetrics
    let model: AppModel

    var body: some View {
        let tint = model.tint(for: activity)
        VStack(spacing: 0) {
            Wings(metrics: metrics) {
                IconView(icon: model.icon(for: activity), size: 16, tint: tint)
            } trailing: {
                ActivityTrailing(activity: activity, tint: tint)
            }
            .frame(maxWidth: .infinity)
            VStack(alignment: .leading, spacing: 2) {
                Text(activity.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                if let sub = activity.subtitle {
                    Text(sub)
                        .font(.system(size: 11.5))
                        .foregroundStyle(Color.islandSecondary)
                        .lineLimit(1)
                }
                if activity.clampedProgress != nil, activity.state == .running {
                    ActivityProgress(activity: activity, tint: tint, height: 4).padding(.top, 2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.top, 2)
        }
    }
}

// MARK: - HUD

struct HUDContent: View {
    let hud: HUDEvent
    let metrics: IslandMetrics

    var symbol: String {
        switch hud.kind {
        case .volume:
            if hud.muted || hud.value == 0 { return "speaker.slash.fill" }
            return hud.value < 0.34 ? "speaker.wave.1.fill" : hud.value < 0.67 ? "speaker.wave.2.fill" : "speaker.wave.3.fill"
        case .brightness: return hud.value < 0.5 ? "sun.min.fill" : "sun.max.fill"
        case .keyboardBrightness: return hud.value == 0 ? "light.min" : "light.max"
        case .microphone: return hud.muted ? "mic.slash.fill" : "mic.fill"
        }
    }

    var body: some View {
        Wings(metrics: metrics) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
                .contentTransition(.symbolEffect(.replace))
        } trailing: {
            LevelBar(value: hud.muted ? 0 : hud.value, tint: .white, height: 5)
                .frame(width: max(26, metrics.wingWidth - 22))
                .animation(.snappy(duration: 0.18), value: hud.value)
        }
    }
}

/// Accepts files dropped anywhere on the island.
struct ShelfDropTarget: ViewModifier {
    var enabled: Bool
    @Binding var targeted: Bool
    var onDrop: ([URL]) -> Void

    func body(content: Content) -> some View {
        if enabled {
            content.onDrop(of: [.fileURL], isTargeted: $targeted) { providers in
                loadFileURLs(providers, completion: onDrop)
                return true
            }
        } else {
            content
        }
    }
}
