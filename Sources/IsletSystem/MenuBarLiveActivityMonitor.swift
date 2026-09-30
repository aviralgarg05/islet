import AppKit
import ApplicationServices
import IsletCore

/// Mirrors the Live Activities macOS shows in the menu bar (from the iPhone, and system ones such
/// as Shortcuts) into Islet. macOS 26/27 hosts them, like the system menu extras, in MenuBarAgent;
/// this watches that process through Accessibility and reads each item's text.
///
/// Needs Accessibility. Reads only MenuBarAgent's items, and only acts (presses an item) when the
/// user clicks the mirrored activity in Islet.
public final class MenuBarLiveActivityMonitor {
    public static let agentBundleID = "com.apple.MenuBarAgent"

    /// Current Live Activities, left to right, each paired with its item for pressing.
    public var onChange: (([MirroredLiveActivity]) -> Void)?
    /// Items appeared, went away or moved (the menu bar layout changed).
    public var onStructureChange: (() -> Void)?

    private var observer: AXObserver?
    private var app: AXUIElement?
    private var launchObserver: NSObjectProtocol?
    private var items: [String: AXUIElement] = [:]
    private var last: [MirroredLiveActivity] = []
    private var pending = false

    public init() {}
    deinit { stop() }

    public static var isAvailable: Bool { AXIsProcessTrusted() }

    public var isStarted: Bool { observer != nil }

    @discardableResult
    public func start() -> Bool {
        guard Self.isAvailable else { return false }
        attach()
        if launchObserver == nil {
            launchObserver = NSWorkspace.shared.notificationCenter.addObserver(
                forName: NSWorkspace.didLaunchApplicationNotification, object: nil, queue: .main
            ) { [weak self] note in
                let launched = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
                if launched?.bundleIdentifier == Self.agentBundleID { self?.attach() }
            }
        }
        scan()
        return observer != nil
    }

    public func stop() {
        if let observer { CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode) }
        observer = nil
        app = nil
        if let o = launchObserver { NSWorkspace.shared.notificationCenter.removeObserver(o) }
        launchObserver = nil
        if !last.isEmpty {
            last = []
            onChange?([])
        }
    }

    /// Open the original item (Apple's expanded view, or the app in iPhone Mirroring).
    @discardableResult
    public func press(key: String) -> Bool {
        guard let element = items[key] else { return false }
        return AXUIElementPerformAction(element, kAXPressAction as CFString) == .success
    }

    private func attach() {
        if let observer { CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode) }
        observer = nil
        guard let agent = NSRunningApplication.runningApplications(withBundleIdentifier: Self.agentBundleID).first else { return }
        let pid = agent.processIdentifier
        let element = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(element, 0.3)
        var obs: AXObserver?
        let callback: AXObserverCallback = { _, element, name, refcon in
            guard let refcon else { return }
            Unmanaged<MenuBarLiveActivityMonitor>.fromOpaque(refcon).takeUnretainedValue().received(name as String, element: element)
        }
        guard AXObserverCreate(pid, callback, &obs) == .success, let obs else { return }
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        for name in [kAXCreatedNotification, kAXUIElementDestroyedNotification, kAXValueChangedNotification,
                     kAXTitleChangedNotification, kAXLayoutChangedNotification, kAXMovedNotification, kAXResizedNotification] {
            AXObserverAddNotification(obs, element, name as CFString, refcon)
        }
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(obs), .defaultMode)
        observer = obs
        app = element
    }

    /// Title and value changes arrive about once a second (the clock, tickers and meters from
    /// other apps), so they only lead to a scan when they come from a mirrored activity.
    private func received(_ name: String, element: AXUIElement) {
        switch name {
        case kAXTitleChangedNotification, kAXValueChangedNotification:
            if belongsToActivity(element) { scheduleScan() }
        default:
            scheduleScan()
            scheduleStructureChange()
        }
    }

    private func belongsToActivity(_ element: AXUIElement) -> Bool {
        guard !items.isEmpty else { return false }
        var e: AXUIElement? = element
        for _ in 0..<5 {
            guard let current = e else { return false }
            if items.values.contains(where: { CFEqual($0, current) }) { return true }
            e = Self.element(current, kAXParentAttribute)
        }
        return false
    }

    private var structurePending = false

    private func scheduleStructureChange() {
        guard !structurePending, onStructureChange != nil else { return }
        structurePending = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            self?.structurePending = false
            self?.onStructureChange?()
        }
    }

    private func scheduleScan() {
        guard !pending else { return }
        pending = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            self?.pending = false
            self?.scan()
        }
    }

    /// Read MenuBarAgent's items and publish the Live Activities among them.
    public func scan() {
        guard let app, let bar = Self.element(app, kAXExtrasMenuBarAttribute) else { return }
        var found: [(MirroredLiveActivity, AXUIElement, CGFloat)] = []
        for host in Self.children(bar) {
            // Items are AXGroup(AXHostingView) > AXMenuBarItem, or a bare item/button. Judge the
            // menu bar item itself when there is one: the group around it has no identifier
            // but repeats its text, so it would look like an unknown item.
            let inner = Self.children(host).filter { Self.string($0, kAXRoleAttribute) == kAXMenuBarItemRole }
            let candidates = Self.string(host, kAXRoleAttribute) == kAXMenuBarItemRole || inner.isEmpty ? [host] : inner
            for element in candidates {
                let info = Self.info(element)
                if let m = MenuBarLiveActivities.mirror(info) {
                    found.append((m, element, info.x))
                    break
                }
            }
        }
        found.sort { $0.2 < $1.2 }
        items = Dictionary(found.map { ($0.0.key, $0.1) }, uniquingKeysWith: { a, _ in a })
        let list = found.map(\.0)
        guard list != last else { return }
        last = list
        onChange?(list)
    }

    /// A read-only description of every MenuBarAgent item, for diagnostics.
    public func dump() -> [MenuBarItemInfo] {
        guard let app, let bar = Self.element(app, kAXExtrasMenuBarAttribute) else { return [] }
        return Self.children(bar).flatMap { host in [host] + Self.children(host) }.map(Self.info)
    }

    // MARK: AX helpers

    static func info(_ e: AXUIElement) -> MenuBarItemInfo {
        var texts: [String] = []
        collectTexts(e, depth: 0, into: &texts)
        var x: CGFloat = 0
        var v: CFTypeRef?
        if AXUIElementCopyAttributeValue(e, kAXPositionAttribute as CFString, &v) == .success, let v, CFGetTypeID(v) == AXValueGetTypeID() {
            var p = CGPoint.zero
            AXValueGetValue(v as! AXValue, .cgPoint, &p)
            x = p.x
        }
        return MenuBarItemInfo(
            identifier: string(e, kAXIdentifierAttribute), subrole: string(e, kAXSubroleAttribute),
            title: string(e, kAXTitleAttribute), description: string(e, kAXDescriptionAttribute),
            value: value(e), help: string(e, kAXHelpAttribute), texts: texts, x: x
        )
    }

    static func collectTexts(_ e: AXUIElement, depth: Int, into out: inout [String]) {
        guard depth < 5 else { return }
        for c in children(e) {
            if let s = string(c, kAXValueAttribute) ?? string(c, kAXDescriptionAttribute) ?? string(c, kAXTitleAttribute), !s.isEmpty {
                out.append(s)
            }
            collectTexts(c, depth: depth + 1, into: &out)
        }
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
}
