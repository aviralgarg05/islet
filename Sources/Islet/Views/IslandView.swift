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
        case .compact(.sticker):
            // The resting sticker alone: the island hugs the notch with one small wing for it,
            // rather than a long bar with an empty left wing.
            let w = min(wing, MenuBarLayoutEngine.iconOnlyWing)
            let hug = n.width + 2 * w
            if m.floats { return grown(pill(width: hug, metrics: m, wing: w), by: look.hoverGrow) }
            return grown(IslandGeometry(size: CGSize(width: hug, height: n.height), top: 6, bottom: small,
                                        stemWidth: hug, stemHeight: n.height, wing: w), by: look.hoverGrow)
        case .compact where m.floats, .hud where m.floats && !look.detailedHUD:
            return grown(pill(width: row, metrics: m, wing: wing), by: look.hoverGrow)
        case .expanded where look.stemmedOpen:
            // Over a notch the stem is the notch's width. Without one there is no notch to
            // match: the stem keeps the pill's width, so opening never pinches it.
            return IslandGeometry(size: m.expanded, top: stemFlare, bottom: Radius.shell,
                                  stemWidth: m.floats ? min(row, m.expanded.width) : n.width,
                                  stemHeight: ExpandedLayout(metrics: m).row)
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
        if m.floats {
            // Without a notch the row part floats like the pill it grows from: inside the
            // row's top edge, its top corners rounded, and the body below it as tall as ever.
            let inset = NotchGeometry.pillInset
            return IslandGeometry(size: CGSize(width: width, height: n.height + 46 + extra + inset), top: 0, bottom: 18,
                                  stemWidth: min(row, width), stemHeight: n.height, wing: wing, inset: inset)
        }
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

    /// A sneak peek whose detail takes a second line gets a little more height, so it clears
    /// the rounded bottom edge: a bar on its own line, or the flight board's codes over their
    /// times. Bars that sit beside their text (ETA, gauge) need none.
    static func sneakBar(_ a: Activity) -> CGFloat {
        switch a.resolvedTemplate {
        case .flight where a.flight != nil: return Space.m
        case .eta, .gauge: return 0
        case .stages where a.stageCount != nil: return Space.s
        default: return a.state == .running && (a.clampedProgress != nil || a.steps != nil) ? Space.s : 0
        }
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
    /// when it isn't shown. `width` is the switcher's own, as drawn (it depends on its labels);
    /// before it has been drawn, a generous guess.
    static func switcherRect(for p: IslandPresentation, geometry g: IslandGeometry, showsApproval: Bool,
                             width drawn: CGFloat? = nil) -> CGRect? {
        guard p == .expanded, !showsApproval else { return nil }
        let width = min(g.size.width, drawn.map { $0 + 2 } ?? 340)
        let height = PageSwitcher.gap + PageSwitcher.height
        return CGRect(x: -width / 2, y: -g.size.height - height, width: width, height: height)
    }

    /// A peek below the notch: an activity's sneak peek or a new song.
    static func isPeek(_ p: IslandPresentation) -> Bool {
        switch p {
        case .sneak, .songPeek: return true
        default: return false
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
        // One key for every song: a song that follows another inside the peek swaps in place.
        case .songPeek: return "song-peek"
        case .compact(.nowPlaying): return "compact-media"
        case .compact(.activity(let a, _)): return "compact-\(a.id)"
        case .compact(.battery): return "compact-battery"
        case .compact(.sticker): return "compact-sticker"
        case .expanded: return "expanded"
        }
    }

    /// How big a presentation's shape is, to tell a move that opens (to a bigger shape, on the
    /// lively spring) from one that closes (once the content has gone, on the calmer one).
    static func rank(_ p: IslandPresentation) -> Int {
        switch p {
        case .hidden, .idle: return 0
        case .compact, .hud: return 1
        case .sneak, .songPeek: return 2
        case .expanded: return 3
        }
    }

    /// The content's identity. Every state with the row beside the notch (compact, the compact
    /// HUD and both peeks) shares one, so moving between them keeps the row in place.
    static func contentKey(_ p: IslandPresentation, detailedHUD: Bool) -> String {
        switch p {
        case .hidden, .idle: return "none"
        case .hud where detailedHUD: return "hud-detailed"
        case .hud, .compact, .sneak, .songPeek: return "row"
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
        // Every activity without a bubble is counted once, in the wing: those past "Show up to"
        // as well as those the row has no room for.
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
               let np = Presenter.mediaInView(closedNowPlaying, pausedMedia: pausedMusic.show(timeout: settings.pausedMusicTimeout, now: Date())) {
                items.append(.media(np))
            }
        case .nowPlaying:
            break
        case .battery, .sticker:
            return .none
        }
        items += acts.map(IslandBubble.activity)
        let room = settings.maxConcurrent - 1
        guard items.count > room else { return BubbleSet(items: items, overflow: 0) }
        return BubbleSet(items: Array(items.prefix(room)), overflow: items.count - room)
    }

    /// A click on the closed island. An activity with a link opens it; a meeting reminder opens
    /// the island on Home, where it leads with its Join button; anything else opens the island.
    func activateClosedIsland(_ display: CGDirectDisplayID, presentation p: IslandPresentation) {
        if let a = focusedActivity(for: p) {
            if meetingReminder(for: a.id) != nil {
                select(tab: .home)
                setExpanded(display)
                return
            }
            if canOpen(a) {
                openActivity(a)
                return
            }
        }
        setExpanded(display)
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
    /// Snapshots only: draw a transition frozen part of the way through (`--snapshot-motion`).
    var frame: MotionFrame? = nil
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.snapshotMode) private var snapshotMode
    @ViewState private var dropTargeted = false
    /// The shape the island is moving towards and the one it came from, to tell an opening
    /// from a closing and to size the squash.
    @ViewState private var history = ShapeHistory()
    /// The bubbles beside the island and the ones before them, to tell which arrive and
    /// which leave, and to hold leaving ones for one more update.
    @ViewState private var bubbleHistory = BubbleHistory()

    /// One presentation's silhouette: its key, how big it is and its width.
    struct Settled: Equatable {
        var key: String
        var rank: Int
        var width: CGFloat
    }

    struct ShapeHistory: Equatable {
        var previous: Settled?
        var current: Settled?

        /// The shape a change to `key` started from: the one before the current one once the
        /// change has been recorded, the current one in the update that brings the change.
        func origin(for key: String) -> Settled? { current?.key == key ? previous : current }
    }

    struct BubbleHistory: Equatable {
        var previous = BubbleSet.none
        var current: BubbleSet?

        /// The bubbles a change to `now` started from, recorded or not yet.
        func before(_ now: BubbleSet) -> BubbleSet {
            guard let current else { return now }
            return current.key == now.key ? previous : current
        }
    }

    private var style: AnimationStyle {
        // The motion sheets always draw the full motion.
        if frame != nil { return .fluid }
        return AnimationStyle.effective(model.settings.animationStyle, reduceMotion: systemReduceMotion || model.settings.reduceMotion)
    }

    var body: some View {
        let p = model.presentation(for: display)
        let placement = model.placement(for: display, metrics: metrics)
        let look = model.look(for: display)
        let style = self.style
        let key = IslandLayout.key(p)
        let target = IslandLayout.geometry(for: p, metrics: metrics, wing: placement.wing, look: look)
        // Where the shell is coming from, and so whether it is opening (growing) or closing.
        let origin = history.origin(for: key)
        let fromG = frame.map { IslandLayout.geometry(for: $0.from, metrics: metrics, wing: placement.wing, look: look) }
        let fromRank = frame.map { IslandLayout.rank($0.from) } ?? origin?.rank ?? IslandLayout.rank(p)
        let opening = IslandLayout.rank(p) >= fromRank
        let fromWidth = fromG?.outerWidth ?? origin?.width ?? target.outerWidth
        let move = ShellMove(key: key, opening: opening, delta: target.outerWidth - fromWidth, stretches: style.stretches,
                             intoRow: IslandLayout.rank(p) <= 1)
        let g = frame.map { target.moved(from: fromG ?? target, by: IslandMotion.shellProgress(at: $0.t, opening: opening)) } ?? target
        // Resting on the notch shows the island growing out of it, even with nothing to show.
        let visible = IslandLayout.isVisible(p) || dropTargeted || (p == .idle && look.hoverGrow > 0)
        let fitted = model.fittedBubbles(for: p, placement: placement, metrics: metrics, display: display)
        let current = frame?.toBubbles ?? fitted.bubbles
        // The shell changing shape (opening, closing, a peek) rather than one closed island
        // giving way to another of the same shape.
        let fromKey = frame.map { IslandLayout.key($0.from) } ?? origin?.key ?? key
        let reshaping = fromKey != key && (fromRank != IslandLayout.rank(p) || abs(move.delta) > 0.5)
        // A bubble leaves with the transition attached in the last update it was drawn in,
        // and how it should leave (absorbed into the island or the bubble beside it, or
        // fading as the shell changes shape under it) is only known once it has to. So live,
        // leaving bubbles are drawn for one more update, wearing the right transition, and go
        // in the next.
        let before = frame.map { $0.fromBubbles ?? model.fittedBubbles(for: $0.from, placement: placement, metrics: metrics,
                                                                       display: display).bubbles }
            ?? bubbleHistory.before(current)
        let leaves = Set(before.items.map(\.key)).subtracting(current.items.map(\.key))
        let holding = frame == nil && !leaves.isEmpty && bubbleHistory.current.map { $0.key != current.key } ?? false
        let bubbles = holding ? before : current
        // Only bubbles that change in the same update as the shell's shape go with it; later
        // ones bud and merge as usual.
        let withShell = reshaping && (frame != nil || history.current.map { $0.key != key } ?? false)
        let slots = bubbleSlots(drawn: bubbles, before: before, after: current, reshaping: withShell, opening: opening)
        let left = model.settings.bubblePlacement == .left
        let bp = IslandLayout.bubblePlacement(metrics: metrics, placement: placement, count: bubbles.items.count, left: left)
        // How far the island's frame has grown on each side since the change began: bubbles
        // fading as the shell changes shape are laid out beside the new frame, and are moved
        // back by this much so they fade where they were instead of drifting over the menu bar.
        let shift = (g.outerWidth - fromWidth) / 2

        VStack(spacing: PageSwitcher.gap) {
            island(p, geometry: g, from: fromG, move: move, counted: fitted.counted)
                // Bubbles hang off the island's edge, behind it (so a bubble's goo flows out from
                // under the edge), and take no part in centring it: nothing a bubble does, coming
                // or going, can move the island. (Balancing them with spacers on the other side
                // let the island slide sideways while the two sides animated at different speeds.)
                .background(alignment: .top) {
                    // The shell's own frame on the canvas, for the bubbles to hang from.
                    Color.clear
                        .frame(width: g.outerWidth, height: g.size.height)
                        .background(alignment: left ? .topLeading : .topTrailing) {
                            HStack(alignment: .top, spacing: IslandLayout.bubbleGap) {
                                bubbleViews(slots, diameter: bp.diameter, top: bp.top, geometry: g, shift: shift)
                            }
                            .fixedSize()
                            // The row's inner edge sits one gap outside the island's body, measured
                            // from its side rather than from the flare at the top of the screen, so
                            // the first bubble is as far from the island as the next is from it.
                            .alignmentGuide(left ? HorizontalAlignment.leading : HorizontalAlignment.trailing) { d in
                                left ? d[HorizontalAlignment.trailing] + IslandLayout.bubbleGap - g.top
                                     : d[HorizontalAlignment.leading] - IslandLayout.bubbleGap + g.top
                            }
                        }
                }
            switcher(p)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        // Shape first: opening springs open at once; closing waits for the content to go.
        .animation(opening ? style.morph : style.collapse, value: key)
        .animation(style.morph, value: bubbles.key)
        .animation(style.morph, value: placement)
        // An approval card arriving on the open island (or answered) changes its shape between
        // the stem-and-body one and the full-width one: the shell morphs, as it does for a new
        // placement, instead of snapping.
        .animation(style.morph, value: look.stemmedOpen)
        // The hover response: a quick, small spring, in step with the others.
        .animation(style.inPlace, value: look.hoverGrow)
        // Appearing from nothing and going back to it. The animation wraps the ones above, so
        // it times only the fade and the shell keeps its spring.
        .opacity(presence(p, visible: visible))
        .animation(presenceAnimation(visible: visible), value: visible)
        .modifier(ShelfDropTarget(enabled: !snapshotMode && model.settings.shelfEnabled, targeted: $dropTargeted) { urls in
            model.addToShelf(urls)
        })
        .onChange(of: dropTargeted) { _, targeted in
            if targeted {
                model.select(tab: .shelf)
                model.setExpanded(display)
            }
        }
        .onChange(of: key, initial: true) { _, _ in
            history = ShapeHistory(previous: history.current,
                                   current: Settled(key: key, rank: IslandLayout.rank(p), width: target.outerWidth))
        }
        .onChange(of: current.key, initial: true) { _, _ in
            bubbleHistory = BubbleHistory(previous: bubbleHistory.current ?? .none, current: current)
        }
        .onChange(of: key + current.key) { _, _ in
            NotificationCenter.default.post(name: .isletLayoutChanged, object: nil)
        }
        .onChange(of: placement) { _, _ in
            NotificationCenter.default.post(name: .isletLayoutChanged, object: nil)
        }
        .fontDesign(model.settings.roundedFont ? .rounded : .default)
        .environment(\.islandReduceMotion, IslandLoops.holdStill(reduceMotion: model.settings.reduceMotion,
                                                                 animationOff: model.settings.animationStyle == .off))
        .environment(\.islandLoopsFrozen, model.settings.animationStyle == .off)
        .environment(\.islandMotion, style)
        .environment(\.visualiserStyle, model.settings.visualiserStyle)
        .environment(\.hiddenFromCapture, model.settings.hideFromScreenCapture)
        .environment(\.colorScheme, .dark)
    }

    /// How opaque the whole island is. It appears from nothing at once over a notch (it grows
    /// out of the black hardware) and with a quick fade without one; going back to nothing, it
    /// fades once the shell has closed onto the notch.
    private func presence(_ p: IslandPresentation, visible: Bool) -> Double {
        guard let frame else { return visible ? 1 : 0 }
        let was = IslandLayout.isVisible(frame.from), now = IslandLayout.isVisible(p)
        guard was != now else { return now ? 1 : 0 }
        return IslandMotion.presence(at: frame.t, showing: now, notch: !metrics.isSynthetic, pace: Motion.pace)
    }

    private func presenceAnimation(visible: Bool) -> Animation? {
        let k = Motion.pace
        switch style {
        case .off: return nil
        case .minimal: return .easeInOut(duration: 0.14 * k)
        default:
            if visible { return metrics.isSynthetic ? .easeOut(duration: IslandMotion.showFade * k) : nil }
            return .easeIn(duration: IslandMotion.hideFade * k).delay(IslandMotion.hideDelay * k)
        }
    }

    /// The shell, its content and the urgent glow.
    @ViewBuilder
    private func island(_ p: IslandPresentation, geometry g: IslandGeometry, from fromG: IslandGeometry?, move: ShellMove,
                        counted: Int) -> some View {
        // In a frozen frame the glow comes and goes with the content it belongs to: the old
        // one fading as its content leaves, the new one arriving with its content.
        let glows: [(color: Color, presentation: IslandPresentation, opacity: Double)] = {
            guard let frame else { return model.urgentGlow(for: p).map { [($0, p, 1)] } ?? [] }
            let delay = move.opening ? IslandMotion.contentDelay : IslandMotion.contentDelayClosing
            var list: [(Color, IslandPresentation, Double)] = []
            if let old = model.urgentGlow(for: frame.from) { list.append((old, frame.from, IslandMotion.contentLeft(at: frame.t))) }
            if let new = model.urgentGlow(for: p) { list.append((new, p, IslandMotion.contentReveal(at: frame.t, delay: delay))) }
            return list
        }()
        ZStack(alignment: .top) {
            ZStack(alignment: .top) {
                // A peek's glow spreads round it; the closed island's stays inside its edge (below).
                ForEach(Array(glows.enumerated()), id: \.offset) { _, glow in
                    if !Self.glowsInside(glow.presentation) {
                        if snapshotMode {
                            // As the live glow draws it (`GlowNSView`).
                            g.shape.fill(Color.black).shadow(color: glow.color.opacity(0.5), radius: 9)
                                .opacity(glow.opacity)
                        } else {
                            GlowPulse(color: NSColor(glow.color), cornerRadius: g.bottom)
                                .frame(width: g.outerWidth, height: g.size.height)
                        }
                    }
                }
                if let frame {
                    shell(p, geometry: g, stretch: IslandMotion.stretch(at: frame.t, opening: move.opening, delta: move.delta,
                                                                        intoRow: move.intoRow))
                        .environment(\.shellClock, ShellClock(t: frame.t, wasExpanded: frame.from == .expanded))
                } else {
                    ShellStretch(move: move) { stretch in shell(p, geometry: g, stretch: stretch) }
                }
                ForEach(Array(glows.enumerated()), id: \.offset) { _, glow in
                    if Self.glowsInside(glow.presentation) {
                        InnerGlow(shape: g.shape, color: glow.color)
                            .frame(width: g.outerWidth, height: g.size.height)
                            .opacity(glow.opacity)
                    }
                }
            }
            .frame(width: g.outerWidth, height: g.size.height, alignment: .top)
            contentLayer(p, geometry: g, from: fromG, opening: move.opening, counted: counted)
        }
        // A canvas as wide as the window, which never changes size, with the shell and the
        // content centred on it. The shell grows about its centre, and new content is drawn
        // where it ends up from its first frame. (Framed to the shell instead, the content was
        // laid out from the shell's left edge and rode on that edge as it moved out, so the
        // whole page slid left while the island opened.) Top-aligned: outgoing content keeps
        // its old, larger frame while it fades, and must not push the shell off the top of
        // the screen.
        .frame(maxWidth: .infinity, alignment: .top)
        .frame(height: g.size.height, alignment: .top)
        .keyframeAnimator(initialValue: CGFloat(1), trigger: model.pulse) { view, scale in
            // The closed island bounces only sideways, so it never dips below the menu bar row,
            // and no further than the room kept clear beside its wings, so it never covers a
            // menu bar item.
            view.scaleEffect(x: IslandMotion.pulseWidthScale(scale, rowWidth: g.stemWidth > 0 ? g.stemWidth : g.size.width),
                             y: IslandLayout.rank(p) <= 1 ? 1 : scale, anchor: .top)
        } keyframes: { _ in
            if style.bounces && model.settings.bounceOnActivity {
                SpringKeyframe(IslandMotion.pulsePeak, duration: 0.16, spring: .snappy)
                SpringKeyframe(1.0, duration: 0.45, spring: .bouncy)
            } else {
                LinearKeyframe(1.0, duration: 0.01)
            }
        }
        .contextMenu { islandMenu(p) }
    }

    /// The closed island (compact, a HUD in the row) keeps its urgent glow inside its edge, so
    /// nothing spills below the menu bar row or over the status items beside it.
    static func glowsInside(_ p: IslandPresentation) -> Bool { IslandLayout.rank(p) <= 1 }

    /// The island's surface and outline, `stretch` points wider on each side while it squashes.
    private func shell(_ p: IslandPresentation, geometry g: IslandGeometry, stretch: CGFloat) -> some View {
        let shape = g.stretched(by: stretch)
        // The teleprompter's "See-through while reading" turns the open island to clear glass.
        let seeThrough = p == .expanded && model.seeThroughPage
        // The open island's shadow. In a frozen frame it grows and goes with the shell, so a
        // closing island doesn't lose it at once nor an opening one wear it while still small.
        var shadow = p == .expanded ? 0.45 : 0
        if let frame, (frame.from == .expanded) != (p == .expanded) {
            let k = IslandMotion.shellProgress(at: frame.t, opening: p == .expanded)
            shadow = 0.45 * (p == .expanded ? k : 1 - k)
        }
        return ZStack {
            (seeThrough ? IslandTheme.glass : model.settings.theme)
                .background(expanded: p == .expanded, shape: shape, row: g.stemHeight, height: g.size.height,
                            glassLevel: seeThrough ? 1 : model.settings.glassLevel,
                            closedGlass: closedGlass,
                            stemmed: model.look(for: display).stemmedOpen)
                .shadow(color: .black.opacity(shadow), radius: 14, y: 6)
            IslandOutline(shape: shape, on: model.settings.outline)
        }
        .frame(width: max(0, g.outerWidth + 2 * stretch), height: g.size.height)
    }

    /// The closed island is glass too ("Glass on displays without a notch").
    private var closedGlass: Bool { metrics.isSynthetic && model.settings.glassOnNotchless }

    /// What the island shows. Content arrives after the shape: live, a transition that waits for
    /// the shell; in a frozen frame, the outgoing and incoming content at their progress.
    @ViewBuilder
    private func contentLayer(_ p: IslandPresentation, geometry g: IslandGeometry, from fromG: IslandGeometry?,
                              opening: Bool, counted: Int) -> some View {
        let detailed = model.settings.hudStyle == .detailed
        let stale = model.focusedActivity(for: p)?.isStale(at: Date()) ?? false
        if let frame, let fromG,
           IslandLayout.contentKey(frame.from, detailedHUD: detailed) != IslandLayout.contentKey(p, detailedHUD: detailed) {
            dressed(content(frame.from, geometry: fromG, counted: 0, row: nil), geometry: fromG, stale: false)
                .opacity(IslandMotion.contentLeft(at: frame.t))
            dressed(content(p, geometry: g, counted: counted, row: nil), geometry: g, stale: stale)
                .modifier(ContentReveal(progress: IslandMotion.contentReveal(
                    at: frame.t, delay: opening ? IslandMotion.contentDelay : IslandMotion.contentDelayClosing)))
        } else {
            dressed(content(p, geometry: g, counted: counted, row: frame), geometry: g, stale: stale)
                .id(IslandLayout.contentKey(p, detailedHUD: detailed))
                .transition(style.contentTransition(opening: opening))
        }
    }

    /// Content inside the shell: dimmed when out of date, clipped to the silhouette.
    private func dressed<V: View>(_ view: V, geometry g: IslandGeometry, stale: Bool) -> some View {
        view
            .opacity(stale ? 0.55 : 1)
            // Out-of-date content stops its spinner, glow and other looping motion.
            .environment(\.islandReduceMotion, IslandLoops.holdStill(reduceMotion: model.settings.reduceMotion,
                                                                     animationOff: model.settings.animationStyle == .off,
                                                                     stale: stale))
            .environment(\.islandLoopsFrozen, model.settings.animationStyle == .off || stale)
            .padding(.horizontal, g.top)
            .frame(width: g.outerWidth, height: g.size.height, alignment: .top)
            .clipShape(g.shape)
    }

    /// The page switcher floats under the open island once it has room (not over an approval):
    /// it rises in after the content and goes first when the island closes.
    @ViewBuilder
    private func switcher(_ p: IslandPresentation) -> some View {
        let shows = p == .expanded && model.approvals.current == nil
        if let frame {
            if shows {
                PageSwitcher(model: model)
                    .environment(\.switcherTime, frame.t - IslandMotion.switcherDelay)
            } else if frame.from == .expanded {
                let left = IslandMotion.contentLeft(at: frame.t, length: IslandMotion.switcherExit)
                PageSwitcher(model: model)
                    .opacity(left)
                    .offset(y: IslandMotion.switcherRise / 2 * CGFloat(1 - left))
            }
        } else if shows {
            PageSwitcher(model: model)
                // Only the switcher itself takes clicks, not the band it sits in.
                .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { model.controls.switcherWidth = $0 }
                .transition(SwitcherReveal.transition(style))
        }
    }

    /// A bubble beside the island, as drawn in this update: where it sits (0 next to the
    /// island), how it comes and goes, and, in a frozen frame, how far through it is.
    struct BubbleSlot: Identifiable {
        var bubble: IslandBubble
        var index: Int
        /// It buds from, and is absorbed into, the bubble nearer the island rather than the
        /// island itself (that bubble stays put while it moves).
        var fromNeighbour = false
        /// Arriving, it waits this long: for a closing shell to close, and for a bubble
        /// arriving nearer the island to settle first.
        var delay: Double = 0
        /// Leaving, it fades (the shell is changing shape under it) instead of being absorbed.
        var fades = false
        var leaving = false
        var split: Double? = nil
        var merge: Double? = nil
        var fade: Double? = nil
        var id: String { bubble.key }
    }

    /// Each bubble arriving after another, nearer the island, in the same update waits this
    /// much longer, so it buds off a bubble that is already there.
    static let budStagger = 0.2

    /// The bubbles to draw, nearest the island first, and how each comes and goes. In a
    /// frozen frame, bubbles that are leaving stay in place at their progress.
    private func bubbleSlots(drawn: BubbleSet, before: BubbleSet, after: BubbleSet, reshaping: Bool,
                             opening: Bool) -> [BubbleSlot] {
        let had = Set(before.items.map(\.key)), has = Set(after.items.map(\.key))
        var items = drawn.items
        if frame != nil {
            for (i, b) in before.items.enumerated() where !has.contains(b.key) && !items.contains(b) {
                items.insert(b, at: min(i, items.count))
            }
        }
        let k = Motion.pace
        let closingDelay = reshaping && !opening ? IslandMotion.budDelayClosing * k : 0
        var arrivingNearer = 0
        var slots: [BubbleSlot] = []
        for (i, b) in items.enumerated() {
            let arriving = !had.contains(b.key), leaving = !has.contains(b.key)
            let neighbourLeaving = i > 0 && !has.contains(items[i - 1].key)
            var slot = BubbleSlot(bubble: b, index: i)
            slot.fromNeighbour = i > 0 && !neighbourLeaving
            slot.delay = closingDelay + Double(arrivingNearer) * Self.budStagger * k
            slot.fades = reshaping
            slot.leaving = leaving
            if arriving { arrivingNearer += 1 }
            if let frame {
                if arriving {
                    slot.split = min(1, max(0, (frame.t - slot.delay) / (IslandMotion.splitDuration * k)))
                } else if leaving && reshaping {
                    slot.fade = min(1, max(0, frame.t / (IslandMotion.bubbleFade * k)))
                } else if leaving {
                    slot.merge = min(1, max(0, frame.t / (IslandMotion.mergeDuration * k)))
                }
            }
            slots.append(slot)
        }
        return slots
    }

    @ViewBuilder
    private func bubbleViews(_ slots: [BubbleSlot], diameter: CGFloat, top: CGFloat, geometry g: IslandGeometry,
                             shift: CGFloat) -> some View {
        let left = model.settings.bubblePlacement == .left
        // The island's end for the goo to join: a floating pill's round end or the notch
        // shape's rounded bottom corner. Glass would show the black goo through it, so then
        // the goo is cut away under the island and flows out of the glass's edge.
        let seeThrough = closedGlass && model.settings.theme == .glass
        let cap = metrics.floats ? GooCap(top: diameter / 2, bottom: diameter / 2, seeThrough: seeThrough)
                                 : GooCap(top: 0, bottom: min(g.bottom, diameter / 2), seeThrough: seeThrough)
        // Nearest the island first on both sides. Activities without a bubble are counted in
        // the island's wing ("+2"), never on a bubble.
        ForEach(left ? Array(slots.reversed()) : slots) { slot in
            let goo = gooShape(slot, diameter: diameter, geometry: g, left: left, cap: cap)
            BubbleView(bubble: slot.bubble, model: model, diameter: diameter, glass: seeThrough)
                .modifier(frozenGoo(slot, shape: goo))
                .modifier(CrossMorph(progress: 1 - (slot.fade ?? 0)))
                // Fading with the shell, it stays where it was while the island grows away from
                // it. The frame's move and this one animate together, so they cancel.
                .offset(x: slot.fades && slot.leaving ? (left ? 1 : -1) * shift : 0)
                .padding(.top, top)
                // Each bubble's goo passes under the bubbles nearer the island.
                .zIndex(-Double(slot.index))
                .transition(bubbleTransition(slot, shape: goo))
                .onTapGesture { model.setExpanded(display) }
                .contextMenu {
                    if case .activity(let a) = slot.bubble {
                        Button("Dismiss") { model.remove(activityID: a.id) }
                        Button("Mute “\(AppModel.mutedName(a.source))”") { model.mute(source: a.source) }
                    }
                }
                .spokenButton(slot.bubble.spokenLabel, value: slot.bubble.spokenValue,
                              hint: "Opens the island") { model.setExpanded(display) }
                .modifier(DismissAction(activity: slot.bubble.activity, model: model))
                // A bubble on its way out is gone as far as VoiceOver is concerned.
                .accessibilityHidden(slot.leaving)
        }
    }

    /// Where a bubble's goo runs: from the island's side (below its top flare) or from the
    /// edge of the bubble nearer the island, out to the bubble's resting centre.
    private func gooShape(_ slot: BubbleSlot, diameter: CGFloat, geometry g: IslandGeometry, left: Bool, cap: GooCap) -> GooBud {
        let gap = IslandLayout.bubbleGap
        let rest = slot.fromNeighbour ? gap + diameter / 2
            : gap + CGFloat(slot.index) * (diameter + gap) + diameter / 2
        return GooBud(progress: 1, kind: .split, diameter: diameter, rest: rest, left: left,
                      anchor: slot.fromNeighbour ? .bubble : .island(cap))
    }

    /// In a frozen frame, a bubble arriving or leaving at its progress; otherwise at rest.
    private func frozenGoo(_ slot: BubbleSlot, shape: GooBud) -> GooBud {
        var goo = shape
        if let split = slot.split {
            goo.progress = split
        } else if let merge = slot.merge {
            goo.kind = .merge
            goo.progress = 1 - merge
        }
        return goo
    }

    /// Bubbles bud out of the island's side (or the bubble beside them) like liquid and are
    /// pulled back into it when they go; as the shell changes shape they fade instead. With
    /// less motion they fade.
    private func bubbleTransition(_ slot: BubbleSlot, shape: GooBud) -> AnyTransition {
        guard style.isRich else { return style == .off ? .identity : .opacity }
        let k = Motion.pace
        func goo(_ kind: IslandMotion.BudKind, _ progress: Double) -> GooBud {
            var g = shape
            g.kind = kind
            g.progress = progress
            return g
        }
        let removal = slot.fades
            ? CrossMorph.transition.animation(.easeIn(duration: IslandMotion.bubbleFade * k))
            : AnyTransition.modifier(active: goo(.merge, 0), identity: goo(.merge, 1))
                .animation(.linear(duration: IslandMotion.mergeDuration * k))
        return .asymmetric(
            insertion: AnyTransition.modifier(active: goo(.split, 0), identity: goo(.split, 1))
                .animation(.linear(duration: IslandMotion.splitDuration * k).delay(slot.delay)),
            removal: removal
        )
    }

    /// Clicking an activity with a link opens it; a meeting reminder opens Home on it; anything
    /// else expands the island.
    private func activate(_ p: IslandPresentation) {
        Haptics.play(.tap)
        model.activateClosedIsland(display, presentation: p)
    }

    @ViewBuilder
    private func islandMenu(_ p: IslandPresentation) -> some View {
        if let a = model.focusedActivity(for: p) {
            if model.canOpen(a) { Button("Open") { model.openActivity(a) } }
            Button("Dismiss “\(a.title)”") { model.remove(activityID: a.id) }
            Button("Mute “\(AppModel.mutedName(a.source))”") { model.mute(source: a.source) }
            Divider()
        }
        Button(model.expandedScreen == nil ? "Open island" : "Close island") {
            model.setExpanded(model.expandedScreen == nil ? display : nil)
        }
        Button("Settings…") { AppActions.openSettings() }
        Divider()
        Button("Quit Islet") { NSApp.terminate(nil) }
    }

    /// - Parameter row: in a frozen frame whose content stays the row, the frame, so the row
    ///   can draw its own swaps at their progress.
    @ViewBuilder
    private func content(_ p: IslandPresentation, geometry g: IslandGeometry, counted: Int, row: MotionFrame?) -> some View {
        switch p {
        case .hidden, .idle:
            Color.clear
        case .hud, .compact, .sneak, .songPeek:
            // One branch for every state with the row, so moving between them keeps it in place.
            if case .hud(let hud) = p, model.settings.hudStyle == .detailed {
                DetailedHUDContent(hud: hud, metrics: metrics, tint: model.hudTint(hud.kind))
            } else {
                let hud = p.isHUD
                IslandRow(presentation: p, metrics: metrics, geometry: g, model: model, counted: counted, frame: row)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        if hud { return }
                        activate(p)
                    }
                    // One element for VoiceOver, pressed like a click (a HUD isn't pressed); the
                    // value comes from the wing that draws it (`SpokenText`).
                    .spokenButton(model.spokenLabel(for: p, counted: spokenCount(p, counted: counted)), value: model.spokenValue(for: p),
                                  hint: hud ? nil : model.focusedActivity(for: p).map { model.canOpen($0) ? "Opens it" : "Opens the island" }
                                      ?? "Opens the island", isButton: !hud) { activate(p) }
                    .modifier(DismissAction(activity: model.focusedActivity(for: p), model: model))
            }
        case .expanded:
            ApprovalGate(model: model, metrics: metrics) {
                ExpandedView(model: model, metrics: metrics, dropTargeted: dropTargeted, stemmed: model.look(for: display).stemmedOpen)
            }
        }
    }
}

