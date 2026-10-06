import Foundation
import Testing
@testable import CasementCore

/// Changes made while config.json didn't parse were never saved. When the file is fixed, those
/// changes and the fix are both kept (`CasementSettings.merged`).
@Suite struct SettingsMergeTests {
    /// What the file held when the island and Settings last saw it.
    static var base: CasementSettings {
        var s = CasementSettings()
        s.theme = .glass
        s.outline = false
        return s
    }

    @Test func aChangeOnEachSideIsKept() {
        var ours = Self.base
        ours.outline = true
        var theirs = Self.base
        theirs.theme = .graphite
        let merged = CasementSettings.merged(base: Self.base, ours: ours, theirs: theirs)
        #expect(merged.outline)
        #expect(merged.theme == .graphite)
    }

    @Test func theSameSettingChangedOnBothSidesIsTheFiles() {
        var ours = Self.base
        ours.theme = .black
        var theirs = Self.base
        theirs.theme = .graphite
        #expect(CasementSettings.merged(base: Self.base, ours: ours, theirs: theirs).theme == .graphite)
    }

    @Test func groupsMergeSettingBySetting() {
        var ours = Self.base
        ours.ask.provider = .openai
        var theirs = Self.base
        theirs.ask.effort = .high
        let merged = CasementSettings.merged(base: Self.base, ours: ours, theirs: theirs)
        #expect(merged.ask.provider == .openai)
        #expect(merged.ask.effort == .high)
    }

    @Test func nothingChangedInMemoryIsTheFile() {
        var theirs = Self.base
        theirs.theme = .graphite
        theirs.mutedSources = ["ci"]
        #expect(CasementSettings.merged(base: Self.base, ours: Self.base, theirs: theirs) == theirs)
        // A file put back as it was takes nothing back from memory either.
        #expect(CasementSettings.merged(base: theirs, ours: theirs, theirs: Self.base) == Self.base)
    }

    /// Settings taken from memory come back exactly, not through the lenient reader's defaults.
    @Test func changesOnlyInMemoryComeBackExactly() {
        var ours = Self.base
        ours.outline = true
        ours.ask.setModel("gpt-5-mini", for: .openai)
        ours.weatherPlace = WeatherPlace(name: "Leeds", country: "United Kingdom", latitude: 53.8, longitude: -1.55)
        ours.mutedSources = ["ci", "plugin"]
        #expect(CasementSettings.merged(base: Self.base, ours: ours, theirs: Self.base) == ours)
    }

    /// A list is one setting: both sides adding to it is a clash, and the file's list wins.
    @Test func listsAreOneSetting() {
        var ours = Self.base
        ours.mutedSources = ["ci"]
        var theirs = Self.base
        theirs.mutedSources = ["plugin"]
        #expect(CasementSettings.merged(base: Self.base, ours: ours, theirs: theirs).mutedSources == ["plugin"])
    }

    /// A setting with nothing set (no weather place) is a value too: clearing it in memory is
    /// kept, and so is setting it in the file.
    @Test func settingsWithNothingSetMerge() {
        var withPlace = Self.base
        withPlace.weatherPlace = WeatherPlace(name: "Leeds", latitude: 53.8, longitude: -1.55)
        var theirs = withPlace
        theirs.theme = .graphite
        let cleared = CasementSettings.merged(base: withPlace, ours: Self.base, theirs: theirs)
        #expect(cleared.weatherPlace == nil)
        #expect(cleared.theme == .graphite)

        var ours = Self.base
        ours.outline = true
        let set = CasementSettings.merged(base: Self.base, ours: ours, theirs: withPlace)
        #expect(set.weatherPlace == withPlace.weatherPlace)
        #expect(set.outline)
    }

    /// Settings from different sides can clash; the result is still one Casement can use.
    @Test func aClashBetweenSidesIsSettled() {
        var ours = Self.base
        ours.lanPort = 50_000
        var theirs = Self.base
        theirs.apiPort = 50_000
        let merged = CasementSettings.merged(base: Self.base, ours: ours, theirs: theirs)
        #expect(merged.apiPort == 50_000)
        #expect(merged.lanPort != merged.apiPort)
    }

    /// The whole story with a real file: a typo, changes that can't be saved, then the fix.
    @Test func changesMadeWhileTheFileWasBrokenSurviveTheFix() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("casement-merge-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("config.json")
        var file = SettingsFile(url: url)
        let base = Self.base
        #expect(try file.save(base) == .saved)

        try Data("{ \"theme\": \"graphite\", \"outline\": ".utf8).write(to: url)
        #expect(file.read().problem != nil)
        var memory = base
        memory.outline = true
        #expect(try file.save(memory) == .refused)

        var fixed = base
        fixed.theme = .graphite
        try JSONEncoder().encode(fixed).write(to: url)
        guard case .loaded(let theirs) = file.read() else { Issue.record("expected loaded"); return }
        #expect(file.problem == nil)
        let merged = CasementSettings.merged(base: base, ours: memory, theirs: theirs)
        #expect(merged.outline)
        #expect(merged.theme == .graphite)
        // Saved, the fixed file holds both.
        #expect(try file.save(merged) == .saved)
        #expect(file.read().value == merged)
    }
}
