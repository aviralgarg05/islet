import Carbon.HIToolbox
import Foundation
import IsletCore

/// One system-wide shortcut through Carbon's hot-key API (no Accessibility permission needed).
public final class GlobalHotkey {
    public var onPress: (() -> Void)?
    private var ref: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private static weak var current: GlobalHotkey?

    public init() {}
    deinit { unregister() }

    /// Returns false if the shortcut is invalid or already taken by another app.
    @discardableResult
    public func register(_ hotkey: Hotkey) -> Bool {
        unregister()
        Self.current = self
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in
            DispatchQueue.main.async { GlobalHotkey.current?.onPress?() }
            return noErr
        }, 1, &spec, nil, &handler)
        let id = EventHotKeyID(signature: OSType(0x49534C54), id: 1) // 'ISLT'
        let status = RegisterEventHotKey(hotkey.keyCode, hotkey.modifiers.rawValue, id, GetApplicationEventTarget(), 0, &ref)
        return status == noErr
    }

    public func unregister() {
        if let ref { UnregisterEventHotKey(ref) }
        if let handler { RemoveEventHandler(handler) }
        ref = nil
        handler = nil
    }
}
