import IsletCore
import SwiftUI

/// The tab buttons left of the notch share that space with nothing else, and the notch hides
/// whatever spills past it. Tabs that don't fit go into a "more" menu instead.
enum TabStripFit {
    static let tabWidth: CGFloat = 28
    static let gap: CGFloat = 2

    /// Width left of the notch in the expanded island's top row (16 pt side padding, 6 pt clear of the notch).
    static func regionWidth(_ metrics: IslandMetrics) -> CGFloat {
        max(0, (metrics.expanded.width - 32 - metrics.notch.width - 12) / 2)
    }

    /// Tabs to show, and the rest for the menu (which then takes the last slot).
    static func split(_ tabs: [IslandTab], width: CGFloat) -> (shown: [IslandTab], more: [IslandTab]) {
        let slots = max(1, Int((width + gap) / (tabWidth + gap)))
        guard tabs.count > slots else { return (tabs, []) }
        let shown = max(0, slots - 1)
        return (Array(tabs.prefix(shown)), Array(tabs.dropFirst(shown)))
    }
}

/// "More" button for the tabs that didn't fit; lit when one of them is selected.
struct TabOverflowMenu: View {
    let model: AppModel
    let tabs: [IslandTab]
    @Environment(\.snapshotMode) private var snapshotMode

    var body: some View {
        let selected = tabs.contains(model.tab)
        let label = Image(systemName: selected ? model.tab.symbol : "ellipsis")
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(selected ? Color.white : Color.islandTertiary)
            .frame(width: TabStripFit.tabWidth, height: 22)
            .background(RoundedRectangle(cornerRadius: 7).fill(selected ? Color.islandFill : .clear))
            .contentShape(Rectangle())
        if snapshotMode {
            label
        } else {
            Menu {
                ForEach(tabs) { tab in
                    Button {
                        Haptics.play(.tap)
                        model.select(tab: tab)
                    } label: {
                        Label(tab.title, systemImage: tab.symbol)
                    }
                }
            } label: {
                label
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("More")
        }
    }
}
