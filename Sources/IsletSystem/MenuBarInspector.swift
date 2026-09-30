import AppKit
import ApplicationServices
import IsletCore

/// Measures what occupies the menu bar next to the notch, so the closed island can size its
/// wings to fit or drop below the notch instead of covering menu bar icons.
///
/// Reads frames only (no titles or values) through Accessibility, which the user grants in
/// Settings. Without that permission `measure` returns nil and Islet uses the drop layout.
public enum MenuBarInspector {
    public static var isAvailable: Bool { AXIsProcessTrusted() }

    private static let queue = DispatchQueue(label: "islet.menubar", qos: .utility)

    /// Measure asynchronously; the completion runs on the main queue.
    /// - Parameters:
    ///   - notch: notch rect in AppKit global coordinates (origin bottom-left).
    ///   - screenFrame: the notch display's frame in AppKit global coordinates.
    public static func measure(notch: CGRect, screenFrame: CGRect, completion: @escaping (MenuBarOccupancy?) -> Void) {
        guard isAvailable else { return completion(nil) }
        let apps = NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy != .prohibited || $0.bundleIdentifier == "com.apple.MenuBarAgent" }
            .map(\.processIdentifier)
        let front = NSWorkspace.shared.frontmostApplication?.processIdentifier
        let primaryHeight = NSScreen.screens.first?.frame.height ?? screenFrame.maxY
        queue.async {
            let result = occupancy(apps: apps, front: front, notch: notch, screenFrame: screenFrame, primaryHeight: primaryHeight)
            DispatchQueue.main.async { completion(result) }
        }
    }

    static func occupancy(apps: [pid_t], front: pid_t?, notch: CGRect, screenFrame: CGRect, primaryHeight: CGFloat) -> MenuBarOccupancy {
        // AX uses top-left global coordinates; convert the menu bar row of this screen.
        let rowTop = primaryHeight - screenFrame.maxY
        let rowBottom = rowTop + max(notch.height, 24)
        func inRow(_ r: CGRect) -> Bool { r.midY >= rowTop && r.midY <= rowBottom && r.maxX > screenFrame.minX && r.minX < screenFrame.maxX }

        var menus: [CGRect] = []
        if let front {
            let app = AXUIElementCreateApplication(front)
            AXUIElementSetMessagingTimeout(app, 0.25)
            if let bar = element(app, kAXMenuBarAttribute) {
                // The Apple menu and app menus; skip empty placeholders.
                menus = children(bar).map(frame).filter { inRow($0) && $0.width > 0 }
            }
        }
        var extras: [CGRect] = []
        for pid in apps {
            let app = AXUIElementCreateApplication(pid)
            AXUIElementSetMessagingTimeout(app, 0.15)
            guard let bar = element(app, kAXExtrasMenuBarAttribute) else { continue }
            for item in children(bar) {
                let f = frame(item)
                if inRow(f), f.width > 0 { extras.append(f) }
            }
        }
        return MenuBarOccupancy.from(menuFrames: menus, statusFrames: extras, notch: notch)
    }

    static func element(_ e: AXUIElement, _ name: String) -> AXUIElement? {
        var v: CFTypeRef?
        guard AXUIElementCopyAttributeValue(e, name as CFString, &v) == .success, let v, CFGetTypeID(v) == AXUIElementGetTypeID() else { return nil }
        return (v as! AXUIElement)
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
