import AppKit
import ApplicationServices
import notify
import IsletCore

/// Mirrors the Live Activities macOS shows in the menu bar (from the iPhone, and Mac ones such as
/// Shortcuts) into Islet. On macOS 27 MenuBarAgent draws them; this reads its menu bar window
/// through Accessibility, including activities collapsed into the overflow behind the notch.
///
/// Needs Accessibility. Reads only MenuBarAgent's items and the Live Activity renderer's content,
/// keeps what it reads in memory, and only acts (presses an item) when the user clicks the
/// mirrored activity in Islet.
///
/// Cost: nothing polls while no activity exists. It wakes on the Darwin notifications that
/// `liveactivitiesd` posts when an activity changes, on items appearing or disappearing, and on
/// changes to the mirrored items themselves; a scan takes a few milliseconds.
public final class MenuBarLiveActivityMonitor {
    public static let agentBundleID = MenuBarAgentScanner.agentBundleID

    /// Current Live Activities, left to right.
    public var onChange: (([MirroredLiveActivity]) -> Void)?
    /// Items appeared, went away or moved (the menu bar layout changed).
    public var onStructureChange: (() -> Void)?
    /// Recognises an app name among an activity's text (the Live Activity catalogue).
    public var knownApp: (String) -> Bool = { _ in false }

    private var observer: AXObserver?
    private var agent: pid_t = 0
    private var slots: [String: MenuBarAgentScanner.Slot] = [:]
    private var chevron: AXUIElement?
    private var watched: [String: AXUIElement] = [:]
    private var last: [MirroredLiveActivity] = []
    private var notifyTokens: [Int32] = []
    private var workspaceObservers: [NSObjectProtocol] = []
    private var safetyTimer: Timer?
    private var scanWork: DispatchWorkItem?
    private var structureWork: DispatchWorkItem?
    private let queue = DispatchQueue(label: "islet.liveactivities", qos: .utility)

    /// Darwin notifications posted when Live Activity records or their rendered views change.
    static let triggers = [
        "com.apple.liveactivitiesd.replicatorParticipant.record",
        "com.apple.chronod.replicator.record",
        "com.apple.activitykit.daemonstartup",
    ]

    public init() {}
    deinit { stop() }

    public static var isAvailable: Bool { AXIsProcessTrusted() }

    /// Whether this macOS shows Live Activities in the menu bar at all (macOS 26 and later).
    public static var isSupported: Bool {
        MenuBarLiveActivities.isSupported(osMajor: ProcessInfo.processInfo.operatingSystemVersion.majorVersion)
    }

    /// Whether macOS is set to show iPhone Live Activities on this Mac (Control Center's setting).
    public static var iPhoneActivitiesEnabled: Bool? {
        CFPreferencesCopyAppValue("RemoteLiveActivitiesEnabled" as CFString, "com.apple.controlcenter" as CFString) as? Bool
    }

    public var isStarted: Bool { observer != nil }

