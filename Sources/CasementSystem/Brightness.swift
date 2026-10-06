import AppKit
import CoreGraphics
import Foundation
import CasementCore

/// Built-in display brightness through the private DisplayServices framework.
///
/// Change notifications come from `DisplayServicesRegisterForBrightnessChangeNotifications`,
/// whose callback has the `CFNotificationCallback` shape and delivers `{"value": level}`
/// (verified on macOS 27). No permission is required. Every call is capability-checked,
/// so if Apple removes a symbol the feature simply turns itself off.
public final class BrightnessMonitor {
    private typealias GetFn = @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32
    private typealias SetFn = @convention(c) (CGDirectDisplayID, Float) -> Int32
    private typealias Callback = @convention(c) (CFNotificationCenter?, UnsafeMutableRawPointer?, CFString?, UnsafeRawPointer?, CFDictionary?) -> Void
    private typealias RegisterFn = @convention(c) (CGDirectDisplayID, UnsafeMutableRawPointer?, Callback) -> Int32

    private static let handle = dlopen("/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices", RTLD_LAZY)
    private static let getFn: GetFn? = handle.flatMap { dlsym($0, "DisplayServicesGetBrightness") }.map { unsafeBitCast($0, to: GetFn.self) }
    private static let setFn: SetFn? = handle.flatMap { dlsym($0, "DisplayServicesSetBrightness") }.map { unsafeBitCast($0, to: SetFn.self) }
    private static let registerFn: RegisterFn? = handle.flatMap { dlsym($0, "DisplayServicesRegisterForBrightnessChangeNotifications") }
        .map { unsafeBitCast($0, to: RegisterFn.self) }

    /// Only one monitor receives callbacks (the C callback cannot capture context safely).
    private static weak var active: BrightnessMonitor?

    /// Called for deliberate changes (auto-brightness drift is filtered out).
    public var onChange: ((Double) -> Void)?
    private var filter = BrightnessChangeFilter()
    private var registered = false

    public init() {}

    public static var isAvailable: Bool { getFn != nil }

    /// Whether the built-in display's brightness can be read and set (the private symbols are
    /// there). An OS update that removes them turns this off.
    public static var canSet: Bool { getFn != nil && setFn != nil }

    /// The built-in panel if there is one (external displays need DDC, which we don't do).
    public static var builtInDisplay: CGDirectDisplayID? {
        var count: UInt32 = 0
        CGGetOnlineDisplayList(0, nil, &count)
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        CGGetOnlineDisplayList(count, &ids, &count)
        return ids.first { CGDisplayIsBuiltin($0) != 0 }
    }

    public static func read(_ display: CGDirectDisplayID? = builtInDisplay) -> Double? {
        guard let getFn, let display else { return nil }
        var v: Float = 0
        return getFn(display, &v) == 0 ? Double(v) : nil
    }

    @discardableResult
    public static func set(_ value: Double, display: CGDirectDisplayID? = builtInDisplay) -> Bool {
        guard let setFn, let display else { return false }
        return setFn(display, Float(min(1, max(0, value)))) == 0
    }

    public func start() {
        guard !registered, let registerFn = Self.registerFn, let display = Self.builtInDisplay else { return }
        Self.active = self
        _ = filter.ingest(Self.read(display) ?? 0, now: Date())
        let status = registerFn(display, nil) { _, _, _, _, info in
            let dict = info as? [String: Any]
            let raw = dict?["value"]
            let value = (raw as? NSNumber)?.doubleValue ?? (raw as? String).flatMap(Double.init) ?? BrightnessMonitor.read()
            guard let value else { return }
            DispatchQueue.main.async { BrightnessMonitor.active?.received(value) }
        }
        registered = status == 0
    }

    private func received(_ value: Double) {
        if filter.ingest(value, now: Date()) { onChange?(value) }
    }
}

/// Keyboard backlight through CoreBrightness' `KeyboardBrightnessClient` (private, no notifications).
public enum KeyboardBacklight {
    private static let client: NSObject? = {
        guard dlopen("/System/Library/PrivateFrameworks/CoreBrightness.framework/CoreBrightness", RTLD_LAZY) != nil,
              let cls = NSClassFromString("KeyboardBrightnessClient") as? NSObject.Type else { return nil }
        return cls.init()
    }()

    private typealias GetIMP = @convention(c) (NSObject, Selector, UInt64) -> Float
    private typealias SetIMP = @convention(c) (NSObject, Selector, Float, UInt64) -> Bool

    /// Whether the backlight can be read and set on this Mac and macOS.
    public static var isAvailable: Bool {
        guard let client else { return false }
        return class_getInstanceMethod(type(of: client), NSSelectorFromString("brightnessForKeyboard:")) != nil
            && class_getInstanceMethod(type(of: client), NSSelectorFromString("setBrightness:forKeyboard:")) != nil
    }

