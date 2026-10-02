import AppKit
import IsletCore
import IsletSystem
import Observation

// The note tools under More: to-dos, the quick note, the converter and emoji. Each starts off,
// reads its file only once its page is first opened, and keeps everything on this Mac. The
// decisions (order, parsing, search) are in IsletCore: Todos.swift, UnitConverter.swift and
// Emoji.swift.

// MARK: - To-dos

/// The to-do list, read from `todos.json` the first time the page opens and saved after each
/// change. A file that can't be read is set aside, never written over.
@MainActor
@Observable
final class TodoController {
    private(set) var list = TodoList()
    /// The line being typed in the page's add field.
    var draft = ""
    /// The line being renamed, if any.
    var editing: String?

    @ObservationIgnored private let url: URL?
    @ObservationIgnored private var loaded = false
    @ObservationIgnored private var canSave = true

    /// - Parameter url: nil keeps the list in memory (snapshots).
    init(url: URL? = IsletPaths.supportDirectory.appendingPathComponent("todos.json")) {
        self.url = url
    }

    func load() {
        guard !loaded else { return }
        loaded = true
        guard let url else { return }
        let start = JSONStore.start(url) { TodoList.load(from: $0) }
        list = start.value ?? TodoList()
        canSave = start.canSave
        if let moved = start.setAside { Log.files.error("todos.json couldn't be read; kept as \(moved.lastPathComponent, privacy: .public)") }
    }

    /// Adds what is typed; Return in the field.
    func addDraft() {
        load()
        guard list.add(draft, now: Date()) != nil else { return }
        draft = ""
        Haptics.play(.tap)
        save()
    }

    func toggleDone(_ item: TodoItem) {
        list.toggleDone(id: item.id, now: Date())
        Haptics.play(item.isDone ? .tap : .snap)
        save()
    }

    func toggleStar(_ item: TodoItem) {
        list.toggleStar(id: item.id)
        save()
    }

    func rename(_ item: TodoItem, to text: String) {
        list.rename(id: item.id, to: text)
        editing = nil
        save()
    }

    func remove(_ item: TodoItem) {
        list.remove(id: item.id)
        save()
    }

    func clearDone() {
        list.clearDone()
        save()
    }

    private func save() {
        guard let url, canSave else { return }
        do {
            try list.save(to: url)
        } catch {
            Log.files.error("todos.json couldn't be saved: \(error.localizedDescription, privacy: .public)")
        }
    }

    func showDemo(_ lines: [(String, starred: Bool, done: Bool)], now: Date) {
        loaded = true
        var l = TodoList()
        for (i, line) in lines.reversed().enumerated() {
            guard let item = l.add(line.0, now: now.addingTimeInterval(Double(i))) else { continue }
            if line.starred { l.toggleStar(id: item.id) }
            if line.done { l.toggleDone(id: item.id, now: now.addingTimeInterval(Double(100 + i))) }
        }
        list = l
    }
}

// MARK: - Quick note

/// The quick note's text. Saved half a second after typing stops (one pending save, never a
/// timer that runs on its own), and at once when the page closes.
@MainActor
@Observable
final class NoteController {
    private(set) var text = ""

    @ObservationIgnored private let file: QuickNoteFile?
    @ObservationIgnored private var loaded = false
    @ObservationIgnored private var pendingSave: DispatchWorkItem?

    init(file: QuickNoteFile? = .standard) {
        self.file = file
    }

    func load() {
        guard !loaded else { return }
        loaded = true
        text = file?.read() ?? ""
    }

    func setText(_ new: String) {
        load()
        let clipped = QuickNoteFile.clipped(new)
        guard clipped != text else { return }
        text = clipped
        pendingSave?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.saveNow() }
        pendingSave = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: work)
    }

    /// Writes what is waiting to be written.
    func saveNow() {
        guard let work = pendingSave else { return }
        work.cancel()
        pendingSave = nil
        do {
            try file?.write(text)
        } catch {
            Log.files.error("note.txt couldn't be saved: \(error.localizedDescription, privacy: .public)")
        }
    }

    func showDemo(_ note: String) {
        loaded = true
        text = note
    }
}

