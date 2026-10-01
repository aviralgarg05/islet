import AppKit
import IsletCore
import SwiftUI

/// How the closed island sits on one display: the width of each wing beside the notch, and how
/// much free menu bar room is left beyond the wings (for bubbles). Infinity means "don't care"
/// (always full width, or a display without a menu bar).
struct ClosedPlacement: Equatable {
    var wing: CGFloat
    var leftSlack: CGFloat
    var rightSlack: CGFloat
}

extension ClosedPlacement {
    /// The same free room on both sides.
    init(wing: CGFloat, slack: CGFloat) {
        self.init(wing: wing, leftSlack: slack, rightSlack: slack)
    }

    static func unmeasured(_ preference: ClosedLayoutPreference, wing: CGFloat, hasMenuBar: Bool) -> ClosedPlacement {
        let width = MenuBarLayoutEngine.wingWidth(preference: preference, notch: .zero, preferredWing: wing, occupancy: nil, hasMenuBar: hasMenuBar)
        // Without a measurement nobody knows what's beside the wings, so bubbles go just below
        // the row, whatever the width setting; they never cover a menu bar item. Only a display
        // with no menu bar row has room for certain.
        let slack: CGFloat = hasMenuBar ? 0 : .infinity
        return ClosedPlacement(wing: width, slack: slack)
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
    /// A floating pill sits this far inside the row, top and bottom (0 = hangs from the top edge).
    var inset: CGFloat = 0

    var shape: IslandShape { IslandShape(topRadius: top, bottomRadius: bottom, stemWidth: stemWidth, stemHeight: stemHeight, inset: inset) }
    var outerWidth: CGFloat { size.width + 2 * top }
}

/// Choices from Settings and the pointer that change the island's silhouette beyond the
/// presentation itself. The view and the panel's hit-testing both read them (`AppModel.look`),
/// so they always agree.
struct IslandLook: Equatable {
    /// HUDs drop below the notch with a percentage ("Detailed").
    var detailedHUD = false
    /// Points the closed island grows on each side while the pointer rests on it, before it
    /// opens (0 when it isn't there, or with Reduce Motion).
    var hoverGrow: CGFloat = 0
    /// The open island takes the stem-and-body shape (the Glass theme): only a notch-wide stem
    /// sits in the menu bar row, so the menu bar beside the notch stays in view, and the glass
    /// body opens out below the row.
    var stemmedOpen = false
}

extension AppModel {
    func look(for display: CGDirectDisplayID) -> IslandLook {
        let calm = settings.reduceMotion || NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        let resting = hoverDisplay == display && expandedScreen == nil
        // An approval card's header uses the whole row, so it keeps the full-width shape.
        return IslandLook(detailedHUD: settings.hudStyle == .detailed,
                          hoverGrow: resting && !calm ? IslandLayout.hoverGrow : 0,
                          stemmedOpen: settings.theme == .glass && approvals.current == nil)
    }
}

/// Layout of the island for each presentation. Shared by the view and the panel's hit-testing.
enum IslandLayout {
    /// - Parameter wing: width of each wing beside the notch, from the closed placement.
    static func geometry(for p: IslandPresentation, metrics m: IslandMetrics, wing: CGFloat, look: IslandLook = IslandLook()) -> IslandGeometry {
        let n = m.notch
        let small = min(12, n.height / 2.4)
        let row = n.width + 2 * wing
        // Shapes without a stem give it their own width, so a move into a stemmed shape narrows
        // the stem smoothly instead of passing through a thin one.
        switch p {
        case .hidden, .idle:
            if m.floats { return grown(pill(width: n.width, metrics: m, wing: 0), by: look.hoverGrow) }
            return grown(IslandGeometry(size: n, top: 6, bottom: small, stemWidth: n.width, stemHeight: n.height), by: look.hoverGrow)
        case .compact where m.floats, .hud where m.floats && !look.detailedHUD:
            return grown(pill(width: row, metrics: m, wing: wing), by: look.hoverGrow)
        case .expanded where look.stemmedOpen:
            return IslandGeometry(size: m.expanded, top: stemFlare, bottom: Radius.shell,
                                  stemWidth: n.width, stemHeight: ExpandedLayout(metrics: m).row)
        case .expanded:
            return IslandGeometry(size: m.expanded, top: Radius.flare, bottom: Radius.shell,
                                  stemWidth: m.expanded.width, stemHeight: n.height)
        case .hud where look.detailedHUD:
            return detailedHUD(metrics: m)
        case .compact, .hud:
            return grown(IslandGeometry(size: CGSize(width: row, height: n.height), top: 6, bottom: small,
                                        stemWidth: row, stemHeight: n.height, wing: wing), by: look.hoverGrow)
        case .sneak(let a):
            return peek(metrics: m, wing: wing, extra: sneakBar(a))
        case .songPeek:
            return peek(metrics: m, wing: wing, extra: 0)
        }
    }

