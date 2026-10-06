import CoreGraphics
import Foundation

/// A window on screen, as the window list describes it: where, at what level and whose. No
/// title (that would need Screen Recording).
public struct ScreenWindow: Equatable, Sendable {
    /// In the window list's coordinates: origin at the top left of the main display, y down.
    public var bounds: CGRect
    public var layer: Int
    public var pid: Int32

    public init(bounds: CGRect, layer: Int, pid: Int32) {
        self.bounds = bounds
        self.layer = layer
        self.pid = pid
    }
}

/// A display, in the window list's coordinates (`CGDisplayBounds`).
public struct DisplayArea: Equatable, Sendable {
    public var id: UInt32
    public var bounds: CGRect

    public init(id: UInt32, bounds: CGRect) {
        self.id = id
        self.bounds = bounds
    }
}

/// Which app is in full screen on which display, whichever app is in front: a video in full
/// screen on the built-in display stays "in full screen" while you work on the external one.
public enum FullscreenCoverage {
    /// The app covering each display: one whose menu bar has gone, where the frontmost ordinary
    /// window that spans the display has no other app's window in front of it. The same app's
    /// smaller windows in front don't count against it: a browser's "Press Esc to exit full
    /// screen" bubble, its link preview or a player's controls are windows of their own.
    /// - Parameters:
    ///   - windows: front to back, as the window list gives them.
    ///   - menuLevel: the menu bar's window level.
    ///   - menuBarAutoHides: the menu bar hides itself everywhere (System Settings), so its
    ///     absence proves nothing: a window that fills the screen counts only when
    ///     `isFullscreen` confirms it.
    ///   - isFullscreen: Accessibility's word on an app's window (`AXFullScreen`), or nil when
    ///     it can't be asked. A window it says isn't in full screen never counts.
    public static func coveringApps(windows: [ScreenWindow], displays: [DisplayArea], menuLevel: Int, menuBarAutoHides: Bool,
                                    isFullscreen: (Int32, CGRect) -> Bool? = { _, _ in nil }) -> [UInt32: Int32] {
        var covered: [UInt32: Int32] = [:]
        for display in displays {
            let d = display.bounds
            let hasMenuBar = windows.contains { $0.layer == menuLevel && $0.bounds.intersects(d) && $0.bounds.minY <= d.minY + 1 }
            if hasMenuBar { continue }
            // The ordinary windows on this display, front to back.
            let onDisplay = windows.filter { $0.layer == 0 && d.contains(CGPoint(x: $0.bounds.midX, y: $0.bounds.midY)) }
            guard let i = onDisplay.firstIndex(where: { covers(window: $0.bounds, display: d) }) else { continue }
            let front = onDisplay[i]
            // Another app's window in front of it: that's a desktop, not full screen.
            if onDisplay[..<i].contains(where: { $0.pid != front.pid }) { continue }
            let confirmed = isFullscreen(front.pid, front.bounds)
            if confirmed == false || (menuBarAutoHides && confirmed != true) { continue }
            covered[display.id] = front.pid
        }
        return covered
    }

    /// A window counts as fullscreen when it spans the display. On notched displays macOS
    /// places fullscreen content below the camera housing by default, so the top edge may
    /// start up to `topAllowance` points down.
    public static func covers(window: CGRect, display: CGRect, topAllowance: CGFloat = 40) -> Bool {
        window.minX <= display.minX + 1 && window.maxX >= display.maxX - 1
            && window.minY <= display.minY + topAllowance && window.maxY >= display.maxY - 1
    }

    /// After an app comes to the front or the Space changes, when to look again: the switch
    /// animates for a moment, and a game may take a second or two to go full screen.
    public static let followUpLooks: [TimeInterval] = [0.6, 2]

    /// After a window of the app in front moves, resizes, appears or takes the focus (a video
    /// or a game going full screen without changing Space, and back): when to look, counted
    /// from the last change, so a window being dragged is looked at once it stops.
    public static let windowChangeLooks: [TimeInterval] = [0.25, 1]

    /// Whether the app in front has its windows followed: only with Accessibility, and never
    /// Casement itself (asking its own main thread would wait on itself).
    public static func followsWindows(of pid: Int32, trusted: Bool, ownPID: Int32) -> Bool {
        trusted && pid > 0 && pid != ownPID
    }
}