extension IslandView {
    /// Other activities the closed island's wing counts ("+2"), as `IslandRow` counts them.
    func spokenCount(_ p: IslandPresentation, counted: Int) -> Int {
        switch p {
        case .compact(.activity(_, let others)): return model.settings.maxConcurrent == 1 ? others : counted
        case .compact(.nowPlaying): return counted
        default: return 0
        }
    }
}

/// Dismissing an activity is in its menu, which VoiceOver also offers as an action. The
/// action comes and goes with the activity; the view stays the same view.
struct DismissAction: ViewModifier {
    let activity: Activity?
    let model: AppModel

    func body(content: Content) -> some View {
        content.accessibilityActions {
            if let activity {
                Button("Dismiss") { model.remove(activityID: activity.id) }
            }
        }
    }
}

extension IslandPresentation {
    var isHUD: Bool {
        if case .hud = self { return true }
        return false
    }
}

extension IslandBubble {
    var activity: Activity? {
        if case .activity(let a) = self { return a }
        return nil
    }
}

extension IslandGeometry {
    /// This geometry `k` of the way from `start`, as SwiftUI's animation moves the frame and the
    /// shape (the wing is the new one at once: the content lays out for where it is going).
    func moved(from start: IslandGeometry, by k: Double) -> IslandGeometry {
        func mix(_ a: CGFloat, _ b: CGFloat) -> CGFloat { a + (b - a) * CGFloat(k) }
        var g = self
        g.size = CGSize(width: mix(start.size.width, size.width), height: mix(start.size.height, size.height))
        g.top = mix(start.top, top)
        g.bottom = mix(start.bottom, bottom)
        g.stemWidth = mix(start.stemWidth, stemWidth)
        g.stemHeight = mix(start.stemHeight, stemHeight)
        g.inset = mix(start.inset, inset)
        return g
    }

