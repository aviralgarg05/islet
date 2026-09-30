import AppKit
import ApplicationServices
import IsletCore

/// Measures what occupies the menu bar next to the notch, so the closed island can size its
/// wings to fit the free space instead of covering menu bar icons.
///
/// Reads frames only (no titles or values) through Accessibility, which the user grants in
/// Settings. Without that permission `measure` returns nil and Islet uses narrow wings.
///
/// On macOS 27 one read of MenuBarAgent's menu bar window gives every item's frame, a few
/// milliseconds with no calls into other apps. Elsewhere it falls back to asking the apps that own
/// status items: asking one without any runs into the timeout (20–50 ms, and wakes it), so that
/// list is built once and kept current from launch and quit events.
public enum MenuBarInspector {
    public static var isAvailable: Bool { AXIsProcessTrusted() }

    static let agentBundleID = "com.apple.MenuBarAgent"

    private static let queue = DispatchQueue(label: "islet.menubar", qos: .utility)

    // Guarded by `queue`.
    private static var owners: Set<pid_t> = []
    private static var ownersBuiltAt: Date?
    /// Rebuild the owner list this often, for apps that add a status item long after launch.
    private static let ownersMaxAge: TimeInterval = 15 * 60

    /// Measure asynchronously; the completion runs on the main queue.
    /// - Parameters:
    ///   - notch: notch rect in AppKit global coordinates (origin bottom-left).
    ///   - screenFrame: the notch display's frame in AppKit global coordinates.
    public static func measure(notch: CGRect, screenFrame: CGRect, completion: @escaping (MenuBarOccupancy?) -> Void) {
        guard isAvailable else { return completion(nil) }
        let running = NSWorkspace.shared.runningApplications
        let candidates = running.filter { $0.activationPolicy != .prohibited }.map(\.processIdentifier)
        let agent = running.first { $0.bundleIdentifier == agentBundleID }?.processIdentifier
        let front = NSWorkspace.shared.frontmostApplication?.processIdentifier
        let primaryHeight = NSScreen.screens.first?.frame.height ?? screenFrame.maxY
        queue.async {
            // macOS 27: MenuBarAgent's menu bar window lists every item with its frame, so no
            // other app needs to be asked.
            if let agent {
                let row = CGRect(x: screenFrame.minX, y: primaryHeight - screenFrame.maxY, width: screenFrame.width, height: notch.height)
                let slots = MenuBarAgentScanner.slots(agent: agent, display: row, readContent: false)
                if !slots.isEmpty {
                    let menus = frontMenus(front, notch: notch, screenFrame: screenFrame, primaryHeight: primaryHeight)
                    let chevron = slots.first { $0.kind == .overflowButton }?.frame
                    let extras = slots.filter { $0.kind != .overflowButton }.map(\.frame)
                    let result = MenuBarOccupancy.from(menuFrames: menus, statusFrames: extras, chevron: chevron, notch: notch)
                    DispatchQueue.main.async { completion(result) }
                    return
                }
            }
            if ownersBuiltAt.map({ Date().timeIntervalSince($0) > ownersMaxAge }) ?? true {
                owners = Set(candidates.filter { $0 != agent && hasExtras($0) })
                ownersBuiltAt = Date()
            }
            let live = Set(candidates)
            owners.formIntersection(live)
            let result = occupancy(owners: Array(owners), agent: agent, front: front, notch: notch,
                                   screenFrame: screenFrame, primaryHeight: primaryHeight)
            DispatchQueue.main.async { completion(result) }
        }
    }

    /// A new app may own status items; check it once it has had time to add them.
    public static func appLaunched(_ pid: pid_t) {
        queue.asyncAfter(deadline: .now() + 2) {
            guard ownersBuiltAt != nil, isAvailable, hasExtras(pid) else { return }
            owners.insert(pid)
        }
    }

    public static func appTerminated(_ pid: pid_t) {
        queue.async { owners.remove(pid) }
    }

