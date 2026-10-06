import AppKit
import CasementCore
import CasementSystem

/// Opaque black panel laid over one of the menu bar's own Live Activity pills, so the activity
/// shows in the island only. Nothing is drawn inside it: no icon, no text, just black.
///
/// It is a panel of its own rather than part of the island, which is only as wide as the island
/// and would not always reach the pill. Clicks pass straight through to macOS's pill underneath,
/// so Apple's own view still opens from the menu bar.
final class MenuBarCoverPanel: NSPanel {
    init() {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isFloatingPanel = true
        // 26: above the menu bar (24) and its status items (25), below the island (27).
        level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 2)
        // Transient, not stationary: stationary windows stay drawn over Mission Control's Spaces bar.
        collectionBehavior = [.canJoinAllSpaces, .transient, .fullScreenAuxiliary, .ignoresCycle]
        isOpaque = true
        backgroundColor = .black
        hasShadow = false
        isMovable = false
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        ignoresMouseEvents = true
        animationBehavior = .none
        let black = NSView()
        black.wantsLayer = true
        black.layer?.backgroundColor = NSColor.black.cgColor
        contentView = black
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// Keeps the covers over the menu bar's Live Activity pills ("Hide the menu bar's own"). One
/// panel per covered pill, placed from the frames the mirror publishes, and ordered out again
/// the moment a cover would be wrong (`MenuBarCovers`). Nothing here polls: `update()` is called
/// when the pills change, when the island's silhouette changes, when an app goes full screen,
/// when the displays change, when settings change and when this login session changes.
@MainActor
final class MenuBarCoverController {
    private let model: AppModel
    private var panels: [MenuBarCoverPanel] = []
    /// The covers on screen now, and whether they were hidden from screen capture, so an update
    /// that changes nothing touches no window.
    private var shown: [CGRect] = []
    private var shownHiddenFromCapture: Bool?

    init(model: AppModel) {
        self.model = model
    }

    /// The display that carries the menu bar: the primary one, whose AppKit origin is (0, 0) and
    /// whose top left is where Accessibility's coordinates start. It is the only menu bar the
    /// mirror reads.
    static var menuBarScreen: NSScreen? {
        NSScreen.screens.first { $0.frame.origin == .zero }
    }

    /// Where the covers belong now, as window frames.
    private var wanted: [CGRect] {
        guard let screen = Self.menuBarScreen else { return [] }
        let display = screen.displayID
        // The island has to be on that display and showing there, since it is where the activity
        // appears instead.
        let islandShows = display.map { model.islandDisplays.contains($0) && model.presentation(for: $0) != .hidden } ?? false
        let height = screen.frame.maxY - screen.visibleFrame.maxY
        let input = MenuBarCovers.Input(
            hideOwn: model.settings.hideMenuBarActivities,
            mirroring: model.settings.mirrorMenuBarActivities,
            supported: model.liveActivitiesSupported,
            trusted: model.accessibilityTrusted,
            inFront: SessionWork.runs(sessionActive: model.sessionActive),
            islandShows: islandShows,
            // A full screen app over that display takes the menu bar with it.
            menuBarShows: display.map { model.fullscreenApps[$0] == nil } ?? false,
            menuBarHeight: height,
            menuBarTop: screen.frame.maxY,
            uncoveredKeys: model.uncoveredMenuBarPillKeys
        )
        return MenuBarCovers.covers(pills: model.menuBarPills, input)
    }

    func update() {
        let rects = wanted
        let hiddenFromCapture = model.settings.hideFromScreenCapture
        guard rects != shown || hiddenFromCapture != shownHiddenFromCapture else { return }
        shown = rects
        shownHiddenFromCapture = hiddenFromCapture
        while panels.count < rects.count { panels.append(MenuBarCoverPanel()) }
        for (i, panel) in panels.enumerated() {
            guard i < rects.count else {
                if panel.isVisible { panel.orderOut(nil) }
                continue
            }
            let sharing: NSWindow.SharingType = hiddenFromCapture ? .none : .readOnly
            if panel.sharingType != sharing { panel.sharingType = sharing }
            if panel.frame != rects[i] { panel.setFrame(rects[i], display: false) }
            if !panel.isVisible { panel.orderFrontRegardless() }
        }
    }
}
