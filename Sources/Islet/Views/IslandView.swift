import AppKit
import IsletCore
import SwiftUI

/// Where the closed island may draw on one display: its layout, and how much free menu bar
/// room is left beyond the wings (for bubbles). Infinity means "don't care" (explicit wings,
/// or a display without a menu bar).
struct ClosedPlacement: Equatable {
    var layout: ClosedLayout
    var leftSlack: CGFloat
    var rightSlack: CGFloat

    static func unmeasured(_ preference: ClosedLayoutPreference, wing: CGFloat, hasMenuBar: Bool) -> ClosedPlacement {
        let layout = MenuBarLayoutEngine.decide(preference: preference, notch: .zero, preferredWing: wing, occupancy: nil, hasMenuBar: hasMenuBar)
        // Without a measurement nobody knows what's beside the wings, so bubbles go just below
        // the row; with the explicit "beside the notch" choice they sit in it.
        let slack: CGFloat = preference == .auto && hasMenuBar ? 0 : .infinity
        return ClosedPlacement(layout: layout, leftSlack: slack, rightSlack: slack)
    }
}

/// Size, corners and silhouette of the island for one presentation.
struct IslandGeometry: Equatable {
    var size: CGSize
    var top: CGFloat
    var bottom: CGFloat
    /// Menu-bar-row width for the stem-and-body silhouette (0 = classic).
    var stemWidth: CGFloat = 0
    var stemHeight: CGFloat = 0
    /// Wing width inside the menu bar row (content beside the notch).
    var wing: CGFloat = 0
    /// Content sits below the notch rather than beside it.
    var dropped = false

    var shape: IslandShape { IslandShape(topRadius: top, bottomRadius: bottom, stemWidth: stemWidth, stemHeight: stemHeight) }
    var outerWidth: CGFloat { size.width + 2 * top }
}

/// Layout of the island for each presentation. Shared by the view and the panel's hit-testing.
enum IslandLayout {
    /// Extra width either side of the notch for the dropped pill.
    static let dropSide: CGFloat = 38