    /// A sneak peek, of an activity or a new song: the wings stay in the menu bar row and the
    /// body opens out below it for a moment.
    private static func peek(metrics m: IslandMetrics, wing: CGFloat, extra: CGFloat) -> IslandGeometry {
        let n = m.notch
        let row = n.width + 2 * wing
        let width = max(row + 32, 276)
        return IslandGeometry(size: CGSize(width: width, height: n.height + 46 + extra), top: 8, bottom: 18,
                              stemWidth: min(row, width), stemHeight: n.height, wing: wing)
    }

    /// How much the closed island widens on each side while the pointer rests on it.
    static let hoverGrow: CGFloat = NotchGeometry.hoverGrow
    /// The stem's flare where it meets the top of the screen, in the stem-and-body shape.
    static let stemFlare: CGFloat = 10

    /// The closed island a little bigger: `d` points wider on each side and no taller, so it
    /// answers the pointer without hanging any lower than the notch or out of the menu bar row.
    private static func grown(_ g: IslandGeometry, by d: CGFloat) -> IslandGeometry {
        guard d > 0 else { return g }
        var g = g
        g.size = NotchGeometry.hoverGrown(g.size, by: d)
        g.stemWidth += 2 * d
        return g
    }

    /// On a display without a notch: a capsule floating inside the menu bar row, clear of the
    /// screen's top edge and of the row's bottom. Like the other closed shapes its stem is its
    /// own width, so opening or peeking widens it smoothly instead of through a thin stem.
    private static func pill(width: CGFloat, metrics m: IslandMetrics, wing: CGFloat) -> IslandGeometry {
        let inset = NotchGeometry.pillInset
        return IslandGeometry(size: CGSize(width: width, height: m.notch.height), top: 0, bottom: (m.notch.height - 2 * inset) / 2,
                              stemWidth: width, stemHeight: m.notch.height, wing: wing, inset: inset)
    }

    /// The detailed HUD: a notch-wide stem in the menu bar row, so the menu bar beside the notch
    /// stays clear, and one short line below it with the icon, the level and its percentage.
    private static func detailedHUD(metrics m: IslandMetrics) -> IslandGeometry {
        let n = m.notch
        let width = max(n.width + 2 * Space.xxl, 236)
        return IslandGeometry(size: CGSize(width: width, height: n.height + hudBody), top: 8, bottom: Radius.l,
                              stemWidth: n.width, stemHeight: n.height)
    }

    /// Height of the detailed HUD's line below the notch: no more than the line needs.
    static let hudBody: CGFloat = 30

    /// A sneak peek with a bar under its text gets a little more height, so the bar clears the
    /// rounded bottom edge.
    static func sneakBar(_ a: Activity) -> CGFloat {
        a.state == .running && (a.clampedProgress != nil || a.steps != nil) ? Space.s : 0
    }

    /// The panel: room for the widest and tallest island, its shadow, and the page switcher
    /// that floats under the open island.
    static func windowFrame(for screen: ScreenDescriptor, metrics: IslandMetrics) -> CGRect {
        var frame = NotchGeometry.windowFrame(for: screen, metrics: metrics)
        frame.origin.y -= PageSwitcher.band
        frame.size.height += PageSwitcher.band
        return frame
    }

    /// Where the page switcher sits, relative to the top centre of the screen (y up), or nil
    /// when it isn't shown. Generous in width: the switcher's own width depends on its labels.
    static func switcherRect(for p: IslandPresentation, geometry g: IslandGeometry, showsApproval: Bool) -> CGRect? {
        guard p == .expanded, !showsApproval else { return nil }
        let width = min(g.size.width, 340)
        let height = PageSwitcher.gap + PageSwitcher.height
        return CGRect(x: -width / 2, y: -g.size.height - height, width: width, height: height)
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
        // One key for every song: a song that follows another inside the peek swaps in place.
        case .songPeek: return "song-peek"
        case .compact(.nowPlaying): return "compact-media"
        case .compact(.activity(let a, _)): return "compact-\(a.id)"
        case .compact(.battery): return "compact-battery"
        case .expanded: return "expanded"
        }
    }

