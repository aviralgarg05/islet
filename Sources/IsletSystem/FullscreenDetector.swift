import AppKit
import CoreGraphics
import Foundation

/// Detects when the frontmost app covers a whole display (fullscreen video, games,
/// presentations) so the island can get out of the way.
///
/// Uses `CGWindowListCopyWindowInfo` bounds and owner PIDs, which need no Screen Recording
/// permission (only window *titles* do). Re-evaluated on app activation and Space changes
/// rather than on a timer.
public final class FullscreenDetector {
    /// Called with the set of display IDs currently covered by a fullscreen window
    /// of the frontmost app, plus that app's bundle id.
    public var onChange: ((Set<CGDirectDisplayID>, String?) -> Void)?
    private var observers: [NSObjectProtocol] = []
    private var lastResult: (Set<CGDirectDisplayID>, String?)?

    public init() {}
    deinit { stop() }

    public func start() {
        let ws = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didActivateApplicationNotification, NSWorkspace.activeSpaceDidChangeNotification] {
            observers.append(ws.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                // Space-switch animations finish ~0.3 s later; evaluate after they settle.
                self?.evaluate()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { self?.evaluate() }
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
    }

    public func evaluate() {
        let front = NSWorkspace.shared.frontmostApplication
        let covered = Self.coveredDisplays(frontPID: front?.processIdentifier)
        let result = (covered, front?.bundleIdentifier)
        if let last = lastResult, last.0 == result.0, last.1 == result.1 { return }
        lastResult = result
        onChange?(covered, front?.bundleIdentifier)
    }

    /// Display IDs where `frontPID` owns a window spanning the display and the menu bar is gone.
    public static func coveredDisplays(frontPID: pid_t?) -> Set<CGDirectDisplayID> {
        guard let pid = frontPID,
              let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]]
        else { return [] }
        var count: UInt32 = 0
        CGGetActiveDisplayList(0, nil, &count)
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        CGGetActiveDisplayList(count, &ids, &count)
        let displays = ids.map { ($0, CGDisplayBounds($0)) }
        let menuLevel = Int(CGWindowLevelForKey(.mainMenuWindow))

        var windows: [CGRect] = []
        var menuBars: [CGRect] = []
        for w in list {
            guard let b = w[kCGWindowBounds as String] as? [String: CGFloat],
                  let x = b["X"], let y = b["Y"], let width = b["Width"], let height = b["Height"] else { continue }
            let rect = CGRect(x: x, y: y, width: width, height: height)
            let layer = w[kCGWindowLayer as String] as? Int ?? 0
            if layer == menuLevel { menuBars.append(rect) }
            if layer == 0, (w[kCGWindowOwnerPID as String] as? pid_t) == pid { windows.append(rect) }
        }
        var covered = Set<CGDirectDisplayID>()
        for (id, bounds) in displays {
            let hasMenuBar = menuBars.contains { $0.intersects(bounds) && $0.minY <= bounds.minY + 1 }
            if hasMenuBar { continue }
            if windows.contains(where: { covers(window: $0, display: bounds) }) { covered.insert(id) }
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
}