    static func geometry(for p: IslandPresentation, metrics m: IslandMetrics, layout: ClosedLayout) -> IslandGeometry {
        let n = m.notch
        let small = min(12, n.height / 2.4)
        switch (p, layout) {
        case (.hidden, _), (.idle, _):
            return IslandGeometry(size: n, top: 6, bottom: small)
        case (.expanded, _):
            return IslandGeometry(size: m.expanded, top: 10, bottom: 24)
        case (.compact, .wings(let l, let r)), (.hud, .wings(let l, let r)):
            let w = min(l, r)
            return IslandGeometry(size: CGSize(width: n.width + 2 * w, height: n.height), top: 6, bottom: small, wing: w)
        case (.compact, .drop), (.hud, .drop):
            return IslandGeometry(size: CGSize(width: n.width + 2 * dropSide, height: n.height + MenuBarLayoutEngine.dropHeight),
                                  top: 6, bottom: 13, stemWidth: n.width, stemHeight: n.height, dropped: true)
        case (.sneak, .wings(let l, let r)):
            let w = min(l, r)
            let row = n.width + 2 * w
            let width = max(row + 32, 276)
            return IslandGeometry(size: CGSize(width: width, height: n.height + 42), top: 8, bottom: 18,
                                  stemWidth: width > row ? row : 0, stemHeight: n.height, wing: w)
        case (.sneak, .drop):
            return IslandGeometry(size: CGSize(width: 276, height: n.height + 50), top: 8, bottom: 18,
                                  stemWidth: n.width, stemHeight: n.height, dropped: true)
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

    /// Where bubbles go: beside the island in the menu bar row when there's room, otherwise
    /// just below the row (never on top of menu bar icons). Returns diameter and top offset.
    static func bubblePlacement(geometry g: IslandGeometry, metrics m: IslandMetrics, placement: ClosedPlacement,
                                count: Int, left: Bool) -> (diameter: CGFloat, top: CGFloat) {
        guard count > 0 else { return (m.notch.height, 0) }
        if g.dropped {
            let d = MenuBarLayoutEngine.dropHeight - 2
            return (d, m.notch.height + 1)
        }
        let d = m.notch.height
        let needed = CGFloat(count) * (d + bubbleGap)
        let slack = left ? placement.leftSlack : placement.rightSlack
        return needed <= slack ? (d, 0) : (d - 4, m.notch.height + 3)
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
        let placement = model.placement(for: display, metrics: metrics)
        let g = IslandLayout.geometry(for: p, metrics: metrics, layout: placement.layout)
        let visible = IslandLayout.isVisible(p) || dropTargeted
        let shape = g.shape
        let glow = model.urgentGlow(for: p)
        let bubbles = model.bubbles(for: p)
        let left = model.settings.bubblePlacement == .left
        let bp = IslandLayout.bubblePlacement(geometry: g, metrics: metrics, placement: placement, count: bubbles.items.count, left: left)
        let stale = model.focusedActivity(for: p)?.isStale(at: Date()) ?? false

        HStack(alignment: .top, spacing: IslandLayout.bubbleGap) {
            // Bubbles on one side are balanced by invisible spacers on the other,
            // so the island itself stays centred on the notch.
            if left { bubbleViews(bubbles, diameter: bp.diameter, top: bp.top) } else { spacers(bubbles.items.count, diameter: bp.diameter) }
            ZStack(alignment: .top) {
                if let glow {
                    if snapshotMode {
                        shape.fill(Color.black).shadow(color: glow.opacity(0.8), radius: 9)
                    } else {
                        GlowPulse(color: NSColor(glow), cornerRadius: g.bottom)
                            .frame(width: g.outerWidth, height: g.size.height)
                    }
                }
                model.settings.theme.background(expanded: p == .expanded, shape: shape, row: metrics.notch.height, height: g.size.height)
                    .shadow(color: .black.opacity(p == .expanded ? 0.45 : 0), radius: 14, y: 6)
                content(p, geometry: g)
                    .opacity(stale ? 0.55 : 1)
                    // Out-of-date content stops its spinner, glow and other looping motion.
                    .environment(\.islandReduceMotion, stale || model.settings.reduceMotion || model.settings.animationStyle == .off)
                    .padding(.horizontal, g.top)
                    .frame(width: g.outerWidth, height: g.size.height, alignment: .top)
                    .clipShape(shape)
                    .id(IslandLayout.key(p))
                    .transition(style.contentTransition)
            }
            .frame(width: g.outerWidth, height: g.size.height)
            .keyframeAnimator(initialValue: CGFloat(1), trigger: model.pulse) { view, scale in
                view.scaleEffect(scale, anchor: .top)
            } keyframes: { _ in
                if style.bounces && model.settings.bounceOnActivity {
                    SpringKeyframe(1.04, duration: 0.16, spring: .snappy)
                    SpringKeyframe(1.0, duration: 0.45, spring: .bouncy)
                } else {
                    LinearKeyframe(1.0, duration: 0.01)
                }
            }
            .contextMenu { islandMenu(p) }
            if left { spacers(bubbles.items.count, diameter: bp.diameter) } else { bubbleViews(bubbles, diameter: bp.diameter, top: bp.top) }
        }
        .opacity(visible ? 1 : 0)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(IslandLayout.isVisible(p) ? style.morph : style.collapse, value: IslandLayout.key(p))
        .animation(style.morph, value: bubbles.key)
        .animation(style.morph, value: placement)
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
        .onChange(of: placement) { _, _ in
            NotificationCenter.default.post(name: .isletLayoutChanged, object: nil)
        }
        .fontDesign(model.settings.roundedFont ? .rounded : .default)
        .environment(\.islandReduceMotion, model.settings.reduceMotion || model.settings.animationStyle == .off)
        .environment(\.colorScheme, .dark)
    }

    @ViewBuilder
    private func spacers(_ count: Int, diameter: CGFloat) -> some View {
        ForEach(0..<count, id: \.self) { _ in Color.clear.frame(width: diameter, height: 1) }
    }

    @ViewBuilder
    private func bubbleViews(_ set: BubbleSet, diameter: CGFloat, top: CGFloat) -> some View {
        ForEach(Array(set.items.enumerated()), id: \.element.key) { i, bubble in
            BubbleView(bubble: bubble, model: model, diameter: diameter,
                       overflow: i == set.items.count - 1 ? set.overflow : 0)
                .padding(.top, top)
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
        let tuck = CGFloat(left ? 22 : -22)
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
        if let a = model.focusedActivity(for: p), model.canOpen(a) {
            model.openActivity(a)
        } else {
            model.setExpanded(display)
        }
    }

    @ViewBuilder
    private func islandMenu(_ p: IslandPresentation) -> some View {
        if let a = model.focusedActivity(for: p) {
            if model.canOpen(a) { Button("Open") { model.openActivity(a) } }
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
    private func content(_ p: IslandPresentation, geometry g: IslandGeometry) -> some View {
        switch p {
        case .hidden, .idle:
            Color.clear
        case .hud(let hud):
            HUDContent(hud: hud, metrics: metrics, geometry: g)
        case .compact(let c):
            CompactContentView(content: c, metrics: metrics, geometry: g, model: model)
                .contentShape(Rectangle())
                .onTapGesture { activate(p) }
        case .sneak(let a):
            SneakView(activity: a, metrics: metrics, geometry: g, model: model)
                .contentShape(Rectangle())
                .onTapGesture { activate(p) }
        case .expanded:
            ApprovalGate(model: model, metrics: metrics) { ExpandedView(model: model, metrics: metrics, dropTargeted: dropTargeted) }
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
                ArtworkView(media: np, size: diameter - 8, corner: (diameter - 8) / 2)
            case .activity(let a):
                if model.visualTemplate(for: a) != nil {
                    TemplateBubble(activity: a, model: model, diameter: diameter)
                } else if a.clampedProgress != nil || a.isIndeterminate, a.endsAt == nil, a.startedAt == nil {
                    ProgressRing(progress: a.clampedProgress, tint: model.tint(for: a), size: diameter - 8, lineWidth: 2.2)
                    IconView(icon: model.icon(for: a), size: diameter - 17, tint: model.tint(for: a))
                } else {
                    IconView(icon: model.icon(for: a), size: diameter - 13, tint: model.tint(for: a))
                }
            }
        }
        .frame(width: diameter, height: diameter)
        .overlay(alignment: .bottomTrailing) {
            if overflow > 0 {
                Text("+\(overflow)")
                    .font(.system(size: 8, weight: .heavy, design: .rounded))
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

// MARK: - Closed-island content

/// Two "wings" either side of the notch, inside the menu bar row.
struct Wings<Leading: View, Trailing: View>: View {
    let metrics: IslandMetrics
    let wing: CGFloat
    @ViewBuilder var leading: Leading
    @ViewBuilder var trailing: Trailing

    var body: some View {
        // Narrow wings (a crowded menu bar) give the content more of their width.
        let inset: CGFloat = wing < 46 ? max(5, (wing * 0.18).rounded()) : 11
        HStack(spacing: 0) {
            leading
                .padding(.leading, inset)
                .frame(width: wing, height: metrics.notch.height, alignment: .leading)
            Spacer(minLength: 0)
            trailing
                .padding(.trailing, inset)
                .frame(width: wing, height: metrics.notch.height, alignment: .trailing)
                .environment(\.wingRoom, wing - inset)
        }
        .frame(width: metrics.notch.width + 2 * wing, height: metrics.notch.height)
    }
}

/// One row hanging below the notch: leading, centre and trailing slots.
struct DropRow<Leading: View, Center: View, Trailing: View>: View {
    let metrics: IslandMetrics
    var height: CGFloat = MenuBarLayoutEngine.dropHeight
    @ViewBuilder var leading: Leading
    @ViewBuilder var center: Center
    @ViewBuilder var trailing: Trailing

    var body: some View {
        VStack(spacing: 0) {
            Color.clear.frame(height: metrics.notch.height)
            HStack(spacing: 7) {
                leading
                center.frame(maxWidth: .infinity, alignment: .leading)
                trailing
            }
            .padding(.horizontal, 13)
            .frame(height: height)
        }
    }
}

struct CompactContentView: View {
    let content: CompactContent
    let metrics: IslandMetrics
    let geometry: IslandGeometry
    let model: AppModel

    var body: some View {
        if geometry.dropped { dropped } else { wings }
    }

    @ViewBuilder
    private var wings: some View {
        switch content {
        case .nowPlaying(let np):
            Wings(metrics: metrics, wing: geometry.wing) {
                ArtworkView(media: np, size: min(20, metrics.notch.height - 10), corner: 5)
            } trailing: {
                PlayingIndicator(tint: model.mediaAccent(np), playing: np.isPlaying)
            }
        case .activity(let a, let others):
            let tint = model.tint(for: a)
            Wings(metrics: metrics, wing: geometry.wing) {
                HStack(spacing: 4) {
                    TemplateLeading(activity: a, model: model, tint: tint)
                    // With bubbles off, count the other activities here instead.
                    if others > 0, model.settings.maxConcurrent == 1 {
                        Text("+\(others)").font(.system(size: 9.5, weight: .bold, design: .rounded)).foregroundStyle(Color.islandSecondary)
                    }
                }
            } trailing: {
                TemplateTrailing(activity: a, model: model, tint: tint)
            }
        case .battery(let ev):
            let tint = BatteryGlyph.tint(ev)
            Wings(metrics: metrics, wing: geometry.wing) {
                Image(systemName: BatteryGlyph.symbol(ev.state))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(tint)
            } trailing: {
                Text("\(ev.state.level)%")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(tint)
                    .monospacedDigit()
            }
        }
    }

    @ViewBuilder
    private var dropped: some View {
        switch content {
        case .nowPlaying(let np):
            DropRow(metrics: metrics) {
                ArtworkView(media: np, size: 17, corner: 4.5)
            } center: {
                HStack(spacing: 4) {
                    Text(np.title).font(.system(size: 11.5, weight: .semibold)).foregroundStyle(.white)
                    if let artist = np.artist {
                        Text(artist).font(.system(size: 11)).foregroundStyle(Color.islandTertiary)
                    }
                }
                .lineLimit(1)
            } trailing: {
                PlayingIndicator(tint: model.mediaAccent(np), playing: np.isPlaying)
                    .scaleEffect(0.85)
            }
        case .activity(let a, _):
            let tint = model.tint(for: a)
            DropRow(metrics: metrics) {
                TemplateLeading(activity: a, model: model, tint: tint, size: 14, compact: true)
            } center: {
                TemplateDropCenter(activity: a, model: model)
            } trailing: {
                TemplateTrailing(activity: a, model: model, tint: tint, compact: true)
            }
        case .battery(let ev):
            let tint = BatteryGlyph.tint(ev)
            DropRow(metrics: metrics) {
                Image(systemName: BatteryGlyph.symbol(ev.state)).font(.system(size: 13, weight: .semibold)).foregroundStyle(tint)
            } center: {
                Text(BatteryGlyph.label(ev)).font(.system(size: 11.5, weight: .semibold)).foregroundStyle(.white).lineLimit(1)
            } trailing: {
                Text("\(ev.state.level)%").font(.system(size: 11.5, weight: .semibold, design: .rounded)).foregroundStyle(tint).monospacedDigit()
            }
        }
    }
}

struct ActivityTrailing: View {
    let activity: Activity
    let tint: Color
    /// Slightly smaller type for the dropped pill and sneak peeks.
    var compact = false
    @Environment(\.wingRoom) private var room

    private var size: CGFloat { compact ? 11.5 : 12.5 }

    var body: some View {
        if room < NarrowValue.wordRoom, activity.endsAt == nil, activity.startedAt == nil,
           let text = activity.trailingText(now: Date()), activity.trailing != nil || activity.progress == nil,
           let glyph = NarrowValue.glyph(for: text, state: activity.state) {
            Image(systemName: glyph)
                .font(.system(size: min(size, room * 0.6), weight: .semibold))
                .foregroundStyle(tint)
        } else if activity.endsAt != nil || activity.startedAt != nil {
            TimelineView(.periodic(from: .now, by: 1)) { ctx in
                Text(activity.trailingText(now: ctx.date) ?? "")
                    .font(.system(size: size, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(tint)
                    .lineLimit(1)
                    .minimumScaleFactor(room < NarrowValue.wordRoom ? 0.5 : 0.7)
                    .contentTransition(.numericText(countsDown: activity.endsAt != nil))
            }
        } else if let text = activity.trailingText(now: Date()), activity.trailing != nil || activity.progress == nil {
            Text(text)
                .font(.system(size: size - 0.5, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(room < NarrowValue.wordRoom ? 0.5 : 0.75)
        } else if activity.progress != nil {
            ProgressRing(progress: activity.clampedProgress, tint: tint, size: compact ? 13 : 15, lineWidth: 2.2)
        } else {
            EmptyView()
        }
    }
}

enum BatteryGlyph {
    static func tint(_ ev: BatteryEvent) -> Color {
        switch ev.kind {
        case .low, .critical: return .red
        case .lowPowerOn: return .yellow
        default: return ev.state.isPluggedIn ? .green : .white
        }
    }

    static func label(_ ev: BatteryEvent) -> String {
        switch ev.kind {
        case .pluggedIn:
            let label = ev.state.isCharging ? "Charging" : "Connected"
            return ev.state.adapterWatts.map { "\(label) · \($0) W" } ?? label
        case .charged: return "Charged to \(ev.state.level)%"
        case .unplugged: return "On battery"
        case .full: return "Fully charged"
        case .low, .critical: return "Low battery"
        case .lowPowerOn: return "Low Power Mode on"
        case .lowPowerOff: return "Low Power Mode off"
        }
    }

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
    let geometry: IslandGeometry
    let model: AppModel

    var body: some View {
        let tint = model.tint(for: activity)
        if geometry.dropped {
            VStack(alignment: .leading, spacing: 2) {
                Color.clear.frame(height: metrics.notch.height - 2)
                HStack(spacing: 8) {
                    TemplateLeading(activity: activity, model: model, tint: tint, compact: true)
                    Text(activity.title).font(.system(size: 12.5, weight: .semibold)).foregroundStyle(.white).lineLimit(1)
                    Spacer(minLength: 4)
                    TemplateTrailing(activity: activity, model: model, tint: tint, compact: true)
                }
                TemplateDetail(activity: activity, model: model, roomy: true) { details(tint: tint) }.padding(.leading, 23)
            }
            .padding(.horizontal, 14)
        } else {
            VStack(spacing: 0) {
                Wings(metrics: metrics, wing: geometry.wing) {
                    TemplateLeading(activity: activity, model: model, tint: tint)
                } trailing: {
                    TemplateTrailing(activity: activity, model: model, tint: tint, compact: true)
                }
                .frame(maxWidth: .infinity)
                VStack(alignment: .leading, spacing: 2) {
                    Text(activity.title).font(.system(size: 12.5, weight: .semibold)).foregroundStyle(.white).lineLimit(1)
                    TemplateDetail(activity: activity, model: model) { details(tint: tint) }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 15)
                .padding(.top, 1)
            }
        }
    }

    @ViewBuilder
    private func details(tint: Color) -> some View {
        if let sub = activity.subtitle {
            Text(sub).font(.system(size: 11)).foregroundStyle(Color.islandSecondary).lineLimit(1)
        }
        if activity.clampedProgress != nil, activity.state == .running {
            ActivityProgress(activity: activity, tint: tint, height: 3.5).padding(.top, 2)
        }
    }
}

// MARK: - HUD

struct HUDContent: View {
    let hud: HUDEvent
    let metrics: IslandMetrics
    let geometry: IslandGeometry

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
        if geometry.dropped {
            DropRow(metrics: metrics) {
                icon.frame(width: 16)
            } center: {
                LevelBar(value: hud.muted ? 0 : hud.value, tint: .white, height: 4)
                    .animation(.snappy(duration: 0.18), value: hud.value)
            } trailing: {
                Text("\(Int((hud.muted ? 0 : hud.value) * 100))")
                    .font(.system(size: 11, weight: .semibold, design: .rounded)).monospacedDigit()
                    .foregroundStyle(Color.islandSecondary).frame(width: 22, alignment: .trailing)
            }
        } else {
            Wings(metrics: metrics, wing: geometry.wing) {
                icon
            } trailing: {
                LevelBar(value: hud.muted ? 0 : hud.value, tint: .white, height: 4)
                    .frame(width: max(22, geometry.wing - 20))
                    .animation(.snappy(duration: 0.18), value: hud.value)
            }
        }
    }

    private var icon: some View {
        Image(systemName: symbol)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.white)
            .contentTransition(.symbolEffect(.replace))
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