// MARK: - Converter

/// What is typed on the Converter page, and its answer.
@MainActor
@Observable
final class ConverterController {
    var query = ""
    /// The answer copied last, said under the field until the next one.
    private(set) var copied: String?

    var conversion: Conversion? { Self.convert(query) }

    static func convert(_ text: String) -> Conversion? {
        UnitConverter.convert(text, imperialVolumes: UnitConverter.usesImperialVolumes())
    }

    /// The answer's number on its own, for pasting into a sum or a form.
    func copy(_ result: ConverterResult, model: AppModel) {
        model.clipboardMonitor.copy(result.number)
        Haptics.play(.tap)
        copied = result.text
    }

    func queryChanged() { copied = nil }
}

// MARK: - Emoji

/// The emoji page's search and the emoji used lately (`emoji.json`). A click copies the emoji,
/// or with "Type emoji where you're typing" on and Accessibility allowed, types it into the app
/// you were typing in.
@MainActor
@Observable
final class EmojiController {
    var query = ""
    private(set) var recents = EmojiRecents()
    /// The emoji just copied or typed, said beside the field until the next one.
    private(set) var picked: (emoji: String, typed: Bool)?
    /// Changes when typing an emoji hands the keyboard back, so the search field starts afresh
    /// and its next click takes the keyboard again.
    private(set) var fieldGeneration = 0

    @ObservationIgnored private let url: URL?
    @ObservationIgnored private var loaded = false

    init(url: URL? = IsletPaths.supportDirectory.appendingPathComponent("emoji.json")) {
        self.url = url
    }

    func load() {
        guard !loaded else { return }
        loaded = true
        if let url { recents = EmojiRecents.load(from: url) }
    }

    var results: [EmojiItem] {
        // Nothing typed: the ones used lately, then the everyday ones, then the rest.
        let lead = query.trimmingCharacters(in: .whitespaces).isEmpty
            ? recents.emoji + EmojiCatalog.favourites.filter { !recents.emoji.contains($0) } : recents.emoji
        return EmojiCatalog.search(query, recent: lead)
    }

    func pick(_ item: EmojiItem, model: AppModel) {
        load()
        recents.use(item.emoji)
        if let url { try? recents.save(to: url) }
        Haptics.play(.tap)
        if model.settings.emojiTypes, EmojiTyper.canType {
            picked = (item.emoji, true)
            // Back to the app you were in, then the emoji goes where you were typing.
            IslandKeyboard.giveBack()
            fieldGeneration += 1
            EmojiTyper.type(item.emoji)
        } else {
            model.clipboardMonitor.copy(item.emoji)
            picked = (item.emoji, false)
        }
    }

    func queryChanged() { picked = nil }

    func showDemo(query: String, recents: [String], picked: String? = nil) {
        loaded = true
        self.query = query
        self.recents = EmojiRecents(recents)
        self.picked = picked.map { ($0, false) }
    }
}

// MARK: - Clipboard page

/// The Clipboard page's search and filter, forgotten when the island closes.
@MainActor
@Observable
final class ClipboardPage {
    var query = ""
    var filter: ClipFilter = .all

    func reset() {
        query = ""
        filter = .all
    }
}

extension AppModel {
    /// The note tools' part of `applyTools()`: a page turned off falls back to Home, and the
    /// note is saved before its page goes.
    func applyNoteTools() {
        let s = settings
        if !s.noteEnabled { tools.note.saveNow() }
        if !s.emojiEnabled { tools.emoji.queryChanged() }
    }

    /// The island closed: the note is saved, searches are forgotten.
    func noteToolsIslandClosed() {
        tools.note.saveNow()
        tools.clipboardPage.reset()
        tools.emoji.query = ""
        tools.emoji.queryChanged()
        tools.todos.editing = nil
    }
}
