import AppKit
import IsletCore
import SwiftUI

/// The switcher that floats under the open island: a glass capsule with Home, Today and Shelf
/// (or up to four pages chosen in Settings) and a "more" menu for the rest, whose highlight
/// slides to the selected page. Beside it, two
/// discs for the things you start rather than visit: a timer on the left and Ask on the right.
///
/// It sits over the desktop, not on the island, so it is the one place the island uses Liquid
/// Glass in the Black theme too (and never glass on glass in the Glass theme).
///
/// When the island opens, the capsule and then the discs rise into place after the content
/// (`SwitcherReveal`, `RiseIn`).
///
/// The capsule keeps one width whichever page is showing: the highlight is as wide as the
/// longest name it may hold, and with no page of its own selected (Ask, a new timer) the
/// segments share that width. So the discs never move out from under the pointer.
struct PageSwitcher: View {
    let model: AppModel
    @Namespace private var highlight
    @Environment(\.islandMotion) private var motion

    /// Height of the capsule and the discs.
    static let height: CGFloat = 32
    /// Gap between the island and the switcher.
    static let gap: CGFloat = Space.s
    /// Room the switcher needs under the island, with a little for its shadow.
    static let band: CGFloat = gap + height + Space.m
    /// The capsule's padding around the selected page's highlight (concentric: 16 − 3 = 13).
    private static let inset: CGFloat = 3
    /// A page's glyph, the same width for every page so the highlight's width is the name's.
    private static let glyph: CGFloat = 16
    /// An unselected segment.
    private static let segmentWidth: CGFloat = 36

    var body: some View {
        let pages = Self.pages(model)
        let moreSelected = pages.more.contains(model.tab)
        // The highlight fits the longest name it may hold: the capsule's pages and the page
        // the "more" segment shows now.
        let highlight = Self.highlightWidth(for: pages.main.map(\.title) + (moreSelected ? [model.tab.title] : []))
        // The capsule's pages and More, which is always there.
        let segments = pages.main.count + 1
        let capsule = highlight + CGFloat(max(0, segments - 1)) * Self.segmentWidth
        let anySelected = moreSelected || pages.main.contains(model.tab) && !model.timers.isEntering
        // With none of its pages selected, the segments share the capsule's width.
        let shared = anySelected ? nil : capsule / CGFloat(max(1, segments))
        let selectedWidth = shared ?? highlight
        let otherWidth = shared ?? Self.segmentWidth
        GlassGroup(spacing: Space.s) {
            HStack(spacing: Space.s) {
                disc(symbol: "timer", help: "New timer", selected: model.tab == .home && model.timers.isEntering) {
                    if model.tab == .home && model.timers.isEntering {
                        model.timers.isEntering = false
                    } else {
                        model.select(tab: .home)
                        model.timers.isEntering = true
                    }
                }
                HStack(spacing: 0) {
                    ForEach(pages.main) { tab in
                        let selected = model.tab == tab && !model.timers.isEntering
                        segment(symbol: tab.symbol, title: tab.title, selected: selected, width: selected ? selectedWidth : otherWidth) {
                            model.timers.isEntering = false
                            model.select(tab: tab)
                        }
                    }
                    // A menu of the other pages, whichever one it shows: "More pages, Weather".
                    // It stays with no page under it too, for keep awake, keep open, Settings,
                    // Send feedback and Quit.
                    segment(symbol: moreSelected ? model.tab.symbol : "ellipsis",
                            title: moreSelected ? model.tab.title : nil, selected: moreSelected,
                            width: moreSelected ? selectedWidth : otherWidth,
                            spoken: (label: "More pages", value: moreSelected ? model.tab.title : "",
                                     hint: "Shows the other pages, keep awake, keep open and Settings")) {
                        showMore(pages.more)
                    }
                }
                .frame(width: capsule)
                .padding(Self.inset)
                .floatingGlass(Capsule())
                .accessibilityElement(children: .contain)
                .accessibilityLabel("Pages")
                // It buds off the island first; the discs follow a moment later.
                .modifier(RiseIn(index: 0))
                disc(symbol: IslandTab.ask.symbol, help: "Ask", selected: model.tab == .ask) {
                    model.select(tab: model.tab == .ask ? .home : .ask)
                }
            }
        }
        // Always its own width: while the island opens or closes, bubbles still beside it can
        // leave the switcher less room than it needs, and that must not squeeze the selected
        // page's name over its neighbour.
        .fixedSize()
        .frame(height: Self.height)
        .shadow(color: .black.opacity(0.25), radius: 8, y: 3)
        // The highlight slides on the settle spring; a short fade with less motion, none with Off.
        .animation(motion.inPlace, value: model.tab)
        .animation(motion.inPlace, value: model.timers.isEntering)
    }