    /// The shape `d` points wider on each side, for the shell's squash and stretch. A shape
    /// that is one width from top to bottom (the closed island, the open island without a
    /// stem) stretches as a whole, so the closed island never grows a lip below its row; a
    /// stemmed one stretches only its body, so its stem stays the width of the row.
    func stretched(by d: CGFloat) -> IslandShape {
        var shape = self.shape
        shape.stemWidth = IslandMotion.stretchedStem(stemWidth, width: size.width, by: d)
        return shape
    }
}

/// "+2" in the closed island's wing: other activities without a bubble.
struct MoreCount: View {
    let count: Int
    @Environment(\.islandMotion) private var motion

    var body: some View {
        if count > 0 {
            Text("+\(count)")
                .textStyle(.caption, emphasized: true, numeric: true)
                .foregroundStyle(Color.islandSecondary)
                .fixedSize()
                .contentTransition(motion.numberSwap(value: Double(count)))
                .animation(motion.inPlace, value: count)
                .accessibilityLabel("\(count) more")
        }
    }
}

struct BubbleView: View {
    let bubble: IslandBubble
    let model: AppModel
    let diameter: CGFloat
    /// The island beside it is see-through glass (a display without a notch), so the bubble is too.
    var glass = false
    @Environment(\.islandMotion) private var motion
    @Environment(\.colorSchemeContrast) private var contrast

