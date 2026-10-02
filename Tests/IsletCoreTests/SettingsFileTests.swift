import Foundation
import Testing
@testable import IsletCore

/// A folder of its own under the temporary directory, removed by the caller.
private func scratchFolder(_ name: String) throws -> URL {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("islet-\(name)-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir
}

/// config.json is never reset or written over because it doesn't parse.
@Suite struct SettingsFileTests {
    @Test func aFileThatDoesNotParseIsKeptByteForByte() throws {
        let dir = try scratchFolder("config")
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("config.json")
        let broken = Data("{\n  \"hoverToOpen\": false,\n  \"theme\": \"glass\"\n  \"outline\": true\n}\n".utf8)
        try broken.write(to: url)

        var file = SettingsFile(url: url)
        guard case .unreadable(let problem) = file.read() else {
            Issue.record("expected unreadable")
            return
        }
        // The missing comma is noticed on line 4, where the next key starts.
        #expect(problem.line == 4, "\(problem)")
        #expect(problem.sentence(file: "config.json") == "config.json has an error on line 4.")
        #expect(file.problem == problem)

        var changed = IsletSettings()
        changed.hoverToOpen = true
        #expect(try file.save(changed) == .refused)
        #expect(try Data(contentsOf: url) == broken)
        #expect(throws: FileProblem.self) { try changed.save(to: url) }
        #expect(try Data(contentsOf: url) == broken)
        #expect(!FileManager.default.fileExists(atPath: file.brokenCopy.path))
    }

    /// The file watcher sees Islet's own saves too. Reloading one would undo a change made since
    /// (a slider still moving, an island change waiting for its save), so an echo of our own write
    /// is told apart from an edit made by someone else.
    @Test func ownWritesAreToldApartFromOtherEdits() throws {
        let dir = try scratchFolder("config")
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("config.json")
        var file = SettingsFile(url: url)
        #expect(!file.holdsOwnWrite(), "nothing written yet")

        var s = IsletSettings()
        s.hoverToOpen = false
        #expect(try file.save(s) == .saved)
        #expect(file.holdsOwnWrite())

        // Saving what is already there is still ours.
        #expect(try file.save(s) == .unchanged)
        #expect(file.holdsOwnWrite())

        // Someone else edits the file: that one must be loaded.
        var other = s
        other.hoverToOpen = true
        try other.save(to: url)
        #expect(!file.holdsOwnWrite())
        guard case .loaded(let fresh) = file.read() else { Issue.record("expected loaded"); return }
        #expect(fresh.hoverToOpen)

        // A deleted file is not ours either.
        try FileManager.default.removeItem(at: url)
        #expect(!file.holdsOwnWrite())
    }

    /// An edit by hand is loaded; putting the file back to what Islet last wrote (undo, or
    /// `git checkout`) is an edit too, and must be loaded rather than taken for Islet's own save.
    @Test func revertingToOurLastWriteIsReadAgain() throws {
        let dir = try scratchFolder("config")
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("config.json")
        var file = SettingsFile(url: url)
        var a = IsletSettings()
        a.theme = .glass
        #expect(try file.save(a) == .saved)
        let ours = try Data(contentsOf: url)

        var b = a
        b.theme = .graphite
        try b.save(to: url)
        #expect(file.read().value?.theme == .graphite)

        try ours.write(to: url)
        #expect(!file.holdsOwnWrite())
        #expect(file.read().value == a)
    }

    /// A typo shows the problem; undoing it back to Islet's own bytes must clear it again.
    @Test func undoingATypoBackToOurBytesClearsTheProblem() throws {
        let dir = try scratchFolder("config")
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("config.json")
        var file = SettingsFile(url: url)
        var a = IsletSettings()
        a.outline = true
        #expect(try file.save(a) == .saved)
        let ours = try Data(contentsOf: url)

        try Data("{ \"outline\": tru }".utf8).write(to: url)
        #expect(file.read().problem != nil)
        #expect(file.problem != nil)
        #expect(try file.save(a) == .refused)

        try ours.write(to: url)
        #expect(!file.holdsOwnWrite())
        #expect(file.read().value == a)
        #expect(file.problem == nil)
    }

    /// One save by an editor can reach Islet twice (the folder and the file are both watched).
    /// The second event must not read the file again: that would undo a change made in between.
    @Test func aSecondEventForTheSameEditIsHeld() throws {
        let dir = try scratchFolder("config")
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("config.json")
        var file = SettingsFile(url: url)
        #expect(try file.save(IsletSettings()) == .saved)
        var b = IsletSettings()
        b.hoverToOpen = false
        try b.save(to: url)
        #expect(!file.holdsOwnWrite())
        #expect(file.read().value == b)
        #expect(file.holdsOwnWrite())
    }

    /// Opening the file at launch counts as reading it: its own watcher event isn't read twice.
    @Test func openingTheFileIsInStepWithIt() throws {
        let dir = try scratchFolder("config")
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("config.json")
        var s = IsletSettings()
        s.outline = true
        try s.save(to: url)
        var file = SettingsFile(url: url)
        #expect(file.open().settings == s)
        #expect(file.holdsOwnWrite())
    }

    @Test func fixingTheFileClearsTheProblem() throws {
        let dir = try scratchFolder("config")
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("config.json")
        try Data("{ nope".utf8).write(to: url)
        var file = SettingsFile(url: url)
        #expect(file.read().problem != nil)
        try Data(#"{"hoverToOpen": false}"#.utf8).write(to: url)
        let fixed = file.read()
        #expect(file.problem == nil)
        #expect(fixed.value?.hoverToOpen == false)
        #expect(try file.save(fixed.value!) == .saved)
    }

    @Test func replacingKeepsTheBrokenFileBeside() throws {
        let dir = try scratchFolder("config")
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("config.json")
        let broken = Data("{ \"theme\": ".utf8)
        try broken.write(to: url)
        var file = SettingsFile(url: url)
        _ = file.read()
        var lastGood = IsletSettings()
        lastGood.theme = .graphite
        try file.replace(with: lastGood)
        #expect(file.problem == nil)
        #expect(try Data(contentsOf: file.brokenCopy) == broken)
        #expect(file.brokenCopy.lastPathComponent == "config.json.broken")
        #expect(file.read().value == lastGood)
        // A file that parses is just saved; no copy is made.
        try FileManager.default.removeItem(at: file.brokenCopy)
        try file.replace(with: IsletSettings())
        #expect(!FileManager.default.fileExists(atPath: file.brokenCopy.path))
        #expect(file.read().value == IsletSettings())
    }

    @Test func unknownKeysSurviveASave() throws {
        let dir = try scratchFolder("config")
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("config.json")
        try Data(#"{"hoverToOpen": false, "zzFromANewerIslet": {"level": 1.5, "on": true, "names": ["a", "b"]}, "count": 3}"#.utf8).write(to: url)
        var file = SettingsFile(url: url)
        var s = try #require(file.read().value)
        #expect(s.hoverToOpen == false)
        s.outline = true
        #expect(try file.save(s) == .saved)
        let object = try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        let future = try #require(object["zzFromANewerIslet"] as? [String: Any])
        #expect(future["level"] as? Double == 1.5)
        #expect(future["on"] as? Bool == true)
        #expect(future["names"] as? [String] == ["a", "b"])
        #expect(object["count"] as? Int == 3)
        #expect(object["outline"] as? Bool == true)
        #expect(file.read().value == s)
        // The known keys are written exactly as before.
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let plain = String(decoding: try e.encode(s), as: UTF8.self).components(separatedBy: "\n")
        let written = Set(String(decoding: try Data(contentsOf: url), as: UTF8.self).components(separatedBy: "\n"))
        for line in plain where !line.hasPrefix("{") && !line.hasPrefix("}") {
            #expect(written.contains(line) || written.contains(line + ","), "\(line)")
        }
        // Saving the same again writes nothing.
        #expect(try file.save(s) == .unchanged)
    }

    @Test func retiredKeysAreDroppedOnSave() throws {
        let dir = try scratchFolder("config")
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("config.json")
        try Data(#"{"hapticFeedback": false, "hideForApps": ["com.apple.Keynote"], "launchAtLogin": true}"#.utf8).write(to: url)
        var file = SettingsFile(url: url)
        var s = try #require(file.read().value)
        #expect(s.hapticsMode == .off)
        s.hapticsMode = .all
        try file.save(s)
        let object = try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        for key in ["hapticFeedback", "hideForApps", "launchAtLogin"] { #expect(object[key] == nil, "\(key)") }
        // The old switch can't turn haptics off again.
        #expect(file.read().value?.hapticsMode == .all)
        #expect(IsletSettings.retiredKeys.isDisjoint(with: IsletSettings.knownKeys))
    }

    @Test func missingEmptyAndOtherShapes() throws {
        let dir = try scratchFolder("config")
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("config.json")
        var file = SettingsFile(url: url)
        #expect(file.read() == .missing)
        // Nothing to lose: an empty file is written like a missing one.
        try Data(" \n".utf8).write(to: url)
        #expect(file.read() == .missing)
        #expect(try file.save(IsletSettings()) == .saved)
        #expect(file.read() == .loaded(IsletSettings()))
        // Valid JSON that isn't an object is kept too.
        try Data("[1, 2]".utf8).write(to: url)
        #expect(file.read().problem?.line == 1)
        #expect(try file.save(IsletSettings()) == .refused)
        #expect(try Data(contentsOf: url) == Data("[1, 2]".utf8))
    }

    /// A file already broken when Islet starts (edited while it was quit, or before a restart)
    /// gives the settings from the last time it parsed, not the defaults.
    @Test func aFileBrokenAtLaunchStartsFromTheLastGoodCopy() throws {
        let dir = try scratchFolder("config")
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("config/config.json")
        let copy = dir.appendingPathComponent("support/config-last-good.json")
        var mine = IsletSettings()
        mine.hideFromScreenCapture = true
        mine.theme = .graphite
        // A session that saves, then quits.
        var first = SettingsFile(url: url, lastGood: copy)
        try first.save(mine)
        #expect(FileManager.default.fileExists(atPath: copy.path))
        // A typo made while Islet wasn't running.
        let broken = Data("{\n  \"theme\": \"graphite\",\n  \"hideFromScreenCapture\": true\n  \"outline\": true\n}\n".utf8)
        try broken.write(to: url)
        var next = SettingsFile(url: url, lastGood: copy)
        let opened = next.open()
        #expect(opened.origin == .lastGood)
        #expect(opened.settings == mine)
        #expect(next.problem?.line == 4)
        // The broken file is left alone, and so is the copy.
        #expect(try next.save(IsletSettings()) == .refused)
        #expect(try Data(contentsOf: url) == broken)
        #expect(IsletSettings.read(from: copy).value == mine)
        // Replace writes those settings back, keeping config.json.broken.
        try next.replace(with: opened.settings)
        #expect(try Data(contentsOf: next.brokenCopy) == broken)
        #expect(next.read().value == mine)
    }

    @Test func aFileBrokenAtLaunchWithNoCopySaysItIsOnDefaults() throws {
        let dir = try scratchFolder("config")
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("config.json")
        let copy = dir.appendingPathComponent("config-last-good.json")
        try Data("{ \"theme\": ".utf8).write(to: url)
        var file = SettingsFile(url: url, lastGood: copy)
        let opened = file.open()
        #expect(opened.origin == .defaults)
        #expect(opened.settings == IsletSettings())
        // A copy that doesn't parse either counts as none.
        try Data("not json".utf8).write(to: copy)
        #expect(file.open().origin == .defaults)
        // Missing, and good, files come from the file.
        try FileManager.default.removeItem(at: url)
        #expect(file.open().origin == .file)
        try Data(#"{"outline": true}"#.utf8).write(to: url)
        let good = file.open()
        #expect(good.origin == .file && good.settings.outline)
        // Reading a good file refreshes the copy.
        #expect(IsletSettings.read(from: copy).value?.outline == true)
    }

    @Test func aBrokenReadNeverReachesTheCopy() throws {
        let dir = try scratchFolder("config")
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("config.json")
        let copy = dir.appendingPathComponent("config-last-good.json")
        try Data(#"{"outline": true}"#.utf8).write(to: url)
        var file = SettingsFile(url: url, lastGood: copy)
        _ = file.read()
        let kept = try Data(contentsOf: copy)
        try Data("{ oops".utf8).write(to: url)
        _ = file.read()
        #expect(try file.save(IsletSettings()) == .refused)
        #expect(try Data(contentsOf: copy) == kept)
    }

    @Test func lineNumbersFromTheParser() {
        #expect(FileProblem.line(described: "Badly formed object around line 12, column 3.") == 12)
        #expect(FileProblem.line(described: "No line here") == nil)
        let data = Data("a\nb\nc".utf8)
        #expect(FileProblem.line(at: 0, in: data) == 1)
        #expect(FileProblem.line(at: 2, in: data) == 2)
        #expect(FileProblem.line(at: 4, in: data) == 3)
        #expect(FileProblem.line(at: nil, in: data) == nil)
    }
}

/// The shelf and timers never start empty over a file they couldn't read.
@Suite struct StoreFileTests {
    @Test func aCorruptTimersFileIsMovedAsideFirst() throws {
        let dir = try scratchFolder("timers")
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("timers.json")
        try Data("{\"timers\": [".utf8).write(to: url)
        let start = TimerEngine.start(from: url)
        #expect(start.value == nil)
        #expect(start.canSave)
        #expect(start.problem != nil)
        #expect(start.setAside?.lastPathComponent == "timers.json.corrupt")
        #expect(!FileManager.default.fileExists(atPath: url.path))
        #expect(try Data(contentsOf: dir.appendingPathComponent("timers.json.corrupt")) == Data("{\"timers\": [".utf8))
        // A second bad file doesn't replace the first copy.
        try Data("nope".utf8).write(to: url)
        #expect(TimerEngine.start(from: url).setAside?.lastPathComponent == "timers.json.corrupt-2")
        // A good file loads, a missing one starts empty, and neither is moved.
        var e = TimerEngine()
        try e.start(seconds: 60, now: t0)
        try e.save(to: url)
        #expect(TimerEngine.start(from: url).value == e)
        try FileManager.default.removeItem(at: url)
        let fresh = TimerEngine.start(from: url)
        #expect(fresh.value == nil && fresh.canSave && fresh.setAside == nil)
    }

    @Test func aCorruptShelfFileIsMovedAsideFirst() throws {
        let dir = try scratchFolder("shelf")
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("shelf.json")
        try Data("{\"items\": 3".utf8).write(to: url)
        let start = JSONStore.start(url) { JSONStore.read(Shelf.self, from: $0) }
        #expect(start.value == nil && start.canSave)
        #expect(start.setAside?.lastPathComponent == "shelf.json.corrupt")
    }

    @Test func copiesGetTheirOwnNames() {
        let url = URL(fileURLWithPath: "/tmp/x/shelf.json")
        #expect(BrokenFile.destination(for: url, suffix: "corrupt") { _ in false }.lastPathComponent == "shelf.json.corrupt")
        let taken: Set<String> = ["shelf.json.corrupt", "shelf.json.corrupt-2"]
        #expect(BrokenFile.destination(for: url, suffix: "corrupt") { taken.contains($0.lastPathComponent) }.lastPathComponent
                == "shelf.json.corrupt-3")
        // Past nine copies the first name is reused.
        #expect(BrokenFile.destination(for: url, suffix: "corrupt") { _ in true }.lastPathComponent == "shelf.json.corrupt")
    }

    @Test func itemsOnADiskThatIsNotConnectedStay() {
        var shelf = Shelf()
        shelf.add(paths: ["/Users/me/gone.txt", "/Users/me/here.txt", "/Volumes/Backup/photo.jpg",
                          "/Volumes/Work/old.key", "/Volumes/Work/new.key"], now: t0)
        // Backup isn't mounted; Work is, and one of its files was deleted.
        let existing: Set<String> = ["/Users/me/here.txt", "/Volumes/Work", "/Volumes/Work/new.key"]
        shelf.prune { existing.contains($0) }
        #expect(Set(shelf.items.map(\.path)) == ["/Users/me/here.txt", "/Volumes/Backup/photo.jpg", "/Volumes/Work/new.key"])
        let backup = shelf.items.first { $0.path.hasPrefix("/Volumes/Backup") }!
        #expect(!Shelf.isAvailable(backup) { existing.contains($0) })
        #expect(shelf.items.filter { !$0.path.hasPrefix("/Volumes/Backup") }.allSatisfy { Shelf.isAvailable($0) { existing.contains($0) } })
        #expect(Shelf.volume(of: "/Volumes/Backup/a/b.txt") == "/Volumes/Backup")
        #expect(Shelf.volume(of: "/Volumes/Backup") == nil)
        #expect(Shelf.volume(of: "/Users/me/a.txt") == nil)
    }
}
