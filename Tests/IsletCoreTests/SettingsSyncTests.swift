import Foundation
import Testing

/// A setting changed anywhere but the Settings window (the island's own controls, a link) is
/// saved and applied as an edit in Settings is: `saveAndApplySettings()`, or `settingsEdited()`
/// for a change that comes in steps. Saving alone would leave what depends on it as it was
/// until the next change.
@Suite struct SettingsSyncTests {
    static let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

    /// Every place that saves without applying, with how often: the settings machinery itself,
    /// and writing config.json before showing it.
    static let savesOnly: [String: Int] = [
        "AppModel.swift|saveSettings()": 1,  // saveAndApplySettings
        "AppModel.swift|self?.saveSettings()": 1,  // settingsEdited, which posts next
        "AppModel.swift|if !FileManager.default.fileExists(atPath: IsletPaths.configFile.path) { saveSettings() }": 1,
        "AppModel.swift|if next != fresh { saveSettings() }": 1,  // config.json read, already applied
        "AdvancedSettings.swift|model.saveSettings()": 2,  // Show in Finder, Open config.json
        "main.swift|model.saveSettings()": 1,  // Edit config.json in the status menu
    ]

    @Test func changesOutsideSettingsAreApplied() throws {
        let sources = Self.root.appendingPathComponent("Sources/Islet")
        let files = FileManager.default.enumerator(at: sources, includingPropertiesForKeys: nil)?
            .compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" } ?? []
        #expect(!files.isEmpty)
        var found: [String: Int] = [:]
        for file in files {
            let text = try String(contentsOf: file, encoding: .utf8)
            for line in text.split(separator: "\n") where line.contains("saveSettings()") && !line.contains("func saveSettings") {
                found["\(file.lastPathComponent)|\(line.trimmingCharacters(in: .whitespaces))", default: 0] += 1
            }
        }
        #expect(found == Self.savesOnly, "Use saveAndApplySettings() so the change takes effect: \(found)")
    }
}