    /// What sits inside a bubble, in proportion to it, so the notch's bubble and the smaller
    /// pill's bubble look the same: a ring with clear space inside, a glyph in the ring, a
    /// glyph on its own, artwork.
    struct Sizes: Equatable {
        var ring: CGFloat
        var line: CGFloat
        var ringed: CGFloat
        var plain: CGFloat
        var appIcon: CGFloat

        init(diameter d: CGFloat) {
            ring = d * 0.8
            line = max(1.5, d * 0.07)
            ringed = d * 0.44
            plain = d * 0.6
            appIcon = d * 0.62
        }
    }

    var body: some View {
        let s = Sizes(diameter: diameter)
        ZStack {
            if glass {
                // The same glass and smoke as the pill beside it.
                GlassSurface(shape: Circle(), tint: Color.black.opacity(0.2), fallback: Color(white: 0.13).opacity(0.78))
                Circle().fill(Color.black.opacity(GlassMelt.standardSmoke))
            } else {
                Circle().fill(Color.black)
            }
            // Increase Contrast or "Subtle outline" edges a bubble as it does the island.
            if contrast == .increased {
                Circle().strokeBorder(IslandOutline.increasedEdge, lineWidth: IslandOutline.increasedWidth)
            } else if model.settings.outline {
                Circle().strokeBorder(IslandOutline.edge, lineWidth: IslandOutline.width)
            }
            switch bubble {
            case .media(let np):
                Group {
                    if np.artworkData == nil, np.artworkURL == nil, let bundle = np.bundleID, AppIconView.isInstalled(bundle) {
                        // No artwork: the player's own icon, which carries its own shape.
                        AppIconView(bundleID: bundle, size: s.appIcon)
                    } else {
                        TrackArtwork(media: np, size: s.ring, corner: s.ring / 2)
                    }
                }
                .opacity(np.isPlaying ? 1 : PausedLook.artworkOpacity)
                .animation(motion == .off ? nil : .easeInOut(duration: PausedLook.fade), value: np.isPlaying)
            case .activity(let a):
                if model.visualTemplate(for: a) != nil {
                    TemplateBubble(activity: a, model: model, diameter: diameter)
                } else if a.clampedProgress != nil, a.endsAt == nil, a.startedAt == nil {
                    // A ring only for real progress; a bubble that is just "working" stays a clean icon.
                    ProgressRing(progress: a.clampedProgress, tint: model.tint(for: a), size: s.ring, lineWidth: s.line)
                        .spokenValue(SpokenText.value(a, now: Date()))
                    IconView(icon: model.icon(for: a), size: s.ringed, tint: model.tint(for: a))
                } else {
                    IconView(icon: model.icon(for: a), size: s.plain, tint: model.tint(for: a))
                }
            }
        }
        .frame(width: diameter, height: diameter)
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

    /// Space between the island's edge and the wing's content: clear of the rounded bottom
    /// corner even in an icon-only wing, a little more in a roomy one.
    static func inset(for wing: CGFloat) -> CGFloat { wing < 46 ? Space.s : 11 }

    /// The room a wing leaves its content, from the inset to the notch's edge.
    static func room(for wing: CGFloat) -> CGFloat { max(0, wing - inset(for: wing)) }

    /// The leading glyph's size: 15 points where it fits, smaller in an icon-only wing so it,
    /// and a timer's ring round it, stay inside the room.
    static func glyph(for wing: CGFloat) -> CGFloat { max(8, min(15, room(for: wing) - Space.xs)) }

    var body: some View {
        let inset = Self.inset(for: wing)
        HStack(spacing: 0) {
            leading
                .padding(.leading, inset)
                .frame(width: wing, height: metrics.notch.height, alignment: .leading)
                .environment(\.wingRoom, Self.room(for: wing))
            Spacer(minLength: 0)
            trailing
                .padding(.trailing, inset)
                .frame(width: wing, height: metrics.notch.height, alignment: .trailing)
                .environment(\.wingRoom, Self.room(for: wing))
        }
        .frame(width: metrics.notch.width + 2 * wing, height: metrics.notch.height)
    }
}

/// The closed island's row beside the notch, and a peek's body below it. One view for the
/// compact island, the compact HUD and both peeks, so moving between them keeps the row in
/// place: the leading glyph and the trailing value swap on their own (a new activity's glyph
/// with one soft bounce, a value of another kind with a cross-morph), and a peek's body fades
/// in under the row once the shell has dropped.
struct IslandRow: View {
    let presentation: IslandPresentation
    let metrics: IslandMetrics
    let geometry: IslandGeometry
    let model: AppModel
    /// Other activities with no room for a bubble beside the island, counted in the wing.
    var counted = 0
    /// A transition frozen part of the way through (snapshots): the row draws both sides of
    /// each swap at their progress instead of running transitions.
    var frame: MotionFrame? = nil
    @Environment(\.islandMotion) private var motion

