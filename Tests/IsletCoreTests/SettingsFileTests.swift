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
