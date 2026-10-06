import Foundation
import Testing
@testable import CasementCore

/// To-dos and the quick note: one line in, starred first, ticked off to the end, kept on this
/// Mac in files only you can read.
@Suite struct TodoTests {
    private func tempDir() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("casement-todos-\(UUID().uuidString)")
    }

    @Test func addingMakesOneTrimmedLineAndSkipsBlanks() {
        var list = TodoList()
        #expect(list.add("   ", now: t0) == nil)
        #expect(list.add("\n\t\n", now: t0) == nil)
        let item = list.add("  Buy milk\n  and bread  ", now: t0)
        #expect(item?.text == "Buy milk and bread")
        #expect(list.items.count == 1)
        let long = String(repeating: "a", count: TodoList.maxLength + 50)
        #expect(list.add(long, now: t0)?.text.count == TodoList.maxLength)
    }

    @Test func starredComeFirstThenNewestThenDoneMostRecentFirst() {
        var list = TodoList()
        let a = list.add("a", now: t0)!
        let b = list.add("b", now: t0.addingTimeInterval(1))!
        let c = list.add("c", now: t0.addingTimeInterval(2))!
        let d = list.add("d", now: t0.addingTimeInterval(3))!
        #expect(list.ordered.map(\.text) == ["d", "c", "b", "a"])
        list.toggleStar(id: a.id)
        #expect(list.ordered.map(\.text) == ["a", "d", "c", "b"])
        list.toggleDone(id: c.id, now: t0.addingTimeInterval(10))
        list.toggleDone(id: d.id, now: t0.addingTimeInterval(20))
        #expect(list.ordered.map(\.text) == ["a", "b", "d", "c"])
        #expect(list.openCount == 2)
        #expect(list.hasDone)
        // Put back to do, it is with the others again.
        list.toggleDone(id: d.id, now: t0.addingTimeInterval(30))
        #expect(list.ordered.map(\.text) == ["a", "d", "b", "c"])
        _ = b
    }

    @Test func clearDoneKeepsWhatIsLeftToDo() {
        var list = TodoList()
        let a = list.add("a", now: t0)!
        list.add("b", now: t0)
        list.toggleDone(id: a.id, now: t0)
        list.clearDone()
        #expect(list.items.map(\.text) == ["b"])
        #expect(!list.hasDone)
    }

    @Test func renamingToNothingRemovesTheLine() {
        var list = TodoList()
        let a = list.add("a", now: t0)!
        list.rename(id: a.id, to: "  better\nwords ")
        #expect(list.items.first?.text == "better words")
        list.rename(id: a.id, to: "  ")
        #expect(list.items.isEmpty)
    }

    @Test func pastTheLimitDoneLinesGoFirstThenUnstarredOnes() {
        var list = TodoList()
        let first = list.add("first", now: t0)!
        list.toggleStar(id: first.id)
        let done = list.add("done", now: t0)!
        list.toggleDone(id: done.id, now: t0)
        for i in 0..<(TodoList.maxItems - 2) { list.add("item \(i)", now: t0) }
        #expect(list.items.count == TodoList.maxItems)
        list.add("one more", now: t0)
        #expect(list.items.count == TodoList.maxItems)
        #expect(!list.items.contains { $0.text == "done" })
        list.add("and another", now: t0)
        // The oldest unstarred line went; the starred one stays.
        #expect(!list.items.contains { $0.text == "item 0" })
        #expect(list.items.contains { $0.text == "first" })
    }

    @Test func aFullListOfStarredLinesStillTakesTheNewOne() throws {
        var list = TodoList()
        for i in 0..<TodoList.maxItems {
            let item = list.add("starred \(i)", now: t0)
            let id = try #require(item).id
            list.toggleStar(id: id)
        }
        // The line just typed stays; the oldest starred one makes room for it.
        let typed = list.add("new line", now: t0)
        let added = try #require(typed)
        #expect(list.items.count == TodoList.maxItems)
        #expect(list.items.contains { $0.id == added.id })
        #expect(!list.items.contains { $0.text == "starred 0" })
        #expect(list.items.contains { $0.text == "starred 1" })
    }

    @Test func savesReadableOnlyByYouAndReadsBack() throws {
        let dir = tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("todos.json")
        var list = TodoList()
        let a = list.add("Water the plants", now: t0)!
        list.toggleStar(id: a.id)
        list.add("Call Sam", now: t0.addingTimeInterval(5))
        try list.save(to: url)
        let mode = try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? Int
        #expect(mode == 0o600)
        #expect(TodoList.load(from: url).value == list)
        // Empty, the file goes.
        list.remove(id: a.id)
        list.remove(id: list.items[0].id)
        try list.save(to: url)
        #expect(!FileManager.default.fileExists(atPath: url.path))
        guard case .missing = TodoList.load(from: url) else {
            Issue.record("expected no file")
            return
        }
    }

    @Test func aLineThatCantBeReadIsSkippedNotTheList() throws {
        let json = """
        {"items": [{"id": "1", "text": "kept", "createdAt": 1800000000},
                   {"id": 2, "text": ["not", "text"]},
                   {"id": "3", "text": "", "createdAt": 1800000000},
                   {"text": "no id", "starred": true}]}
        """
        let list = try TodoList.decoder.decode(TodoList.self, from: Data(json.utf8))
        #expect(list.items.map(\.text) == ["kept", "no id"])
        #expect(list.items[1].starred)
    }

    @Test func aBrokenFileIsReportedNotEmptied() throws {
        let dir = tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("todos.json")
        try Data("{not json".utf8).write(to: url)
        guard case .unreadable = TodoList.load(from: url) else {
            Issue.record("expected unreadable")
            return
        }
    }

    // MARK: Quick note

    @Test func theNoteKeepsItsTextAndAnEmptyOneRemovesTheFile() throws {
        let dir = tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let note = QuickNoteFile(url: dir.appendingPathComponent("note.txt"))
        #expect(note.read() == "")
        try note.write("Ideas\n- a calmer clipboard\n")
        #expect(note.read() == "Ideas\n- a calmer clipboard\n")
        let mode = try FileManager.default.attributesOfItem(atPath: note.url.path)[.posixPermissions] as? Int
        #expect(mode == 0o600)
        try note.write("  \n ")
        #expect(!FileManager.default.fileExists(atPath: note.url.path))
    }

    @Test func aVeryLongNoteIsCut() throws {
        let dir = tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let note = QuickNoteFile(url: dir.appendingPathComponent("note.txt"))
        try note.write(String(repeating: "x", count: QuickNoteFile.maxLength + 10))
        #expect(note.read().count == QuickNoteFile.maxLength)
    }

    @Test func wordCount() {
        #expect(QuickNoteFile.summary("") == "0 words")
        #expect(QuickNoteFile.summary("one") == "1 word")
        #expect(QuickNoteFile.summary("one two\nthree") == "3 words")
    }
}