    var body: some View {
        VStack(spacing: 0) {
            Wings(metrics: metrics, wing: geometry.wing) {
                leadingSlot
            } trailing: {
                trailingSlot
            }
            .frame(maxWidth: .infinity)
            bodySlot
        }
    }

    // MARK: Swaps

    private var leadingSlot: some View {
        let p = presentation
        let arriving = Self.isActivity(p)
        return ZStack(alignment: .leading) {
            if let frame, Self.leadingKey(frame.from) != Self.leadingKey(p) {
                let t = frame.t
                leading(frame.from).modifier(CrossMorph(progress: IslandMotion.morphOut(at: t, pace: Motion.pace)))
                if arriving {
                    leading(p).modifier(GlyphArrival(progress: IslandMotion.glyphArrival(at: t, pace: Motion.pace)))
                } else {
                    leading(p).modifier(CrossMorph(progress: IslandMotion.morphIn(at: t, pace: Motion.pace)))
                }
            } else {
                leading(p)
                    .id(Self.leadingKey(p))
                    .transition(arriving ? motion.glyphTransition : motion.valueTransition)
            }
        }
    }

    private var trailingSlot: some View {
        let p = presentation
        return ZStack(alignment: .trailing) {
            if let frame, trailingKey(frame.from) != trailingKey(p) {
                trailing(frame.from).modifier(CrossMorph(progress: IslandMotion.morphOut(at: frame.t, pace: Motion.pace)))
                trailing(p).modifier(CrossMorph(progress: IslandMotion.morphIn(at: frame.t, pace: Motion.pace)))
            } else {
                trailing(p)
                    .id(trailingKey(p))
                    .transition(motion.valueTransition)
            }
        }
    }

