import AppKit
import ApplicationServices
import IsletCore

/// Reads the menu bar as macOS 27 builds it: MenuBarAgent keeps one window per Space and display,
/// and each window has a slot for every item, including the ones collapsed into the overflow
/// (which `AXExtrasMenuBar` leaves out). One window per display is enough; they all carry the
/// same items.
///
/// Only MenuBarAgent's own items and the Live Activity renderer's content are read. A slot that
/// belongs to another app is recorded by its frame and bundle ID and never walked into.
public enum MenuBarAgentScanner {
    public static let agentBundleID = "com.apple.MenuBarAgent"

    /// One item in the menu bar.
    public struct Slot {
        public var frame: CGRect
        /// The element to press or observe: the menu bar item itself when there is one.
        public var element: AXUIElement
        public var info: MenuBarItemInfo
        public var kind: MenuBarItemKind
        /// Stable while the item exists: its identifier, or the element's hash.
        public var key: String
    }

    /// MenuBarAgent's labels in every language, read once from its bundle.
    public static let labels: MenuBarLabels = {
        let url = URL(fileURLWithPath: "/System/Library/CoreServices/MenuBarAgent.app/Contents/Resources/MenuBarCore.loctable")
        guard let data = try? Data(contentsOf: url),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else { return .english }
        return .from(loctable: plist.compactMapValues { $0 as? [String: String] })
    }()

    public static var agentPID: pid_t? {
        NSRunningApplication.runningApplications(withBundleIdentifier: agentBundleID).first?.processIdentifier
    }

    /// The slots of the menu bar on one display.
    /// - Parameters:
    ///   - display: the display's frame in AX coordinates (top-left origin); nil for the main display.
    ///   - readContent: read each MenuBarAgent item's text (for Live Activities); frames only otherwise.
    public static func slots(agent: pid_t, display: CGRect? = nil, readContent: Bool) -> [Slot] {
        let app = AXUIElementCreateApplication(agent)
        AXUIElementSetMessagingTimeout(app, 0.2)
        guard let window = menuBarWindow(app, display: display) else { return [] }
        let bundles = Dictionary(NSWorkspace.shared.runningApplications.map { ($0.processIdentifier, $0.bundleIdentifier ?? "") },
                                 uniquingKeysWith: { a, _ in a })
        var result: [Slot] = []
        for slot in children(window) {
            let frame = frame(slot)
            guard frame.width > 0 else { continue }
            if string(slot, kAXRoleAttribute) == kAXButtonRole {
                let info = MenuBarItemInfo(role: kAXButtonRole, x: frame.minX, width: frame.width)
                result.append(Slot(frame: frame, element: slot, info: info, kind: .overflowButton, key: "overflow"))
                continue
            }
            guard let content = children(slot).first else { continue }
            let owner = pid(content)
            let bundle = bundles[owner] ?? ""
            if owner != agent, !MenuBarLiveActivities.rendererBundleIDs.contains(bundle) {
                let info = MenuBarItemInfo(owner: bundle.isEmpty ? "unknown" : bundle, x: frame.minX, width: frame.width)
                result.append(Slot(frame: frame, element: content, info: info, kind: .thirdParty, key: "app:\(bundle):\(frame.minX)"))
                continue
            }
            // AXGroup(AXHostingView) > AXMenuBarItem for MenuBarAgent's own items.
            let item = [content] + children(content)
            let target = item.first { string($0, kAXRoleAttribute) == "AXMenuBarItem" } ?? content
            var info = MenuBarItemInfo(
                identifier: string(target, kAXIdentifierAttribute), role: string(target, kAXRoleAttribute),
                subrole: string(target, kAXSubroleAttribute), description: string(target, kAXDescriptionAttribute),
                owner: owner == agent ? "agent" : "renderer", x: frame.minX, width: frame.width
            )
            let kind0 = MenuBarLiveActivities.classify(info, labels: labels)
            // System items are recognised from the identifier alone; read more only when it could matter.
            if readContent, kind0 != .systemItem {
                info.title = string(target, kAXTitleAttribute)
                info.value = value(target)
                info.help = string(target, kAXHelpAttribute)
                info.customActions = customActions(target)
                var texts: [String] = []
                var budget = 40
                collectTexts(target, agent: agent, renderers: bundles, depth: 0, budget: &budget, into: &texts)
                info.texts = texts
            }
            let kind = MenuBarLiveActivities.classify(info, labels: labels)
            let key = info.identifier.flatMap { $0.isEmpty ? nil : "id:\($0)" } ?? "el:\(String(CFHash(target), radix: 36))"
            result.append(Slot(frame: frame, element: target, info: info, kind: kind, key: key))
        }
        // Items collapsed into the overflow are stacked on the chevron.
        if let chevron = result.first(where: { $0.kind == .overflowButton })?.frame.insetBy(dx: -2, dy: 0) {
            for i in result.indices where result[i].kind != .overflowButton && result[i].frame.intersects(chevron) {
                result[i].info.hidden = true
            }
        }
        return result.sorted { $0.frame.minX < $1.frame.minX }
    }

    /// The first menu bar window on the display (all Spaces have one with the same items).
    static func menuBarWindow(_ app: AXUIElement, display: CGRect?) -> AXUIElement? {
        var v: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &v) == .success,
              let windows = v as? [AXUIElement] else { return nil }
        return windows.first { w in
            let f = frame(w)
            guard f.height > 0, f.height <= 40 else { return false }
            guard let display else { return f.minX == 0 && f.minY == 0 }
            return abs(f.minX - display.minX) < 1 && abs(f.minY - display.minY) < 1
        }
    }

    static func collectTexts(_ e: AXUIElement, agent: pid_t, renderers: [pid_t: String], depth: Int, budget: inout Int, into out: inout [String]) {
        guard depth < 6, budget > 0 else { return }
        for c in children(e) {
            budget -= 1
            guard budget > 0 else { return }
            let p = pid(c)
            // Stay inside MenuBarAgent and the Live Activity renderer.
            guard p == agent || MenuBarLiveActivities.rendererBundleIDs.contains(renderers[p] ?? "") else { continue }
            if let s = value(c) ?? string(c, kAXDescriptionAttribute) ?? string(c, kAXTitleAttribute), !s.isEmpty {
                out.append(s)
            }
            collectTexts(c, agent: agent, renderers: renderers, depth: depth + 1, budget: &budget, into: &out)
        }
    }

    /// Custom action names ("End Live Activity"); read, never performed.
    static func customActions(_ e: AXUIElement) -> [String] {
        var names: CFArray?
        guard AXUIElementCopyActionNames(e, &names) == .success, let list = names as? [String] else { return [] }
        return list.compactMap { raw in
            guard raw.hasPrefix("Name:") else { return nil }
            return raw.dropFirst(5).split(separator: "\n").first.map(String.init)
        }
    }

    // MARK: AX helpers

    static func pid(_ e: AXUIElement) -> pid_t {
        var p: pid_t = 0
        AXUIElementGetPid(e, &p)
        return p
    }

    static func value(_ e: AXUIElement) -> String? {
        var v: CFTypeRef?
        guard AXUIElementCopyAttributeValue(e, kAXValueAttribute as CFString, &v) == .success, let v else { return nil }
        if let s = v as? String { return s }
        if let n = v as? NSNumber { return n.stringValue }
        return nil
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
}