    /// Bubbles sit beside the island in the menu bar row, level with it. They never hang below
    /// the row and never cover a menu bar icon: only as many as fit are drawn
    /// (`AppModel.fittedBubbles`) and the island counts the rest. Returns diameter and top offset.
    static func bubblePlacement(metrics m: IslandMetrics, placement: ClosedPlacement,
                                count: Int, left: Bool) -> (diameter: CGFloat, top: CGFloat) {
        // Beside a floating pill, bubbles float with it at its height.
        if m.floats { return (m.notch.height - 2 * NotchGeometry.pillInset, NotchGeometry.pillInset) }
        return (m.notch.height, 0)
    }

    /// How many bubbles of `diameter` fit in `slack` points beside the island.
    static func bubblesThatFit(_ count: Int, slack: CGFloat, diameter: CGFloat) -> Int {
        guard count > 0 else { return 0 }
        guard slack.isFinite else { return count }
        return max(0, min(count, Int((slack / (diameter + bubbleGap)).rounded(.down))))
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
    /// The bubbles that fit beside the island on this display, and how many more the island
    /// counts in its wing ("+2") because the menu bar row has no room for them.
    func fittedBubbles(for p: IslandPresentation, placement: ClosedPlacement, metrics: IslandMetrics,
                       display: CGDirectDisplayID? = nil) -> (bubbles: BubbleSet, counted: Int) {
        let all = bubbles(for: p, display: display)
        guard !all.items.isEmpty else { return (all, 0) }
        let left = settings.bubblePlacement == .left
        let fit = IslandLayout.bubblesThatFit(all.items.count, slack: left ? placement.leftSlack : placement.rightSlack,
                                              diameter: metrics.notch.height)
        guard fit < all.items.count else { return (all, 0) }
        return (BubbleSet(items: Array(all.items.prefix(fit)), overflow: 0), all.items.count - fit + all.overflow)
    }

    /// - Parameter display: the island's display; music has no bubble where "In full screen"
    ///   hides it.
    func bubbles(for p: IslandPresentation, display: CGDirectDisplayID? = nil) -> BubbleSet {
        guard case .compact(let c) = p, settings.maxConcurrent > 1 else { return .none }
        var acts = activities
        var items: [IslandBubble] = []
        switch c {
        case .activity(let a, _):
            acts.removeAll { $0.id == a.id }
            // Music paused a moment ago keeps its bubble (dimmed) for "Hide paused music after".
            if settings.mediaEnabled, display.map({ fullscreenBehaviour(on: $0) != .hideMusic }) ?? true,
               let np = Presenter.mediaInView(nowPlaying, pausedMedia: pausedMusic.show(timeout: settings.pausedMusicTimeout, now: Date())) {
                items.append(.media(np))
            }
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
        let look = model.look(for: display)
        let g = IslandLayout.geometry(for: p, metrics: metrics, wing: placement.wing, look: look)
        // Resting on the notch shows the island growing out of it, even with nothing to show.
        let visible = IslandLayout.isVisible(p) || dropTargeted || (p == .idle && look.hoverGrow > 0)
        let shape = g.shape
        let glow = model.urgentGlow(for: p)
        let fitted = model.fittedBubbles(for: p, placement: placement, metrics: metrics, display: display)
        let bubbles = fitted.bubbles
        let left = model.settings.bubblePlacement == .left
        let bp = IslandLayout.bubblePlacement(metrics: metrics, placement: placement, count: bubbles.items.count, left: left)
        let stale = model.focusedActivity(for: p)?.isStale(at: Date()) ?? false

        HStack(alignment: .top, spacing: IslandLayout.bubbleGap) {
            // Bubbles on one side are balanced by invisible spacers on the other,
            // so the island itself stays centred on the notch.
            if left { bubbleViews(bubbles, diameter: bp.diameter, top: bp.top) } else { spacers(bubbles.items.count, diameter: bp.diameter) }
            VStack(spacing: PageSwitcher.gap) {
            ZStack(alignment: .top) {
                if let glow {
                    if snapshotMode {
                        shape.fill(Color.black).shadow(color: glow.opacity(0.8), radius: 9)
                    } else {
                        GlowPulse(color: NSColor(glow), cornerRadius: g.bottom)
                            .frame(width: g.outerWidth, height: g.size.height)
                    }
                }
                model.settings.theme.background(expanded: p == .expanded, shape: shape, row: g.stemHeight, height: g.size.height,
                                                glassLevel: model.settings.glassLevel,
                                                closedGlass: metrics.isSynthetic && model.settings.glassOnNotchless,
                                                stem: p == .expanded && look.stemmedOpen ? g.stemWidth : nil)
                    .shadow(color: .black.opacity(p == .expanded ? 0.45 : 0), radius: 14, y: 6)
                IslandOutline(shape: shape, on: model.settings.outline)
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
            // Pages float under the open island, once it has room (not over an approval).
            if p == .expanded && model.approvals.current == nil {
                PageSwitcher(model: model)
                    .transition(switcherTransition)
            }
            }
            if left { spacers(bubbles.items.count, diameter: bp.diameter) } else { bubbleViews(bubbles, diameter: bp.diameter, top: bp.top) }
        }
        .opacity(visible ? 1 : 0)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(IslandLayout.isVisible(p) ? style.morph : style.collapse, value: IslandLayout.key(p))
        .animation(style.morph, value: bubbles.key)
        .animation(style.morph, value: placement)
        // The hover response: a quick, small spring, in step with the others.
        .animation(style == .off ? nil : Motion.settle, value: look.hoverGrow)
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
        .environment(\.islandMotion, style)
        .environment(\.visualiserStyle, model.settings.visualiserStyle)
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

    /// The switcher buds off the island's lower edge after the shape has settled, and goes
    /// first when it closes.
    private var switcherTransition: AnyTransition {
        switch style {
        case .off: return .identity
        case .minimal: return .opacity
        default:
            return .asymmetric(
                insertion: AnyTransition.scale(scale: 0.6, anchor: .top).combined(with: .opacity).combined(with: .offset(y: -PageSwitcher.height / 2))
                    .animation(Motion.open.delay(0.14 * Motion.pace)),
                removal: .opacity.animation(.easeIn(duration: 0.08))
            )
        }
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
        Button(model.expandedScreen == nil ? "Open island" : "Close island") {
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
            if model.settings.hudStyle == .detailed {
                DetailedHUDContent(hud: hud, metrics: metrics, tint: model.hudTint(hud.kind))
            } else {
                HUDContent(hud: hud, metrics: metrics, geometry: g, tint: model.hudTint(hud.kind))
            }
        case .compact(let c):
            CompactContentView(content: c, metrics: metrics, geometry: g, model: model,
                               counted: model.fittedBubbles(for: p, placement: model.placement(for: display, metrics: metrics), metrics: metrics,
                                                            display: display).counted)
                .contentShape(Rectangle())
                .onTapGesture { activate(p) }
        case .sneak(let a):
            SneakView(activity: a, metrics: metrics, geometry: g, model: model)
                .contentShape(Rectangle())
                .onTapGesture { activate(p) }
        case .songPeek(let np):
            SongPeekView(media: np, metrics: metrics, geometry: g, model: model)
                .contentShape(Rectangle())
                .onTapGesture { activate(p) }
        case .expanded:
            ApprovalGate(model: model, metrics: metrics) {
                ExpandedView(model: model, metrics: metrics, dropTargeted: dropTargeted, stemmed: model.look(for: display).stemmedOpen)
            }
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

/// "+2" in the closed island's wing: other activities without a bubble.
struct MoreCount: View {
    let count: Int

    var body: some View {
        if count > 0 {
            Text("+\(count)")
                .font(.system(size: 9.5, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(Color.islandSecondary)
                .fixedSize()
                .accessibilityLabel("\(count) more")
        }
    }
}

struct BubbleView: View {
    let bubble: IslandBubble
    let model: AppModel
    let diameter: CGFloat
    var overflow = 0
    @Environment(\.islandMotion) private var motion

    var body: some View {
        ZStack {
            Circle().fill(Color.black)
            switch bubble {
            case .media(let np):
                TrackArtwork(media: np, size: diameter - 8, corner: (diameter - 8) / 2)
                    .opacity(np.isPlaying ? 1 : PausedLook.artworkOpacity)
                    .animation(motion == .off ? nil : .easeInOut(duration: PausedLook.fade), value: np.isPlaying)
            case .activity(let a):
                if model.visualTemplate(for: a) != nil {
                    TemplateBubble(activity: a, model: model, diameter: diameter)
                } else if a.clampedProgress != nil, a.endsAt == nil, a.startedAt == nil {
                    // A ring only for real progress; a bubble that is just "working" stays a clean icon.
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

    /// Space between the island's edge and the wing's content. Narrow wings (a crowded menu
    /// bar) give the content more of their width.
    static func inset(for wing: CGFloat) -> CGFloat { wing < 46 ? max(5, (wing * 0.18).rounded()) : 11 }

    var body: some View {
        let inset = Self.inset(for: wing)
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

struct CompactContentView: View {
    let content: CompactContent
    let metrics: IslandMetrics
    let geometry: IslandGeometry
    let model: AppModel
    /// Other activities with no room for a bubble beside the island, counted in the wing.
    var counted = 0

    var body: some View {
        switch content {
        case .nowPlaying(let np):
            // A new song swaps the artwork; the equaliser beside it keeps running.
            Wings(metrics: metrics, wing: geometry.wing) {
                HStack(spacing: 4) {
                    ClosedArtwork(media: np, model: model, size: ClosedArtwork.size(metrics))
                    MoreCount(count: counted)
                }
            } trailing: {
                PlayingIndicator(tint: model.musicTint(np), playing: np.isPlaying)
            }
        case .activity(let a, let others):
            let tint = model.tint(for: a)
            Wings(metrics: metrics, wing: geometry.wing) {
                HStack(spacing: 4) {
                    TemplateLeading(activity: a, model: model, tint: tint)
                    // With bubbles off, or no room for them in the menu bar row, count the
                    // other activities here instead.
                    MoreCount(count: model.settings.maxConcurrent == 1 ? others : counted)
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
                    .textStyle(.body, emphasized: true, numeric: true)
                    .foregroundStyle(tint)
                    .monospacedDigit()
                    // Icon-only wings are too narrow for "100%" at full size; never wrap it.
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
        }
    }
}

/// The artwork beside the notch: corners from Settings, and dimmed while the music is paused,
/// in step with the indicator settling. With "Show song progress" a thin ring round it fills
/// as the song plays; it sits outside the artwork, so the artwork doesn't move.
struct ClosedArtwork: View {
    let media: NowPlaying
    let model: AppModel
    var size: CGFloat
    @Environment(\.islandMotion) private var motion

    /// Fits the menu bar row, up to 20 points.
    static func size(_ metrics: IslandMetrics) -> CGFloat { max(8, min(20, metrics.notch.height - 10)) }
    /// Space between the artwork and the ring, and the ring's line.
    static let ringGap: CGFloat = 1.5
    static let ringLine: CGFloat = 1.5

    var body: some View {
        let corner = model.artworkCorner(size: size, standard: 5)
        TrackArtwork(media: media, size: size, corner: corner)
            .overlay {
                if model.settings.songProgressRing, media.duration != nil {
                    let pad = Self.ringGap + Self.ringLine
                    SongRing(media: media, tint: model.musicTint(media), corner: corner + pad, lineWidth: Self.ringLine)
                        .frame(width: size + 2 * pad, height: size + 2 * pad)
                        .allowsHitTesting(false)
                }
            }
            .opacity(media.isPlaying ? 1 : PausedLook.artworkOpacity)
            .animation(motion == .off ? nil : .easeInOut(duration: PausedLook.fade), value: media.isPlaying)
    }
}

struct ActivityTrailing: View {
    let activity: Activity
    let tint: Color
    /// Slightly smaller type for sneak peeks.
    var compact = false
    @Environment(\.wingRoom) private var room

    private var size: CGFloat { compact ? TextStyle.caption.size : TextStyle.body.size }

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
                .font(.system(size: size, weight: .semibold, design: .rounded))
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
        // The text lines up under the wing's icon, so the peek reads as one column.
        let row = metrics.notch.width + 2 * geometry.wing
        let lead = max(Space.m, (geometry.size.width - row) / 2 + Wings<EmptyView, EmptyView>.inset(for: geometry.wing))
        VStack(spacing: 0) {
            Wings(metrics: metrics, wing: geometry.wing) {
                TemplateLeading(activity: activity, model: model, tint: tint)
            } trailing: {
                TemplateTrailing(activity: activity, model: model, tint: tint, compact: true)
            }
            .frame(maxWidth: .infinity)
            VStack(alignment: .leading, spacing: Space.hair) {
                Text(activity.title).textStyle(.headline).foregroundStyle(Ink.primary).lineLimit(1)
                TemplateDetail(activity: activity, model: model) { details(tint: tint) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, lead)
            .padding(.top, Space.hair)
        }
    }

    @ViewBuilder
    private func details(tint: Color) -> some View {
        if let sub = activity.subtitle {
            Text(sub).textStyle(.caption).foregroundStyle(Ink.secondary).lineLimit(1)
        }
        if activity.clampedProgress != nil, activity.state == .running {
            ActivityProgress(activity: activity, tint: tint, height: 4).padding(.top, Space.hair)
        }
    }
}

/// A new song for a moment: the wings as in the closed island, and the title and artist in
/// the body below, lined up under the artwork like an activity's sneak peek.
struct SongPeekView: View {
    let media: NowPlaying
    let metrics: IslandMetrics
    let geometry: IslandGeometry
    let model: AppModel

    var body: some View {
        let row = metrics.notch.width + 2 * geometry.wing
        let lead = max(Space.m, (geometry.size.width - row) / 2 + Wings<EmptyView, EmptyView>.inset(for: geometry.wing))
        VStack(spacing: 0) {
            Wings(metrics: metrics, wing: geometry.wing) {
                ClosedArtwork(media: media, model: model, size: ClosedArtwork.size(metrics))
            } trailing: {
                PlayingIndicator(tint: model.musicTint(media), playing: media.isPlaying)
            }
            .frame(maxWidth: .infinity)
            TrackText(media: media) {
                VStack(alignment: .leading, spacing: Space.hair) {
                    Text(media.title).textStyle(.headline).foregroundStyle(Ink.primary).lineLimit(1)
                    if let by = media.artist ?? media.appName {
                        Text(by).textStyle(.caption).foregroundStyle(Ink.secondary).lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, lead)
            .padding(.top, Space.hair)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(["Now playing", media.title, media.artist].compactMap { $0 }.joined(separator: ", "))
    }
}

// MARK: - HUD

extension HUDEvent {
    var symbol: String {
        switch kind {
        case .volume:
            if muted || value == 0 { return "speaker.slash.fill" }
            return value < 0.34 ? "speaker.wave.1.fill" : value < 0.67 ? "speaker.wave.2.fill" : "speaker.wave.3.fill"
        case .brightness: return value < 0.5 ? "sun.min.fill" : "sun.max.fill"
        case .keyboardBrightness: return value == 0 ? "light.min" : "light.max"
        case .microphone: return muted ? "mic.slash.fill" : "mic.fill"
        }
    }

    /// The level shown: nothing while muted.
    var shownLevel: Double { muted ? 0 : value }

    var accessibilityName: String {
        switch kind {
        case .volume: return "Volume"
        case .brightness: return "Brightness"
        case .keyboardBrightness: return "Keyboard brightness"
        case .microphone: return "Microphone"
        }
    }
}

struct HUDContent: View {
    let hud: HUDEvent
    let metrics: IslandMetrics
    let geometry: IslandGeometry
    /// White, the accent or the kind's own colour (Settings → Notifications & HUDs).
    var tint: Color = .white

    var symbol: String { hud.symbol }

    var body: some View {
        Wings(metrics: metrics, wing: geometry.wing) {
            icon
        } trailing: {
            LevelBar(value: hud.muted ? 0 : hud.value, tint: tint, height: 4)
                .frame(width: max(22, geometry.wing - 20))
                .animation(.snappy(duration: 0.18), value: hud.value)
        }
    }

    private var icon: some View {
        Image(systemName: symbol)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(tint)
            .contentTransition(.symbolEffect(.replace))
    }
}

/// The detailed HUD (Settings → Notifications & HUDs → Style): the menu bar row stays as the
/// notch, and one line below it holds the icon, the level and its percentage.
struct DetailedHUDContent: View {
    let hud: HUDEvent
    let metrics: IslandMetrics
    var tint: Color = .white
    @Environment(\.islandMotion) private var motion

    var body: some View {
        let percent = Int((hud.shownLevel * 100).rounded())
        VStack(spacing: 0) {
            Color.clear.frame(height: metrics.notch.height)
            HStack(spacing: Space.s) {
                Image(systemName: hud.symbol)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(tint)
                    .contentTransition(.symbolEffect(.replace))
                    .frame(width: 18)
                LevelBar(value: hud.shownLevel, tint: tint, height: 5)
                    .animation(motion == .off ? nil : .snappy(duration: 0.18), value: hud.value)
                Text("\(percent)%")
                    .textStyle(.caption, emphasized: true, numeric: true)
                    .foregroundStyle(Ink.secondary)
                    .contentTransition(.numericText(value: Double(percent)))
                    .animation(motion == .off ? nil : .snappy(duration: 0.18), value: percent)
                    .frame(width: 34, alignment: .trailing)
            }
            .padding(.horizontal, Space.l)
            .frame(height: IslandLayout.hudBody)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(hud.accessibilityName) \(percent)%")
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
