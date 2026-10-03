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
/// more shortly after, `FullscreenCoverage.followUpLooks`) rather than on a timer. With
/// Accessibility it also follows the windows of the app in front, so a video or a game that goes
/// full screen in place (no new Space, no app switch) is noticed, and so is it leaving.
public final class FullscreenDetector {
    /// Called with the app covering each covered display (its bundle id, "" when it has none),
    /// and the frontmost app's bundle id.
    public var onChange: (([CGDirectDisplayID: String], String?) -> Void)?
    private var observers: [NSObjectProtocol] = []
    private var lastResult: ([CGDirectDisplayID: String], String?)?
    /// What the last look read, with the answer it gave (`coveringApps()`).
    private var lastLook: (windows: [ScreenWindow], displays: [DisplayArea], menuBarAutoHides: Bool,
                           trusted: Bool, covered: [CGDirectDisplayID: pid_t])?
    private var followUps: [DispatchWorkItem] = []
    /// Follows the windows of the app in front (`watchFrontApp`).
    private var windowObserver: AXObserver?
    private var watchedPID: pid_t = 0
    private var windowLooks: [DispatchWorkItem] = []
    /// The app being set up to follow, while its notifications are added off the main thread.
    private var pendingPID: pid_t = 0
    /// Bumped each time the app to follow changes, so a setup that finishes late is dropped.
    private var watchGeneration = 0
    /// Adding an observer's notifications asks the app itself, once per notification; a busy app
    /// takes a while to answer, so that happens here and not on the main thread.
    private let axQueue = DispatchQueue(label: "dev.islet.fullscreen.ax", qos: .utility)

    public init() {}
    deinit { stop() }