    @discardableResult
    public func start() -> Bool {
        guard Self.isAvailable else { return false }
        if observer == nil { attach() }
        if notifyTokens.isEmpty {
            for name in Self.triggers {
                var token: Int32 = 0
                let status = notify_register_dispatch(name, &token, DispatchQueue.main) { [weak self] _ in
                    // The pill is rendered out of process, so look again a moment later too.
                    self?.scheduleScan(after: 1)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 3) { self?.scheduleScan(after: 0) }
                }
                if status == UInt32(NOTIFY_STATUS_OK) { notifyTokens.append(token) }
            }
        }
        if workspaceObservers.isEmpty {
            let wnc = NSWorkspace.shared.notificationCenter
            workspaceObservers.append(wnc.addObserver(forName: NSWorkspace.didLaunchApplicationNotification, object: nil, queue: .main) { [weak self] note in
                let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
                if app?.bundleIdentifier == Self.agentBundleID {
                    self?.attach()
                    self?.scheduleScan(after: 1)
                }
            })
            for name in [NSWorkspace.activeSpaceDidChangeNotification, NSWorkspace.didWakeNotification, NSWorkspace.screensDidWakeNotification] {
                workspaceObservers.append(wnc.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                    self?.scheduleScan(after: 0.5)
                })
            }
            appObservers.append(NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
                self?.scheduleScan(after: 0.5)
            })
        }
        scheduleScan(after: 0)
        return observer != nil
    }

    private var appObservers: [NSObjectProtocol] = []

    public func stop() {
        detach()
        notifyTokens.forEach { notify_cancel($0) }
        notifyTokens = []
        workspaceObservers.forEach { NSWorkspace.shared.notificationCenter.removeObserver($0) }
        workspaceObservers = []
        appObservers.forEach { NotificationCenter.default.removeObserver($0) }
        appObservers = []
        scanWork?.cancel()
        structureWork?.cancel()
        safetyTimer?.invalidate()
        safetyTimer = nil
        slots = [:]
        if !last.isEmpty {
            last = []
            onChange?([])
        }
    }

    /// Open the original item: Apple's expanded view, or the app in iPhone Mirroring.
    /// An activity hidden in the overflow is revealed first so macOS has somewhere to show it.
    @discardableResult
    public func press(key: String) -> Bool {
        guard let slot = slots[key] else { return false }
        if slot.info.hidden, let chevron {
            guard AXUIElementPerformAction(chevron, kAXPressAction as CFString) == .success else { return false }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                _ = AXUIElementPerformAction(slot.element, kAXPressAction as CFString)
            }
            return true
        }
        return AXUIElementPerformAction(slot.element, kAXPressAction as CFString) == .success
    }

    /// A read-only description of MenuBarAgent's items, for diagnostics. Other apps' items are
    /// listed by bundle ID and position only.
    public static func dump() -> [MenuBarItemInfo] {
        guard isAvailable, let agent = MenuBarAgentScanner.agentPID else { return [] }
        return MenuBarAgentScanner.slots(agent: agent, readContent: true).map { slot in
            var info = slot.info
            info.kind = slot.kind
            return info
        }
    }

    // MARK: Observing

    private func attach() {
        detach()
        guard let pid = MenuBarAgentScanner.agentPID else { return }
        agent = pid
        var obs: AXObserver?
        let callback: AXObserverCallback = { _, element, name, refcon in
            guard let refcon else { return }
            Unmanaged<MenuBarLiveActivityMonitor>.fromOpaque(refcon).takeUnretainedValue().received(name as String, element: element)
        }
        guard AXObserverCreate(pid, callback, &obs) == .success, let obs else { return }
        let app = AXUIElementCreateApplication(pid)
        // Structure only: value and title changes on the whole app arrive every second from
        // other apps' status items and the clock, so those are watched per element instead.
        for name in [kAXCreatedNotification, kAXUIElementDestroyedNotification, kAXLayoutChangedNotification] {
            AXObserverAddNotification(obs, app, name as CFString, Unmanaged.passUnretained(self).toOpaque())
        }
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(obs), .defaultMode)
        observer = obs
    }

    private func detach() {
        if let observer {
            for (_, element) in watched { unwatch(element, observer) }
            CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
        }
        watched = [:]
        observer = nil
    }

    private static let elementNotifications = [kAXValueChangedNotification, kAXTitleChangedNotification,
                                                kAXUIElementDestroyedNotification, kAXResizedNotification, "AXDescriptionChanged"]

    private func watch(_ element: AXUIElement, _ observer: AXObserver) {
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        for name in Self.elementNotifications { AXObserverAddNotification(observer, element, name as CFString, refcon) }
    }

    private func unwatch(_ element: AXUIElement, _ observer: AXObserver) {
        for name in Self.elementNotifications { AXObserverRemoveNotification(observer, element, name as CFString) }
    }

    private func received(_ name: String, element: AXUIElement) {
        switch name {
        case kAXCreatedNotification, kAXUIElementDestroyedNotification, kAXLayoutChangedNotification:
            // Ignore the other apps' UI that MenuBarAgent hosts; telling needs no IPC.
            var p: pid_t = 0
            AXUIElementGetPid(element, &p)
            guard p == agent || isRenderer(p) else { return }
            scheduleScan(after: 0.3)
            scheduleStructureChange()
        default:
            // A mirrored activity changed.
            scheduleScan(after: 0.3)
        }
    }

    private func isRenderer(_ pid: pid_t) -> Bool {
        guard let bundle = NSRunningApplication(processIdentifier: pid)?.bundleIdentifier else { return false }
        return MenuBarLiveActivities.rendererBundleIDs.contains(bundle)
    }

    private func scheduleStructureChange() {
        guard onStructureChange != nil else { return }
        structureWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.onStructureChange?() }
        structureWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: work)
    }

    private func scheduleScan(after delay: TimeInterval) {
        scanWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.scan() }
        scanWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    /// Publish the last list again, unchanged (an app was unmuted): no menu bar read.
    public func refresh() {
        if observer != nil { onChange?(last) }
    }

    /// Read MenuBarAgent's items off the main thread and publish the Live Activities among them.
    public func scan() {
        guard observer != nil, agent != 0 else { return }
        let agent = agent
        queue.async { [weak self] in
            let slots = MenuBarAgentScanner.slots(agent: agent, readContent: true)
            DispatchQueue.main.async { self?.apply(slots) }
        }
    }

    private func apply(_ all: [MenuBarAgentScanner.Slot]) {
        guard let observer else { return }
        chevron = all.first { $0.kind == .overflowButton }?.element
        let labels = MenuBarAgentScanner.labels
        var found: [(MirroredLiveActivity, MenuBarAgentScanner.Slot)] = []
        for slot in all where slot.kind == .liveActivity {
            if let m = MenuBarLiveActivities.mirror(slot.info, key: slot.key, labels: labels, knownApp: knownApp) {
                found.append((m, slot))
            }
        }
        slots = Dictionary(found.map { ($0.0.key, $0.1) }, uniquingKeysWith: { a, _ in a })

        // Watch each mirrored activity's own element for changes; stop watching ones that went.
        let current = slots.mapValues(\.element)
        for (key, element) in watched where current[key].map({ !CFEqual($0, element) }) ?? true {
            unwatch(element, observer)
            watched[key] = nil
        }
        for (key, element) in current where watched[key] == nil {
            watch(element, observer)
            watched[key] = element
        }
        // A slow safety net, only while something is mirrored, in case a change isn't announced.
        if found.isEmpty {
            safetyTimer?.invalidate()
            safetyTimer = nil
        } else if safetyTimer == nil {
            let t = Timer(timeInterval: 15, repeats: true) { [weak self] _ in self?.scan() }
            t.tolerance = 3
            RunLoop.main.add(t, forMode: .common)
            safetyTimer = t
        }

        let list = found.map(\.0)
        guard list != last else { return }
        last = list
        onChange?(list)
    }
}