    /// The highlight's width for the longest of `titles`: its glyph, the name and the padding.
    static func highlightWidth(for titles: [String]) -> CGFloat {
        let font = NSFont.systemFont(ofSize: TextStyle.body.size, weight: .semibold)
        let name = titles.map { ceil(($0 as NSString).size(withAttributes: [.font: font]).width) }.max() ?? 0
        return max(segmentWidth, glyph + Space.xs + name + 2 * Space.m)
    }

    /// One page in the capsule. The selected one shows its name on the sliding highlight.
    /// - Parameter spoken: what VoiceOver says in place of the title, for the "more" menu.
    private func segment(symbol: String, title: String?, selected: Bool, width: CGFloat,
                         spoken: (label: String, value: String, hint: String)? = nil,
                         action: @escaping () -> Void) -> some View {
        Button {
            Haptics.play(.tap)
            action()
        } label: {
            HStack(spacing: Space.xs) {
                Image(systemName: symbol)
                    .font(.system(size: 12, weight: .semibold))
                    .frame(width: Self.glyph)
                if selected, let title {
                    Text(title)
                        .textStyle(.body, emphasized: true)
                        .lineLimit(1)
                        .fixedSize()
                        .transition(.opacity)
                }
            }
            .foregroundStyle(selected ? Ink.primary : Ink.secondary)
            .frame(width: width, height: Self.height - 2 * Self.inset)
            .background {
                if selected {
                    Capsule().fill(Wash.strong).contrastEdge(Capsule()).matchedGeometryEffect(id: "highlight", in: highlight)
                }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help(spoken == nil ? title ?? "" : "More")
        .accessibilityLabel(spoken?.label ?? title ?? "More")
        .accessibilityValue(spoken?.value ?? "")
        .accessibilityHint(spoken?.hint ?? "")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    /// A round glass button beside the capsule.
    private func disc(symbol: String, help: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button {
            Haptics.play(.tap)
            action()
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(selected ? Ink.primary : Ink.secondary)
                .frame(width: Self.height, height: Self.height)
                .background { if selected { Circle().fill(Wash.strong).contrastEdge(Circle()).padding(Self.inset) } }
                .contentShape(Circle())
        }
        .buttonStyle(PressableStyle())
        .floatingGlass(Circle())
        .modifier(RiseIn(index: 1))
        .help(help)
        .accessibilityLabel(help)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    /// Pages whose feature is on, split between the capsule and the "more" menu in the order
    /// set in Settings → General (`IslandPage.switcher`). Clipboard is listed only while
    /// clipboard history is on.
    static func pages(_ model: AppModel) -> (main: [IslandTab], more: [IslandTab]) {
        let split = IslandPage.switcher(model.settings, current: IslandPage(rawValue: model.tab.rawValue))
        func tabs(_ pages: [IslandPage]) -> [IslandTab] { pages.compactMap { IslandTab(rawValue: $0.rawValue) } }
        return (tabs(split.main), tabs(split.more))
    }

    /// The rest of the pages, then keep awake, keep open and Settings.
    private func showMore(_ tabs: [IslandTab]) {
        var items = tabs.map { tab in
            IslandMenu.Item(title: tab.title, symbol: tab.symbol, checked: model.tab == tab) {
                model.timers.isEntering = false
                model.select(tab: tab)
            }
        }
        if !items.isEmpty { items.append(.separator) }
        let awake = model.controls.awake
        var awakeItems = KeepAwake.presets.map { preset in
            IslandMenu.Item(title: preset.title) { model.setKeepAwake(.start(minutes: preset.minutes), announce: false) }
        }
        if awake != nil {
            awakeItems.append(.separator)
            awakeItems.append(IslandMenu.Item(title: "Turn off") { model.setKeepAwake(.stop, announce: false) })
        }
        items.append(IslandMenu.Item(title: "Keep awake", symbol: "cup.and.saucer", checked: awake != nil, children: awakeItems))
        // Also beside the notch in the Black and Graphite themes; the Glass theme's stem has no room.
        items.append(IslandMenu.Item(title: "Keep open", symbol: "pin", checked: model.pinned) { model.pinned.toggle() })
        items.append(IslandMenu.Item(title: "Settings…", symbol: "gearshape") { AppActions.openSettings() })
        // Opens the issue form in the browser; nothing is sent from here.
        items.append(IslandMenu.Item(title: "Send feedback", symbol: "bubble.left",
                                     children: Feedback.Kind.allCases.map { kind in
                                         IslandMenu.Item(title: kind.title) { AppActions.sendFeedback(kind) }
                                     }))
        items.append(.separator)
        items.append(IslandMenu.Item(title: "Quit Islet", symbol: "power") { NSApp.terminate(nil) })
        IslandMenu.show(items, model: model)
    }
}

/// Gives a little when pressed; no hover wash (the glass reacts on its own).
struct PressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? Motion.pressScale : 1)
            .animation(Motion.settle, value: configuration.isPressed)
    }
}
