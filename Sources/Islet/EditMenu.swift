import AppKit

/// Islet has no menu bar of its own, and without a main menu AppKit has nothing to route
/// ⌘X, ⌘C, ⌘V, ⌘A and ⌘Z to, so they do nothing in text fields such as the Ask box or an API
/// key pasted into Settings. An accessory app's main menu is never shown; this one only
/// carries those shortcuts.
@MainActor
enum EditMenu {
    static func install() {
        guard NSApp.mainMenu == nil else { return }
        let edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        edit.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "z").keyEquivalentModifierMask = [.command, .shift]
        edit.addItem(.separator())
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")

        let main = NSMenu()
        main.addItem(NSMenuItem())  // The application menu's slot, left empty.
        let editItem = NSMenuItem()
        editItem.submenu = edit
        main.addItem(editItem)
        NSApp.mainMenu = main
    }
}
