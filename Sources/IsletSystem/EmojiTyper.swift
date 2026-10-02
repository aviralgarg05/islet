import AppKit
import ApplicationServices
import Foundation

/// Types an emoji into the app that has the keyboard, as the Character Viewer does, for "Type
/// emoji where you're typing". It sends that one character and nothing else, only when an emoji
/// is clicked, and only with Accessibility allowed; otherwise the emoji is copied instead.
public enum EmojiTyper {
    /// macOS lets Islet send typing only with Accessibility allowed.
    public static var canType: Bool { AXIsProcessTrusted() }

    /// Sends `text` as one key press a moment from now, once the app you were typing in has the
    /// keyboard back from the island.
    public static func type(_ text: String, after delay: TimeInterval = 0.08) {
        let units = Array(text.utf16)
        guard !units.isEmpty, units.count <= 32 else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            let source = CGEventSource(stateID: .hidSystemState)
            for down in [true, false] {
                guard let event = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: down) else { continue }
                event.flags = []
                event.keyboardSetUnicodeString(stringLength: units.count, unicodeString: units)
                event.post(tap: .cghidEventTap)
            }
        }
    }
}
