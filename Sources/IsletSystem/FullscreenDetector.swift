import AppKit
import ApplicationServices
import CoreGraphics
import Foundation
import IsletCore

/// Detects which app covers each display (fullscreen video, games, presentations) so the
/// island can get out of the way there, whichever app is in front.
///
/// Uses `CGWindowListCopyWindowInfo` bounds and owner PIDs, which need no Screen Recording
/// permission (only window *titles* do). With Accessibility, a window that fills the screen is
/// checked with `AXFullScreen`. Re-evaluated on app activation and Space changes (and twice
/// more shortly after, `FullscreenCoverage.followUpLooks`) rather than on a timer.
public final class FullscreenDetector {
    /// Called with the app covering each covered display (its bundle id, "" when it has none),
    /// and the frontmost app's bundle id.
    public var onChange: (([CGDirectDisplayID: String], String?) -> Void)?
    private var observers: [NSObjectProtocol] = []
    private var lastResult: ([CGDirectDisplayID: String], String?)?
    private var followUps: [DispatchWorkItem] = []

    public init() {}
    deinit { stop() }

    public func start() {
        let ws = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didActivateApplicationNotification, NSWorkspace.activeSpaceDidChangeNotification] {
            observers.append(ws.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                self?.evaluate()
                self?.lookAgainShortly()
            })
        }
        observers.append(NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.evaluate() })
        evaluate()
    }

    public func stop() {
        for o in observers {
            NSWorkspace.shared.notificationCenter.removeObserver(o)
            NotificationCenter.default.removeObserver(o)
        }
        observers.removeAll()
        followUps.forEach { $0.cancel() }
        followUps.removeAll()
    }

    /// Space switches animate for a moment, and a game may go full screen a second or two after
    /// it comes to the front: look again then. A newer change replaces the pending looks.
    private func lookAgainShortly() {
        followUps.forEach { $0.cancel() }
        followUps = FullscreenCoverage.followUpLooks.map { delay in
            let work = DispatchWorkItem { [weak self] in self?.evaluate() }
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
            return work
        }
    }

    public func evaluate() {
        let front = NSWorkspace.shared.frontmostApplication
        var covered: [CGDirectDisplayID: String] = [:]
        for (display, pid) in Self.coveringApps() {
            covered[display] = NSRunningApplication(processIdentifier: pid)?.bundleIdentifier ?? ""
        }
        let result = (covered, front?.bundleIdentifier)
        if let last = lastResult, last.0 == result.0, last.1 == result.1 { return }
        lastResult = result
        onChange?(covered, front?.bundleIdentifier)
    }

    /// The app (pid) covering each display now (`FullscreenCoverage`).
    public static func coveringApps() -> [CGDirectDisplayID: pid_t] {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]]
        else { return [:] }
        var count: UInt32 = 0
        CGGetActiveDisplayList(0, nil, &count)
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        CGGetActiveDisplayList(count, &ids, &count)
        let displays = ids.map { DisplayArea(id: $0, bounds: CGDisplayBounds($0)) }
        let windows: [ScreenWindow] = list.compactMap { w in
            guard let b = w[kCGWindowBounds as String] as? [String: CGFloat],
                  let x = b["X"], let y = b["Y"], let width = b["Width"], let height = b["Height"],
                  let pid = w[kCGWindowOwnerPID as String] as? pid_t else { return nil }
            return ScreenWindow(bounds: CGRect(x: x, y: y, width: width, height: height),
                                layer: w[kCGWindowLayer as String] as? Int ?? 0, pid: pid)
        }
        return FullscreenCoverage.coveringApps(windows: windows, displays: displays,
                                               menuLevel: Int(CGWindowLevelForKey(.mainMenuWindow)),
                                               menuBarAutoHides: menuBarAutoHides, isFullscreen: axFullScreen)
    }

    /// Whether the menu bar hides itself everywhere (System Settings > Control Centre).
    static var menuBarAutoHides: Bool { UserDefaults.standard.bool(forKey: "_HIHideMenuBar") }

    /// Accessibility's word on whether `pid`'s window at `bounds` is in full screen, or nil
    /// without Accessibility or when the window can't be found. Asked only about a window that
    /// already fills a display without a menu bar, with a short timeout.
    static func axFullScreen(pid: pid_t, bounds: CGRect) -> Bool? {
        guard AXIsProcessTrusted() else { return nil }
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.1)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &value) == .success,
              let windows = value as? [AXUIElement] else { return nil }
        for window in windows {
            guard let frame = frame(of: window), abs(frame.minX - bounds.minX) < 2, abs(frame.minY - bounds.minY) < 2,
                  abs(frame.width - bounds.width) < 2, abs(frame.height - bounds.height) < 2 else { continue }
            var full: CFTypeRef?
            guard AXUIElementCopyAttributeValue(window, "AXFullScreen" as CFString, &full) == .success else { return nil }
            return (full as? Bool) ?? (full as? NSNumber)?.boolValue
        }
        return nil
    }

    /// A window's position and size, in the same top-left coordinates as the window list.
    private static func frame(of window: AXUIElement) -> CGRect? {
        var pos: CFTypeRef?, size: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window, kAXPositionAttribute as CFString, &pos) == .success,
              AXUIElementCopyAttributeValue(window, kAXSizeAttribute as CFString, &size) == .success,
              let pos, let size, CFGetTypeID(pos) == AXValueGetTypeID(), CFGetTypeID(size) == AXValueGetTypeID() else { return nil }
        var p = CGPoint.zero, s = CGSize.zero
        guard AXValueGetValue(pos as! AXValue, .cgPoint, &p), AXValueGetValue(size as! AXValue, .cgSize, &s) else { return nil }
        return CGRect(origin: p, size: s)
    }

    /// Kept for callers of the old check: see `FullscreenCoverage.covers`.
    public static func covers(window: CGRect, display: CGRect, topAllowance: CGFloat = 40) -> Bool {
        FullscreenCoverage.covers(window: window, display: display, topAllowance: topAllowance)
    }
}