    @ViewBuilder
    private var bodySlot: some View {
        let p = presentation
        if let frame, Self.bodyKey(frame.from) != Self.bodyKey(p) {
            ZStack(alignment: .topLeading) {
                if Self.bodyKey(frame.from) != nil {
                    peekBody(frame.from).opacity(IslandMotion.contentLeft(at: frame.t, pace: Motion.pace))
                }
                if Self.bodyKey(p) != nil {
                    peekBody(p).modifier(ContentReveal(progress: IslandMotion.contentReveal(at: frame.t, pace: Motion.pace)))
                }
            }
        } else if let key = Self.bodyKey(p) {
            // Content after the shape: the body waits for the shell to drop.
            peekBody(p)
                .id(key)
                .transition(motion.contentTransition(opening: true))
        }
    }

    // MARK: Keys

    private static func isActivity(_ p: IslandPresentation) -> Bool {
        switch p {
        case .compact(.activity), .sneak: return true
        default: return false
        }
    }

    /// Who the leading glyph belongs to: it swaps when this changes.
    static func leadingKey(_ p: IslandPresentation) -> String {
        switch p {
        case .compact(.nowPlaying), .songPeek: return "media"
        case .compact(.activity(let a, _)), .sneak(let a): return "activity-\(a.id)"
        case .compact(.battery): return "battery"
        case .hud(let hud): return "hud-\(hud.kind)"
        default: return "none"
        }
    }

