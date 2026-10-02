import AppKit
import IsletCore
import IsletSystem
import SwiftUI

extension Snapshots {
    /// The note tools and the clipboard and shelf changes: To-dos, Note, Converter and Emoji
    /// (off, on and in use), the Ask box answering a conversion, the Clipboard page with every
    /// kind of clip, a filter and a search, the empty shelf saying how long files stay, and the
    /// switcher with a page moved into the capsule. Leaves the model as it found it.
    static func renderNoteTools(model: AppModel, now: Date, shoot: (String) -> Void, size: (SizePreset) -> Void) {
        let saved = model.settings
        model.forcedPresentation = .expanded
        size(.compact)

        // To-dos: off, empty, then a list with a starred line and two ticked off.
        model.tab = .todos
        shoot("95-todos-off")
        model.settings.todosEnabled = true
        model.tools.todos.showDemo([], now: now)
        shoot("95b-todos-empty")
        model.tools.todos.showDemo([("Send the invoice to Sam", starred: true, done: false),
                                    ("Book the dentist", starred: false, done: false),
                                    ("Water the plants", starred: false, done: false),
                                    ("Reply to the design review notes", starred: false, done: true),
                                    ("Renew the passport", starred: false, done: true)], now: now)
        shoot("95c-todos")
        size(.standard)
        shoot("95d-todos-standard")
        size(.compact)

        // The quick note: off, empty, then with a few lines.
        model.tab = .note
        shoot("96-note-off")
        model.settings.noteEnabled = true
        model.tools.note.showDemo("")
        shoot("96b-note-empty")
        model.tools.note.showDemo("Ideas for the weekend\n- Pick up the bike from the shop\n- Try the new bakery on Elm Street\n- Call Mum about Sunday lunch")
        shoot("96c-note")
        size(.standard)
        shoot("96d-note-standard")
        size(.compact)

        // The converter: off, the examples, an answer, the usual answers, and nonsense.
        model.tab = .converter
        shoot("97-converter-off")
        model.settings.converterEnabled = true
        model.tools.converter.query = ""
        shoot("97b-converter-empty")
        model.tools.converter.query = "5 ft in cm"
        shoot("97c-converter")
        model.tools.converter.query = "70 kg"
        shoot("97d-converter-usual")
        model.tools.converter.query = "5 apples in pears"
        shoot("97e-converter-unknown")
        model.tools.converter.query = "100 °F in °C"
        size(.standard)
        shoot("97f-converter-standard")
        size(.compact)
        // The Ask box answers it too.
        model.tab = .ask
        model.ask.clearForSnapshot()
        for kind in AskProviderKind.allCases { model.ask.setStatusForSnapshot(.ready, for: kind) }
        model.ask.sessionProvider = .anthropic
        model.ask.draft = "60 mph in km/h"
        shoot("97g-ask-conversion")
        model.ask.draft = ""
        model.ask.sessionProvider = nil
        model.tools.converter.query = ""

        // Emoji: off, the ones used lately first, a search, and nothing found.
        model.tab = .emoji
        shoot("98-emoji-off")
        model.settings.emojiEnabled = true
        model.tools.emoji.showDemo(query: "", recents: ["🚀", "✅", "🎉"], picked: "🚀")
        shoot("98b-emoji")
        model.tools.emoji.showDemo(query: "heart", recents: [])
        shoot("98c-emoji-search")
        size(.standard)
        shoot("98d-emoji-search-standard")
        size(.compact)
        model.tools.emoji.showDemo(query: "xylophonequartz", recents: [])
        shoot("98e-emoji-nothing")
        model.tools.emoji.showDemo(query: "", recents: [])

        // The clipboard: every kind shown as itself, then one kind, then a search.
        let savedClipboard = model.clipboard
        var history = ClipboardHistory(limit: 30)
        history.add(.files(["/System/Library/CoreServices/Finder.app", "/etc/hosts"]), types: [], sourceBundleID: "com.apple.finder",
                    now: now)
        if let picture = demoPicture() {
            history.add(.image(picture), types: [], sourceBundleID: "com.apple.screencaptureui", now: now)
        }
        history.add("#0A84FF", types: [], sourceBundleID: "com.apple.dt.Xcode", now: now)
        history.add("Meet at the café on Elm Street at 6", types: [], sourceBundleID: "com.apple.MobileSMS", now: now)
        history.add("https://github.com/aviralgarg05/islet/releases", types: [], sourceBundleID: "com.apple.Safari", now: now)
        history.togglePin(id: history.entries.first { $0.kind == .colour }?.id ?? "")
        model.setClipboardForSnapshot(history)
        model.tab = .clipboard
        shoot("99-clipboard-kinds")
        size(.standard)
        shoot("99b-clipboard-kinds-standard")
        size(.large)
        shoot("99h-clipboard-kinds-large")
        size(.compact)
        model.tools.clipboardPage.filter = .kind(.link)
        history.add("https://developer.apple.com/documentation/swiftui", types: [], sourceBundleID: "com.apple.Safari", now: now)
        model.setClipboardForSnapshot(history)
        shoot("99c-clipboard-links")
        model.tools.clipboardPage.filter = .all
        model.tools.clipboardPage.query = "elm"
        shoot("99d-clipboard-search")
        model.tools.clipboardPage.query = "zzz"
        shoot("99e-clipboard-no-match")
        model.tools.clipboardPage.reset()
        model.setClipboardForSnapshot(savedClipboard)

        // The empty shelf says how long files stay.
        let shelved = model.shelfService.urls()
        model.shelfService.removeAll()
        model.tab = .shelf
        shoot("99f-shelf-empty-keeps-a-day")
        model.shelfService.add(urls: shelved)

        // To-dos moved into the capsule, Today left out.
        var pages = model.settings.islandPages
        pages.move(.todos, onto: .shelf)
        pages.setShown(.today, false)
        model.settings.islandPages = pages
        model.tab = .todos
        shoot("99g-switcher-custom-order")

        model.settings = saved
        model.tools.todos.showDemo([], now: now)
        model.tools.note.showDemo("")
        size(saved.sizePreset)
        model.tab = .home
    }

    /// A small screenshot-like picture for the clipboard's image row.
    static func demoPicture() -> ClipImage? {
        let size = NSSize(width: 160, height: 100)
        let image = NSImage(size: size, flipped: false) { rect in
            NSGradient(colors: [NSColor(red: 0.36, green: 0.42, blue: 0.62, alpha: 1), NSColor(red: 0.62, green: 0.45, blue: 0.55, alpha: 1)])?
                .draw(in: rect, angle: -35)
            NSColor.black.setFill()
            NSBezierPath(roundedRect: NSRect(x: 50, y: 78, width: 60, height: 14), xRadius: 7, yRadius: 7).fill()
            return true
        }
        guard let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else { return nil }
        return ClipImage(data: png, type: "public.png", width: rep.pixelsWide, height: rep.pixelsHigh)
    }
}
