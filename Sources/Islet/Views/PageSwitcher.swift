import AppKit
import IsletCore
import SwiftUI

/// The switcher that floats under the open island: a glass capsule with Home, Today and Shelf
/// and a "more" menu for the rest, whose highlight slides to the selected page. Beside it, two
/// discs for the things you start rather than visit: a timer on the left and Ask on the right.
///
/// It sits over the desktop, not on the island, so it is the one place the island uses Liquid
/// Glass in the Black theme too (and never glass on glass in the Glass theme).
///
/// When the island opens, the capsule and then the discs rise into place after the content
/// (`SwitcherReveal`, `RiseIn`).
struct PageSwitcher: View {
    let model: AppModel
    @Namespace private var highlight

    /// Height of the capsule and the discs.
    static let height: CGFloat = 32
    /// Gap between the island and the switcher.
    static let gap: CGFloat = Space.s
    /// Room the switcher needs under the island, with a little for its shadow.
    static let band: CGFloat = gap + height + Space.m
    /// The capsule's padding around the selected page's highlight (concentric: 16 − 3 = 13).
    private static let inset: CGFloat = 3

    var body: some View {
        let pages = Self.pages(model)
        let moreSelected = pages.more.contains(model.tab)
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
                        segment(symbol: tab.symbol, title: tab.title, selected: model.tab == tab && !model.timers.isEntering) {
                            model.timers.isEntering = false
                            model.select(tab: tab)
                        }
                    }
                    if !pages.more.isEmpty {
                        segment(symbol: moreSelected ? model.tab.symbol : "ellipsis",
                                title: moreSelected ? model.tab.title : nil, selected: moreSelected) {
                            showMore(pages.more)
                        }
                        .help("More")
                    }
                }
                .padding(Self.inset)
                .floatingGlass(Capsule())
                // It buds off the island first; the discs follow a moment later.
                .modifier(RiseIn(index: 0))
                disc(symbol: IslandTab.ask.symbol, help: "Ask", selected: model.tab == .ask) {
                    model.select(tab: model.tab == .ask ? .home : .ask)
                }
            }
        }
        .frame(height: Self.height)
        .shadow(color: .black.opacity(0.25), radius: 8, y: 3)
        .animation(Motion.settle, value: model.tab)
        .animation(Motion.settle, value: model.timers.isEntering)
    }

    /// One page in the capsule. The selected one shows its name on the sliding highlight.
    private func segment(symbol: String, title: String?, selected: Bool, action: @escaping () -> Void) -> some View {
        Button {
            Haptics.play(.tap)
            action()
        } label: {
            HStack(spacing: Space.xs) {
                Image(systemName: symbol)
                    .font(.system(size: 12, weight: .semibold))
                if selected, let title {
                    Text(title)
                        .textStyle(.body, emphasized: true)
                        .lineLimit(1)
                        .fixedSize()
                        .transition(.opacity)
                }
            }
            .foregroundStyle(selected ? Ink.primary : Ink.secondary)
            .padding(.horizontal, selected && title != nil ? Space.m : 0)
            .frame(minWidth: 36, minHeight: Self.height - 2 * Self.inset)
            .background {
                if selected {
                    Capsule().fill(Wash.strong).matchedGeometryEffect(id: "highlight", in: highlight)
                }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help(title ?? "")
        .accessibilityLabel(title ?? "More")
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
                .background { if selected { Circle().fill(Wash.strong).padding(Self.inset) } }
                .contentShape(Circle())
        }
        .buttonStyle(PressableStyle())
        .floatingGlass(Circle())
        .modifier(RiseIn(index: 1))
        .help(help)
        .accessibilityLabel(help)
    }

    /// Pages that got a switch in Settings, split between the capsule and the "more" menu.
    static func pages(_ model: AppModel) -> (main: [IslandTab], more: [IslandTab]) {
        let s = model.settings
        var main: [IslandTab] = [.home]
        if s.calendarEnabled || s.remindersEnabled { main.append(.today) }
        if s.shelfEnabled { main.append(.shelf) }
        var more: [IslandTab] = [.clipboard]
        if s.pluginsEnabled { more.append(.widgets) }
        if s.systemStatsEnabled { more.append(.stats) }
        // A page opened some other way (a drop, the API) still shows where you are.
        if model.tab != .ask, !main.contains(model.tab), !more.contains(model.tab) { more.append(model.tab) }
        return (main, more)
    }

    /// The rest of the pages, then keep awake, keep open and Settings.
    private func showMore(_ tabs: [IslandTab]) {
        var items = tabs.map { tab in
            IslandMenu.Item(title: tab.title, symbol: tab.symbol, checked: model.tab == tab) {
                model.timers.isEntering = false
                model.select(tab: tab)
            }
        }
        items.append(.separator)
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
