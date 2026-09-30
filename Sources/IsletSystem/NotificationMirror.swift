import AppKit
import ApplicationServices
import Foundation
import IsletCore

/// Mirrors notification banners from every app (including iPhone notifications that macOS
/// forwards) into the island, by observing Notification Center with the Accessibility API.
///
/// Opt-in and experimental: it needs the Accessibility permission, reads only the text the
/// banner shows on screen, and never stores it. The full Notification Center panel is ignored
/// so opening it doesn't replay old notifications.
public final class NotificationMirror {
    public static let notificationCenterBundleID = "com.apple.notificationcenterui"

    public var onNotification: ((MirroredNotification) -> Void)?
    private var observer: AXObserver?
    private var appElement: AXUIElement?
    private var launchObserver: NSObjectProtocol?
    private var seen: [String: Date] = [:]
    private var pendingScan = false

    public init() {}
    deinit { stop() }

    public static var isTrusted: Bool { AXIsProcessTrusted() }

    /// Returns false when Accessibility access is missing.
    @discardableResult
    public func start() -> Bool {
        guard Self.isTrusted else { return false }
        attach()
        if launchObserver == nil {
            // Notification Center restarts occasionally; re-attach when it does.
            launchObserver = NSWorkspace.shared.notificationCenter.addObserver(
                forName: NSWorkspace.didLaunchApplicationNotification, object: nil, queue: .main
            ) { [weak self] note in
                let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
                if app?.bundleIdentifier == Self.notificationCenterBundleID { self?.attach() }
            }
        }
        return observer != nil
    }

    public func stop() {
        if let observer {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
        }
        observer = nil
        appElement = nil
        if let o = launchObserver { NSWorkspace.shared.notificationCenter.removeObserver(o) }
        launchObserver = nil
    }

    private func attach() {
        if let observer { CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode) }
        observer = nil
        guard let nc = NSRunningApplication.runningApplications(withBundleIdentifier: Self.notificationCenterBundleID).first else { return }
        let pid = nc.processIdentifier
        var obs: AXObserver?
        let callback: AXObserverCallback = { _, _, _, refcon in
            guard let refcon else { return }
            Unmanaged<NotificationMirror>.fromOpaque(refcon).takeUnretainedValue().scheduleScan()
        }
        guard AXObserverCreate(pid, callback, &obs) == .success, let obs else { return }
        let element = AXUIElementCreateApplication(pid)
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        for name in [kAXWindowCreatedNotification, kAXCreatedNotification, kAXLayoutChangedNotification] {
            AXObserverAddNotification(obs, element, name as CFString, refcon)
        }
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(obs), .defaultMode)
        observer = obs
        appElement = element
    }

    /// Banners animate in over a few frames; read them once they've settled.
    private func scheduleScan() {
        guard !pendingScan else { return }
        pendingScan = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            self?.pendingScan = false
            self?.scan()
        }
    }

    // MARK: AX helpers

    static func attribute(_ e: AXUIElement, _ name: String) -> CFTypeRef? {
        var value: CFTypeRef?
        return AXUIElementCopyAttributeValue(e, name as CFString, &value) == .success ? value : nil
    }

    static func string(_ e: AXUIElement, _ name: String) -> String? {
        attribute(e, name) as? String
    }

    static func children(_ e: AXUIElement) -> [AXUIElement] {
        (attribute(e, kAXChildrenAttribute) as? [AXUIElement]) ?? []
    }

    static func size(_ e: AXUIElement) -> CGSize? {
        guard let v = attribute(e, kAXSizeAttribute), CFGetTypeID(v) == AXValueGetTypeID() else { return nil }
        var s = CGSize.zero
        return AXValueGetValue(v as! AXValue, .cgSize, &s) ? s : nil
    }

    /// Groups that look like a single notification: they directly contain static text.
    static func bannerGroups(in e: AXUIElement, depth: Int = 0, into out: inout [AXUIElement]) {
        guard depth < 10 else { return }
        let kids = children(e)
        let role = string(e, kAXRoleAttribute)
        let subrole = string(e, kAXSubroleAttribute) ?? ""
        let hasText = kids.contains { string($0, kAXRoleAttribute) == kAXStaticTextRole }
        if role == kAXGroupRole, subrole.localizedCaseInsensitiveContains("notification") || hasText {
            out.append(e)
            return
        }
        for k in kids { bannerGroups(in: k, depth: depth + 1, into: &out) }
    }

    static func texts(in e: AXUIElement, depth: Int = 0, into out: inout [String]) {
        guard depth < 6 else { return }
        for k in children(e) {
            if string(k, kAXRoleAttribute) == kAXStaticTextRole, let v = string(k, kAXValueAttribute) ?? string(k, kAXDescriptionAttribute) {
                out.append(v)
            } else {
                texts(in: k, depth: depth + 1, into: &out)
            }
        }
    }

    private func scan() {
        guard let appElement else { return }
        let windows = (Self.attribute(appElement, kAXWindowsAttribute) as? [AXUIElement]) ?? []
        let known = Self.knownApps()
        let now = Date()
        seen = seen.filter { now.timeIntervalSince($0.value) < 60 }
        for w in windows {
            // The Notification Center panel is tall; banners are short.
            if let s = Self.size(w), s.height > 420 { continue }
            var groups: [AXUIElement] = []
            Self.bannerGroups(in: w, into: &groups)
            for g in groups {
                var texts: [String] = []
                Self.texts(in: g, into: &texts)
                let desc = Self.string(g, kAXDescriptionAttribute)
                guard let n = NotificationParser.parse(texts: texts, description: desc, knownApps: known) else { continue }
                if seen[n.fingerprint] != nil { continue }
                seen[n.fingerprint] = now
                onNotification?(n)
            }
        }
    }

    /// Display name → bundle id for running regular apps (the likely senders).
    static func knownApps() -> [String: String] {
        var map: [String: String] = [:]
        for app in NSWorkspace.shared.runningApplications where app.activationPolicy == .regular {
            if let name = app.localizedName, let id = app.bundleIdentifier { map[name] = id }
        }
        return map
    }
}