    static func hasExtras(_ pid: pid_t) -> Bool {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.05)
        guard let bar = element(app, kAXExtrasMenuBarAttribute) else { return false }
        return !children(bar).isEmpty
    }

    static func occupancy(owners: [pid_t], agent: pid_t?, front: pid_t?, notch: CGRect, screenFrame: CGRect,
                          primaryHeight: CGFloat) -> MenuBarOccupancy {
        // AX uses top-left global coordinates; convert the menu bar row of this screen.
        let rowTop = primaryHeight - screenFrame.maxY
        let rowBottom = rowTop + max(notch.height, 24)
        func inRow(_ r: CGRect) -> Bool { r.midY >= rowTop && r.midY <= rowBottom && r.maxX > screenFrame.minX && r.minX < screenFrame.maxX }

        let menus = frontMenus(front, notch: notch, screenFrame: screenFrame, primaryHeight: primaryHeight)
        var extras: [CGRect] = []
        var chevron: CGRect?
        if let agent {
            let app = AXUIElementCreateApplication(agent)
            AXUIElementSetMessagingTimeout(app, 0.15)
            if let bar = element(app, kAXExtrasMenuBarAttribute) {
                for item in children(bar) {
                    let f = frame(item)
                    guard inRow(f), f.width > 0 else { continue }
                    // The overflow chevron is the bar's only button; its label is localised, its role isn't.
                    if string(item, kAXRoleAttribute) == kAXButtonRole, string(item, kAXIdentifierAttribute) == nil {
                        chevron = f
                    } else {
                        extras.append(f)
                    }
                }
            }
        }
        for pid in owners {
            let app = AXUIElementCreateApplication(pid)
            AXUIElementSetMessagingTimeout(app, 0.15)
            guard let bar = element(app, kAXExtrasMenuBarAttribute) else { continue }
            for item in children(bar) {
                let f = frame(item)
                if inRow(f), f.width > 0 { extras.append(f) }
            }
        }
        return MenuBarOccupancy.from(menuFrames: menus, statusFrames: extras, chevron: chevron, notch: notch)
    }

    /// The frontmost app's menus in this screen's menu bar row (AX coordinates; x matches AppKit).
    static func frontMenus(_ front: pid_t?, notch: CGRect, screenFrame: CGRect, primaryHeight: CGFloat) -> [CGRect] {
        guard let front else { return [] }
        let rowTop = primaryHeight - screenFrame.maxY
        let rowBottom = rowTop + max(notch.height, 24)
        let app = AXUIElementCreateApplication(front)
        AXUIElementSetMessagingTimeout(app, 0.25)
        guard let bar = element(app, kAXMenuBarAttribute) else { return [] }
        // The Apple menu and app menus; skip empty placeholders.
        return children(bar).map(frame).filter {
            $0.width > 0 && $0.midY >= rowTop && $0.midY <= rowBottom && $0.maxX > screenFrame.minX && $0.minX < screenFrame.maxX
        }
    }

    static func element(_ e: AXUIElement, _ name: String) -> AXUIElement? {
        var v: CFTypeRef?
        guard AXUIElementCopyAttributeValue(e, name as CFString, &v) == .success, let v, CFGetTypeID(v) == AXUIElementGetTypeID() else { return nil }
        return (v as! AXUIElement)
    }

    static func string(_ e: AXUIElement, _ name: String) -> String? {
        var v: CFTypeRef?
        guard AXUIElementCopyAttributeValue(e, name as CFString, &v) == .success else { return nil }
        return v as? String
    }

    static func children(_ e: AXUIElement) -> [AXUIElement] {
        var v: CFTypeRef?
        guard AXUIElementCopyAttributeValue(e, kAXChildrenAttribute as CFString, &v) == .success else { return [] }
        return (v as? [AXUIElement]) ?? []
    }

    static func frame(_ e: AXUIElement) -> CGRect {
        var p = CGPoint.zero, s = CGSize.zero
        var v: CFTypeRef?
        if AXUIElementCopyAttributeValue(e, kAXPositionAttribute as CFString, &v) == .success, let v, CFGetTypeID(v) == AXValueGetTypeID() {
            AXValueGetValue(v as! AXValue, .cgPoint, &p)
        }
        if AXUIElementCopyAttributeValue(e, kAXSizeAttribute as CFString, &v) == .success, let v, CFGetTypeID(v) == AXValueGetTypeID() {
            AXValueGetValue(v as! AXValue, .cgSize, &s)
        }
        return CGRect(origin: p, size: s)
    }

    /// Convert a notch rect from AppKit (bottom-left) to AX (top-left) global coordinates.
    public static func axRect(_ r: CGRect) -> CGRect {
        let primaryHeight = NSScreen.screens.first?.frame.height ?? r.maxY
        return CGRect(x: r.minX, y: primaryHeight - r.maxY, width: r.width, height: r.height)
    }
}
