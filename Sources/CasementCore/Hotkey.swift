import Foundation

/// A global shortcut written as text, e.g. "ctrl+option+i" or "cmd+shift+space".
public struct Hotkey: Equatable, Sendable {
    /// Whether two shortcuts, as config.json writes them, are the same keys ("ctrl+option+i"
    /// and "option+ctrl+I" are). Casement's two shortcuts can't share keys: only one would work.
    public static func sameKeys(_ a: String, _ b: String) -> Bool {
        guard let x = parse(a), let y = parse(b) else { return false }
        return x == y
    }

    public struct Modifiers: OptionSet, Sendable, Hashable {
        public let rawValue: UInt32
        public init(rawValue: UInt32) { self.rawValue = rawValue }
        // Carbon modifier masks (cmdKey, shiftKey, optionKey, controlKey).
        public static let command = Modifiers(rawValue: 1 << 8)
        public static let shift = Modifiers(rawValue: 1 << 9)
        public static let option = Modifiers(rawValue: 1 << 11)
        public static let control = Modifiers(rawValue: 1 << 12)
    }

    /// Carbon virtual key code (kVK_*).
    public var keyCode: UInt32
    public var modifiers: Modifiers

    /// ANSI key codes for the keys a shortcut can use.
    static let keyCodes: [String: UInt32] = [
        "a": 0, "s": 1, "d": 2, "f": 3, "h": 4, "g": 5, "z": 6, "x": 7, "c": 8, "v": 9, "b": 11, "q": 12,
        "w": 13, "e": 14, "r": 15, "y": 16, "t": 17, "1": 18, "2": 19, "3": 20, "4": 21, "6": 22, "5": 23,
        "=": 24, "9": 25, "7": 26, "-": 27, "8": 28, "0": 29, "]": 30, "o": 31, "u": 32, "[": 33, "i": 34,
        "p": 35, "l": 37, "j": 38, "'": 39, "k": 40, ";": 41, "\\": 42, ",": 43, "/": 44, "n": 45, "m": 46,
        ".": 47, "`": 50, "return": 36, "enter": 36, "tab": 48, "space": 49, "escape": 53, "esc": 53,
        "f1": 122, "f2": 120, "f3": 99, "f4": 118, "f5": 96, "f6": 97, "f7": 98, "f8": 100, "f9": 101,
        "f10": 109, "f11": 103, "f12": 111, "up": 126, "down": 125, "left": 123, "right": 124,
    ]

    public static func parse(_ text: String) -> Hotkey? {
        var compact = text.lowercased().replacingOccurrences(of: " ", with: "")
        // Accept the symbol form too ("⌃⌥I"): split leading modifier symbols into parts.
        var symbols: [String] = []
        while let first = compact.first, "⌃⌥⇧⌘".contains(first) {
            symbols.append(String(first))
            compact.removeFirst()
        }
        let parts = symbols + compact.split(separator: "+").map(String.init)
        guard let key = parts.last, let code = keyCodes[key] else { return nil }
        var mods: Modifiers = []
        for p in parts.dropLast() {
            switch p {
            case "cmd", "command", "⌘": mods.insert(.command)
            case "shift", "⇧": mods.insert(.shift)
            case "opt", "option", "alt", "⌥": mods.insert(.option)
            case "ctrl", "control", "⌃": mods.insert(.control)
            default: return nil
            }
        }
        // A global shortcut without a modifier (other than shift) would swallow normal typing.
        guard !mods.subtracting(.shift).isEmpty || key.hasPrefix("f") && key.count > 1 else { return nil }
        return Hotkey(keyCode: code, modifiers: mods)
    }

    /// "⌃⌥I"-style label for Settings.
    public var label: String {
        var s = ""
        if modifiers.contains(.control) { s += "⌃" }
        if modifiers.contains(.option) { s += "⌥" }
        if modifiers.contains(.shift) { s += "⇧" }
        if modifiers.contains(.command) { s += "⌘" }
        let name = Self.keyCodes.first { $0.value == keyCode && $0.key.count <= 6 && $0.key != "enter" && $0.key != "esc" }?.key ?? "?"
        return s + (name.count == 1 ? name.uppercased() : name.capitalized)
    }

    /// The text Settings saves for a recorded key press ("ctrl+option+i"), or nil when the key
    /// can't be used or `parse` would refuse the combination (no modifier, say).
    public static func text(keyCode: UInt32, modifiers: Modifiers) -> String? {
        guard let name = keyCodes.first(where: { $0.value == keyCode && $0.key != "enter" && $0.key != "esc" })?.key else { return nil }
        var parts: [String] = []
        if modifiers.contains(.control) { parts.append("ctrl") }
        if modifiers.contains(.option) { parts.append("option") }
        if modifiers.contains(.shift) { parts.append("shift") }
        if modifiers.contains(.command) { parts.append("cmd") }
        let text = (parts + [name]).joined(separator: "+")
        return parse(text) == nil ? nil : text
    }
}
