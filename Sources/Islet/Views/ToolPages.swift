import IsletCore

/// The tools that are pages of their own. Turned on, each is a page in the page switcher's
/// More menu; still off, it waits in that menu's More tools, where its page offers Turn on.
enum ToolPages {
    static let all: [IslandTab] = [.shortcuts, .weather]

    static func isOn(_ tab: IslandTab, _ s: IsletSettings) -> Bool {
        switch tab {
        case .shortcuts: return s.shortcutsEnabled
        case .weather: return s.weatherEnabled
        default: return true
        }
    }

    static func on(_ s: IsletSettings) -> [IslandTab] { all.filter { isOn($0, s) } }
    static func off(_ s: IsletSettings) -> [IslandTab] { all.filter { !isOn($0, s) } }
}
