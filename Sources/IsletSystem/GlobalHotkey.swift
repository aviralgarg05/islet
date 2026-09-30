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

    private static var nextID: UInt32 = 1
    private static var registered: [UInt32: Weak] = [:]
    private static var handler: EventHandlerRef?
    private final class Weak { weak var hotkey: GlobalHotkey?; init(_ h: GlobalHotkey) { hotkey = h } }

    public init() {
        id = Self.nextID
        Self.nextID += 1
    }

    deinit { unregister() }

    /// Returns false if the shortcut is invalid or already taken by another app.
    @discardableResult
    public func register(_ hotkey: Hotkey) -> Bool {
        unregister()
        Self.installHandler()
        Self.registered[id] = Weak(self)
        let hotKeyID = EventHotKeyID(signature: OSType(0x49534C54), id: id) // 'ISLT'
        let status = RegisterEventHotKey(hotkey.keyCode, hotkey.modifiers.rawValue, hotKeyID, GetApplicationEventTarget(), 0, &ref)
        return status == noErr
    }

    public func unregister() {
        if let ref { UnregisterEventHotKey(ref) }
        ref = nil
        Self.registered[id] = nil
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