    /// What kind of thing the trailing wing shows: a change of kind cross-morphs, a change of
    /// value within one kind changes in place.
    private func trailingKey(_ p: IslandPresentation) -> String {
        switch p {
        // The resting sticker is the same sticker the music plays: it carries on in place.
        case .compact(.nowPlaying), .songPeek, .compact(.sticker): return "indicator"
        case .compact(.activity(let a, _)), .sneak(let a): return "activity-\(a.id)-\(Self.trailingKind(a, model: model))"
        case .compact(.battery): return "percent"
        case .hud: return "level"
        default: return "none"
        }
    }

    /// The kind of value an activity's trailing wing shows.
    static func trailingKind(_ a: Activity, model: AppModel) -> String {
        let now = Date()
        switch model.visualTemplate(for: a) {
        case nil:
            if a.endsAt != nil || a.startedAt != nil { return "clock" }
            if a.trailing != nil || a.progress == nil { return a.trailingText(now: now) == nil ? "none" : "text" }
            return "ring"
        case .liveAudio? where a.templateTrailing(now: now) == nil: return "wave"
        case .media? where a.templateTrailing(now: now) == nil: return "indicator"
        case .score? where a.trailing == nil && a.teams?.count == 2: return "score"
        default: return "value"
        }
    }

    /// The peek's body, if any: a new key swaps it.
    private static func bodyKey(_ p: IslandPresentation) -> String? {
        switch p {
        case .sneak(let a): return "sneak-\(a.id)"
        case .songPeek: return "song"
        default: return nil
        }
    }

    // MARK: Parts

