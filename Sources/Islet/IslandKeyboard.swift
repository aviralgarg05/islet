import AppKit

/// The island's panel doesn't take the keyboard, except while a text field in it is open
/// (the Timer card's custom field). The panel is non-activating, so typing there doesn't
/// bring Islet to the front, and giving the keyboard back returns it to the app you were in.
@MainActor
enum IslandKeyboard {
    /// Read by `IslandPanel.canBecomeKey`.
    private(set) static var allowsKey = false

    /// Make the island's panel on `display` key so a field in it can take typing.
    static func take(on display: CGDirectDisplayID?) {
        allowsKey = true
        let panels = NSApp.windows.filter { $0 is IslandPanel && $0.isVisible }
        (panels.first { $0.screen?.displayID == display } ?? panels.first)?.makeKey()
    }

    /// Hand the keyboard back to the app that had it.
    static func giveBack() {
        allowsKey = false
        for window in NSApp.windows where window is IslandPanel && window.isKeyWindow {
            // Ordering a key panel out is what drops key status; it is back on screen at once.
            window.orderOut(nil)
            window.orderFrontRegardless()
        }
    }
}
