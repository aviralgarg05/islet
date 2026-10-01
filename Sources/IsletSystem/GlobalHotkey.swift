import Carbon.HIToolbox
import Foundation
import IsletCore

/// A system-wide shortcut through Carbon's hot-key API (no Accessibility permission needed).
/// Several can be registered at once; each gets its own id and one shared event handler routes
/// presses to the right one.
public final class GlobalHotkey {
    public var onPress: (() -> Void)?
    private var ref: EventHotKeyRef?
    private let id: UInt32
    /// The shortcut this one is set to, kept while shortcuts are suspended.
    private var hotkey: Hotkey?

    private static var nextID: UInt32 = 1
    private static var registered: [UInt32: Weak] = [:]
    private static var handler: EventHandlerRef?
    /// How many callers have suspended the shortcuts (`suspendAll`) and not yet resumed them.
    private static var suspensions = 0
    private final class Weak { weak var hotkey: GlobalHotkey?; init(_ h: GlobalHotkey) { hotkey = h } }

    public init() {
        id = Self.nextID
        Self.nextID += 1
    }

    deinit { unregister() }

    /// Returns false if the shortcut is invalid or already taken by another app. While
    /// shortcuts are suspended it is kept and taken when they resume.
    @discardableResult
    public func register(_ hotkey: Hotkey) -> Bool {
        unregister()
        Self.installHandler()
        Self.registered[id] = Weak(self)
        self.hotkey = hotkey
        return Self.suspensions > 0 || grab()
    }

    public func unregister() {
        release()
        hotkey = nil
        Self.registered[id] = nil
    }

    /// Let every Islet shortcut through to the app in front, so a shortcut field can record a
    /// combination that is already one of them (otherwise the shortcut fires and the field never
    /// sees the keys). Each call is balanced by `resumeAll`.
    public static func suspendAll() {
        suspensions += 1
        guard suspensions == 1 else { return }
        for h in registered.values.compactMap(\.hotkey) { h.release() }
    }

    /// Take the shortcuts back once the last suspension ends.
    public static func resumeAll() {
        guard suspensions > 0 else { return }
        suspensions -= 1
        guard suspensions == 0 else { return }
        for h in registered.values.compactMap(\.hotkey) { h.grab() }
    }

    public static var isSuspended: Bool { suspensions > 0 }

    @discardableResult
    private func grab() -> Bool {
        guard let hotkey, ref == nil else { return ref != nil }
        let hotKeyID = EventHotKeyID(signature: OSType(0x49534C54), id: id) // 'ISLT'
        let status = RegisterEventHotKey(hotkey.keyCode, hotkey.modifiers.rawValue, hotKeyID, GetApplicationEventTarget(), 0, &ref)
        if status != noErr { ref = nil }
        return status == noErr
    }

    private func release() {
        if let ref { UnregisterEventHotKey(ref) }
        ref = nil
    }

    private static func installHandler() {
        guard handler == nil else { return }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
            var pressed = EventHotKeyID()
            let status = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                                           nil, MemoryLayout<EventHotKeyID>.size, nil, &pressed)
            guard status == noErr else { return OSStatus(eventNotHandledErr) }
            let id = pressed.id
            DispatchQueue.main.async { GlobalHotkey.registered[id]?.hotkey?.onPress?() }
            return noErr
        }, 1, &spec, nil, &handler)
    }
}