    @ViewBuilder
    private func leading(_ p: IslandPresentation) -> some View {
        switch p {
        case .compact(.nowPlaying(let np)), .songPeek(let np):
            // A new song swaps the artwork; the equaliser beside it keeps running.
            counting(Self.bodyKey(p) == nil ? counted : 0,
                     size: min(ClosedArtwork.size(metrics), Wings<EmptyView, EmptyView>.room(for: geometry.wing) - Space.xs)) { size in
                ClosedArtwork(media: np, model: model, size: size)
            }
        case .compact(.activity(let a, _)), .sneak(let a):
            // With bubbles off, or no room for them in the menu bar row, count the other
            // activities here instead.
            counting(activityCount(p), size: Wings<EmptyView, EmptyView>.glyph(for: geometry.wing)) { size in
                TemplateLeading(activity: a, model: model, tint: model.tint(for: a), size: size)
            }
        case .compact(.battery(let ev)):
            Image(systemName: BatteryGlyph.symbol(ev.state))
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(BatteryGlyph.tint(ev))
                .contentTransition(motion.symbolSwap)
                .animation(motion.inPlace, value: BatteryGlyph.symbol(ev.state))
        case .hud(let hud):
            Image(systemName: hud.symbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(model.hudTint(hud.kind))
                .contentTransition(motion.symbolSwap)
                .animation(motion.inPlace, value: hud.symbol)
        default:
            EmptyView()
        }
    }

    /// The leading glyph with the count of other activities beside it ("+2") when both fit
    /// before the notch: at `size`, then a little smaller and closer in a narrow wing, else the
    /// glyph alone. Nothing goes under the notch, where it can't be seen. VoiceOver says the
    /// count either way.
    private func counting<Lead: View>(_ count: Int, size: CGFloat, @ViewBuilder lead: (CGFloat) -> Lead) -> some View {
        return ViewThatFits(in: .horizontal) {
            HStack(spacing: Space.xs) {
                lead(size)
                MoreCount(count: count)
            }
            if count > 0 {
                HStack(spacing: Space.hair) {
                    lead(max(8, size - 3))
                    MoreCount(count: count)
                }
                HStack(spacing: Space.hair) {
                    lead(max(8, size - 5))
                    MoreCount(count: count)
                }
                // A timer's ring is wider than its glyph.
                HStack(spacing: Space.hair) {
                    lead(max(8, size - 8))
                    MoreCount(count: count)
                }
            }
            lead(size)
        }
    }

    private func activityCount(_ p: IslandPresentation) -> Int {
        guard case .compact(.activity(_, let others)) = p else { return 0 }
        return model.settings.maxConcurrent == 1 ? others : counted
    }

    @ViewBuilder
    private func trailing(_ p: IslandPresentation) -> some View {
        switch p {
        case .compact(.nowPlaying(let np)), .songPeek(let np):
            if model.settings.visualiserStyle == .gif {
                stickerWing(np.isPlaying ? .playing : .paused)
            } else {
                PlayingIndicator(tint: model.musicTint(np), playing: np.isPlaying)
            }
        case .compact(.sticker):
            stickerWing(.idle)
        case .compact(.activity(let a, _)), .sneak(let a):
            TemplateTrailing(activity: a, model: model, tint: model.tint(for: a))
        case .compact(.battery(let ev)):
            // Icon-only wings may have no room for "100%": the number alone beside the battery
            // glyph, never a shrunken one.
            WingValue(plan: WingPlan(full: "\(ev.state.level)%", short: "\(ev.state.level)", glyph: nil),
                      tint: BatteryGlyph.tint(ev), transition: motion.numberSwap(value: Double(ev.state.level)),
                      animation: motion.inPlace)
        case .hud(let hud):
            LevelBar(value: hud.muted ? 0 : hud.value, tint: model.hudTint(hud.kind), height: 4)
                .frame(width: max(22, geometry.wing - 20))
                .animation(motion == .off ? nil : .snappy(duration: 0.18), value: hud.value)
        default:
            EmptyView()
        }
    }

    /// The GIF look's sticker, in the row's height (a floating pill's is a little shorter) and
    /// allowed half the wing's edge space.
    private func stickerWing(_ mode: StickerMode) -> some View {
        StickerWing(model: model, mode: mode, row: metrics.notch.height - 2 * geometry.inset,
                    outerSpace: Wings<EmptyView, EmptyView>.inset(for: geometry.wing) / 2)
    }

    /// The peek's text, lined up under the wing's glyph so the peek reads as one column.
    @ViewBuilder
    private func peekBody(_ p: IslandPresentation) -> some View {
        let row = metrics.notch.width + 2 * geometry.wing
        let lead = max(Space.m, (geometry.size.width - row) / 2 + Wings<EmptyView, EmptyView>.inset(for: geometry.wing))
        switch p {
        case .sneak(let a):
            let tint = model.tint(for: a)
            VStack(alignment: .leading, spacing: Space.hair) {
                Text(a.title).textStyle(.headline).foregroundStyle(Ink.primary).lineLimit(1)
                TemplateDetail(activity: a, model: model) { details(a, tint: tint) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, lead)
            .padding(.top, Space.hair)
        case .songPeek(let np):
            TrackText(media: np) {
                VStack(alignment: .leading, spacing: Space.hair) {
                    Text(np.title).textStyle(.headline).foregroundStyle(Ink.primary).lineLimit(1)
                    if let by = np.artist ?? np.appName {
                        Text(by).textStyle(.caption).foregroundStyle(Ink.secondary).lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, lead)
            .padding(.top, Space.hair)
        default:
            EmptyView()
        }
    }

    @ViewBuilder
    private func details(_ a: Activity, tint: Color) -> some View {
        if let sub = a.subtitle {
            Text(sub).textStyle(.caption).foregroundStyle(Ink.secondary).lineLimit(1)
        }
        if a.clampedProgress != nil, a.state == .running {
            ActivityProgress(activity: a, tint: tint, height: 4).padding(.top, Space.hair)
        }
    }
}

/// The artwork beside the notch: corners from Settings (a turning record with Vinyl), and
/// dimmed while the music is paused, in step with the indicator settling. With "Show song
/// progress" a thin ring round it fills as the song plays; it sits outside the artwork, so the
/// artwork doesn't move.
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
        // Vinyl turns the artwork into a round record.
        let vinyl = model.settings.visualiserStyle == .vinyl
        let corner = vinyl ? size / 2 : model.artworkCorner(size: size, standard: 5)
        Group {
            if vinyl {
                VinylArtwork(media: media, size: size, tint: model.musicTint(media))
            } else {
                TrackArtwork(media: media, size: size, corner: corner)
            }
        }
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
    /// The symbol beside the notch, which the value's glyph never repeats.
    var leading: String? = nil
    @Environment(\.wingRoom) private var room
    @Environment(\.islandMotion) private var motion

    var body: some View {
        if activity.endsAt != nil || activity.startedAt != nil {
            TimelineView(.periodic(from: .now, by: 1)) { ctx in
                value(now: ctx.date, transition: .numericText(countsDown: activity.endsAt != nil), animation: nil)
                    .spokenValue(SpokenText.value(activity, now: ctx.date))
            }
        } else if activity.trailing != nil || activity.progress == nil, activity.trailingText(now: Date()) != nil {
            // A changed value rolls to the new one rather than popping.
            value(now: Date(), transition: motion.numberSwap(), animation: motion.inPlace)
                .spokenValue(SpokenText.value(activity, now: Date()))
        } else if activity.progress != nil {
            ProgressRing(progress: activity.clampedProgress, tint: tint, size: compact ? 13 : 15, lineWidth: 2.2)
                .spokenValue(SpokenText.value(activity, now: Date()))
        } else {
            EmptyView()
        }
    }

    private func value(now: Date, transition: ContentTransition, animation: Animation?) -> some View {
        let plan = activity.wingPlan(text: activity.trailingText(now: now) ?? "", narrow: room < NarrowValue.wordRoom,
                                     leading: leading, now: now)
        return WingValue(plan: plan, size: compact ? TextStyle.caption.size : nil, tint: tint, transition: transition,
                         animation: animation)
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
                    .contentTransition(motion.symbolSwap)
                    .animation(motion.inPlace, value: hud.symbol)
                    .frame(width: 18)
                LevelBar(value: hud.shownLevel, tint: tint, height: 5)
                    .animation(motion == .off ? nil : .snappy(duration: 0.18), value: hud.value)
                // Muted says so: "0%" would read as the level having been turned down.
                Text(hud.muted ? "Muted" : "\(percent)%")
                    .textStyle(.caption, emphasized: true, numeric: true)
                    .foregroundStyle(Ink.secondary)
                    .contentTransition(motion.numberSwap(value: Double(percent)))
                    .animation(motion == .off ? nil : .snappy(duration: 0.18), value: percent)
                    .fixedSize()
                    .frame(minWidth: 34, alignment: .trailing)
            }
            .padding(.horizontal, Space.l)
            .frame(height: IslandLayout.hudBody)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(SpokenText.hud(hud).label)
        .accessibilityValue(SpokenText.hud(hud).value)
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