    public static func read() -> Double? {
        let sel = NSSelectorFromString("brightnessForKeyboard:")
        guard let client, let m = class_getInstanceMethod(type(of: client), sel) else { return nil }
        let f = unsafeBitCast(method_getImplementation(m), to: GetIMP.self)
        return Double(f(client, sel, 1))
    }

    @discardableResult
    public static func set(_ value: Double) -> Bool {
        let sel = NSSelectorFromString("setBrightness:forKeyboard:")
        guard let client, let m = class_getInstanceMethod(type(of: client), sel) else { return false }
        let f = unsafeBitCast(method_getImplementation(m), to: SetIMP.self)
        return f(client, sel, Float(min(1, max(0, value))), 1)
    }
}

/// Opt-in "replace the system HUD" mode: an event tap swallows the volume, brightness and
/// keyboard-backlight keys and applies the change itself, so only Casement's HUD appears.
/// Requires Accessibility permission; without it `start()` returns false and nothing changes.
/// A key Casement can't act on (`shouldIntercept` says no) goes on to macOS untouched.
public final class MediaKeyInterceptor {
    public typealias Key = MediaKey

    /// Called on the main thread with the key and whether a fine step (⇧⌥) was requested.
    public var onKey: ((Key, Bool) -> Void)?
    /// Asked on the main thread, for each key press, whether to take it (`KeyInterceptPolicy`);
    /// its repeats and release get the same answer (`KeyInterceptLatch`). With none set, every
    /// key is taken.
    public var shouldIntercept: ((Key, NSEvent.ModifierFlags) -> Bool)?
    /// The answer each key's press got, for its repeats and release. Main thread only.
    fileprivate var latch = KeyInterceptLatch()
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?

    public init() {}
    deinit { stop() }

    public static var hasAccessibility: Bool { AXIsProcessTrusted() }

    /// Whether the keys are being intercepted: a tap that macOS keeps enabled (false without
    /// Accessibility, or once macOS has turned the tap off).
    public var isRunning: Bool { tap.map { CGEvent.tapIsEnabled(tap: $0) } ?? false }

    public static func requestAccessibility() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        _ = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }

    // NX_KEYTYPE_* values from IOKit/hidsystem/ev_keymap.h
    public static func key(for code: Int) -> Key? {
        switch code {
        case 0: return .volumeUp
        case 1: return .volumeDown
        case 7: return .mute
        case 2: return .brightnessUp
        case 3: return .brightnessDown
        case 21: return .backlightUp
        case 22: return .backlightDown
        default: return nil
        }
    }

    @discardableResult
    public func start() -> Bool {
        // A tap macOS turned off for good (Accessibility taken away and given back) is made again.
        if let tap, !CGEvent.tapIsEnabled(tap: tap) { stop() }
        guard tap == nil, Self.hasAccessibility else { return tap != nil }
        let mask = CGEventMask(1 << 14) // NX_SYSDEFINED
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        guard let tap = CGEvent.tapCreate(tap: .cghidEventTap, place: .headInsertEventTap, options: .defaultTap,
                                          eventsOfInterest: mask, callback: { _, type, event, refcon in
            guard let refcon else { return Unmanaged.passUnretained(event) }
            let me = Unmanaged<MediaKeyInterceptor>.fromOpaque(refcon).takeUnretainedValue()
            if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                if let t = me.tap { CGEvent.tapEnable(tap: t, enable: true) }
                return Unmanaged.passUnretained(event)
            }
            guard let ns = NSEvent(cgEvent: event), ns.type == .systemDefined, ns.subtype.rawValue == 8 else {
                return Unmanaged.passUnretained(event)
            }
            let code = Int((ns.data1 & 0xFFFF_0000) >> 16)
            guard let key = MediaKeyInterceptor.key(for: code) else { return Unmanaged.passUnretained(event) }
            let isDown = ((ns.data1 & 0xFF00) >> 8) == 0xA
            let isRepeat = ns.data1 & 0x1 != 0
            // The tap's source is on the main run loop, so this runs on the main thread. The press
            // decides, and its repeats and release follow it, so macOS never sees half a key.
            if let ask = me.shouldIntercept,
               !me.latch.take(key, isDown: isDown, isRepeat: isRepeat, decide: { ask(key, ns.modifierFlags) }) {
                return Unmanaged.passUnretained(event)
            }
            if isDown {
                let fine = ns.modifierFlags.contains(.shift) && ns.modifierFlags.contains(.option)
                DispatchQueue.main.async { me.onKey?(key, fine) }
            }
            return nil
        }, userInfo: refcon) else { return false }
        self.tap = tap
        let src = CFMachPortCreateRunLoopSource(nil, tap, 0)
        source = src
        CFRunLoopAddSource(CFRunLoopGetMain(), src, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        return true
    }

    public func stop() {
        if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        tap = nil
        source = nil
    }
}