    public func start() {
        let ws = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didActivateApplicationNotification, NSWorkspace.activeSpaceDidChangeNotification] {
            observers.append(ws.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                self?.evaluate()
                self?.lookAgainShortly()
                // Accessibility is checked again each time, so a grant takes effect at the next switch.
                if note.name == NSWorkspace.didActivateApplicationNotification { self?.watchFrontApp() }
            })
        }
        observers.append(NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            self?.evaluate()
            self?.lookAgainShortly()
        })
        evaluate()
        watchFrontApp()
    }

    public func stop() {
        for o in observers {
            NSWorkspace.shared.notificationCenter.removeObserver(o)
            NotificationCenter.default.removeObserver(o)
        }
        observers.removeAll()
        followUps.forEach { $0.cancel() }
        followUps.removeAll()
        unwatchFrontApp()
    }

    // MARK: The app in front

    /// What the app in front's windows announce, on the app itself: no per-window bookkeeping.
    /// A window closing shows up as another taking the focus, or as the app leaving the front.
    static let windowNotifications = [kAXWindowMovedNotification, kAXWindowResizedNotification, kAXWindowCreatedNotification,
                                      kAXFocusedWindowChangedNotification, kAXWindowMiniaturizedNotification,
                                      kAXWindowDeminiaturizedNotification]

    /// Follows the windows of the app now in front, with Accessibility. Without it, there is
    /// no event to follow them by, and Islet doesn't poll: app switches and Space changes still
    /// catch full screen.
    private func watchFrontApp() {
        let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier ?? 0
        guard FullscreenCoverage.followsWindows(of: pid, trusted: AXIsProcessTrusted(), ownPID: getpid()) else {
            unwatchFrontApp()
            return
        }
        guard pid != watchedPID && pid != pendingPID else { return }
        unwatchFrontApp()
        watchGeneration += 1
        let generation = watchGeneration
        pendingPID = pid
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        axQueue.async { [weak self] in
            var obs: AXObserver?
            let callback: AXObserverCallback = { _, _, _, refcon in
                guard let refcon else { return }
                Unmanaged<FullscreenDetector>.fromOpaque(refcon).takeUnretainedValue().windowChanged()
            }
            guard AXObserverCreate(pid, callback, &obs) == .success, let obs else {
                // Tried again the next time this app comes to the front.
                DispatchQueue.main.async { if let self, self.watchGeneration == generation { self.pendingPID = 0 } }
                return
            }
            let app = AXUIElementCreateApplication(pid)
            AXUIElementSetMessagingTimeout(app, Self.axTimeout)
            for name in Self.windowNotifications { AXObserverAddNotification(obs, app, name as CFString, refcon) }
            DispatchQueue.main.async {
                // Another app came to the front meanwhile: this one isn't followed.
                guard let self, self.watchGeneration == generation else { return }
                CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(obs), .defaultMode)
                self.windowObserver = obs
                self.watchedPID = pid
                self.pendingPID = 0
            }
        }
    }

    private func unwatchFrontApp() {
        if let windowObserver {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(windowObserver), .defaultMode)
        }
        windowObserver = nil
        watchedPID = 0
        pendingPID = 0
        watchGeneration += 1
        windowLooks.forEach { $0.cancel() }
        windowLooks.removeAll()
    }

    /// A window of the app in front changed: look once it has settled
    /// (`FullscreenCoverage.windowChangeLooks`). A newer change replaces the pending looks.
    private func windowChanged() {
        windowLooks.forEach { $0.cancel() }
        windowLooks = FullscreenCoverage.windowChangeLooks.map { delay in
            let work = DispatchWorkItem { [weak self] in self?.evaluate() }
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
            return work
        }
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
        for (display, pid) in coveringApps() {
            covered[display] = NSRunningApplication(processIdentifier: pid)?.bundleIdentifier ?? ""
        }
        let result = (covered, front?.bundleIdentifier)
        if let last = lastResult, last.0 == result.0, last.1 == result.1 { return }
        lastResult = result
        onChange?(covered, front?.bundleIdentifier)
    }

    /// The app covering each display, worked out again only when something it rests on has
    /// changed. A window event fires for every move, resize and title change of the app in front,
    /// and each is looked at twice (`FullscreenCoverage.windowChangeLooks`), so most looks read
    /// the very same windows; the answer then follows, and the costly part can be skipped. That
    /// part is asking Accessibility about every window that fills a display, which has a timeout
    /// of its own and happens on the main thread.
    ///
    /// Everything the answer rests on is compared, not hashed, so nothing can be missed: the
    /// windows, the displays, whether the menu bar hides itself and whether Accessibility is
    /// allowed (a grant must take effect at the next look, as it did before). A window
    /// Accessibility couldn't answer about keeps nothing, so the second look does ask again.
    private func coveringApps() -> [CGDirectDisplayID: pid_t] {
        let (windows, displays) = Self.windowsAndDisplays()
        let autoHides = Self.menuBarAutoHides
        let trusted = AXIsProcessTrusted()
        if let last = lastLook, last.windows == windows, last.displays == displays,
           last.menuBarAutoHides == autoHides, last.trusted == trusted {
            return last.covered
        }
        var unanswered = false
        let covered = FullscreenCoverage.coveringApps(
            windows: windows, displays: displays, menuLevel: Int(CGWindowLevelForKey(.mainMenuWindow)),
            menuBarAutoHides: autoHides,
            isFullscreen: { pid, bounds in
                let answer = Self.axFullScreen(pid: pid, bounds: bounds)
                if answer == nil { unanswered = true }
                return answer
            }
        )
        lastLook = unanswered ? nil : (windows, displays, autoHides, trusted, covered)
        return covered
    }

    /// The app (pid) covering each display now (`FullscreenCoverage`).
    public static func coveringApps() -> [CGDirectDisplayID: pid_t] {
        let (windows, displays) = windowsAndDisplays()
        return FullscreenCoverage.coveringApps(windows: windows, displays: displays,
                                               menuLevel: Int(CGWindowLevelForKey(.mainMenuWindow)),
                                               menuBarAutoHides: menuBarAutoHides, isFullscreen: axFullScreen)
    }

    /// The windows on screen and the displays they lie on, as the window list gives them.
    static func windowsAndDisplays() -> (windows: [ScreenWindow], displays: [DisplayArea]) {
        var count: UInt32 = 0
        CGGetActiveDisplayList(0, nil, &count)
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        CGGetActiveDisplayList(count, &ids, &count)
        let displays = ids.map { DisplayArea(id: $0, bounds: CGDisplayBounds($0)) }
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]]
        else { return ([], displays) }
        let windows: [ScreenWindow] = list.compactMap { w in
            guard let b = w[kCGWindowBounds as String] as? [String: CGFloat],
                  let x = b["X"], let y = b["Y"], let width = b["Width"], let height = b["Height"],
                  let pid = w[kCGWindowOwnerPID as String] as? pid_t else { return nil }
            return ScreenWindow(bounds: CGRect(x: x, y: y, width: width, height: height),
                                layer: w[kCGWindowLayer as String] as? Int ?? 0, pid: pid)
        }
        return (windows, displays)
    }

    /// How long one Accessibility call about a window may take before it gives up.
    static let axTimeout: Float = 0.1

    /// Whether the menu bar hides itself everywhere (System Settings > Control Centre).
    static var menuBarAutoHides: Bool { UserDefaults.standard.bool(forKey: "_HIHideMenuBar") }

    /// Accessibility's word on whether `pid`'s window at `bounds` is in full screen, or nil
    /// without Accessibility or when the window can't be found. Asked only about a window that
    /// already fills a display without a menu bar, with a short timeout.
    static func axFullScreen(pid: pid_t, bounds: CGRect) -> Bool? {
        guard AXIsProcessTrusted() else { return nil }
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, axTimeout)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &value) == .success,
              let windows = value as? [AXUIElement] else { return nil }
        for window in windows.prefix(8) {
            // Each element has its own timeout (the app's isn't inherited), and this runs on the
            // main thread: a game too busy to answer must not hold up the island for seconds.
            AXUIElementSetMessagingTimeout(window, axTimeout)
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
