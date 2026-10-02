import Foundation
import Testing
@testable import IsletCore

/// Muting a source from the island silences everything it sends, Islet's own cards included,
/// and Settings lists it where its feature is.
@Suite struct MuteRoutingTests {
    static let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

    /// Every `commit(` in the app that skips the mute check (`applyLocal`), with how often.
    /// Anything else Islet shows goes through `applyLocal`, so Mute in the island silences it.
    static let unmutedCommits: [(file: String, line: String, count: Int)] = [
        // applyLocal itself, after its mute check.
        ("AppModel.swift", "return try commit(spec)", 1),
        // The local API, after its own mute check (it echoes a muted spec back).
        ("AppModel.swift", "return try self.commit(spec)", 1),
        // A Mac about to run out warns even with Battery muted.
        ("AppModel.swift", "if ev.kind == .critical { _ = try? commit(spec) }", 1),
        // The first launch's hint, shown once.
        ("AppModel.swift", "FirstRunHint.activity(", 1),
        // Appearance's previews, which the user just asked for.
        ("AppActions.swift", "_ = try? model.commit(ActivitySpec(", 2),
    ]

    @Test func onlyTheseSkipTheMuteCheck() throws {
        let sources = Self.root.appendingPathComponent("Sources/Islet")
        let files = FileManager.default.enumerator(at: sources, includingPropertiesForKeys: nil)?
            .compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" } ?? []
        #expect(!files.isEmpty)
        let call = try Regex(#"try\??\s+(self\.|model\.)?commit\("#)
        var left = Dictionary(uniqueKeysWithValues: Self.unmutedCommits.map { ("\($0.file)|\($0.line)", $0.count) })
        var unexpected: [String] = []
        for file in files {
            let text = try String(contentsOf: file, encoding: .utf8)
            for line in text.split(separator: "\n", omittingEmptySubsequences: false) where line.contains(call) {
                let name = file.lastPathComponent
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if let key = Self.unmutedCommits.map({ "\($0.file)|\($0.line)" })
                    .first(where: { $0.hasPrefix(name + "|") && trimmed.contains($0.dropFirst(name.count + 1)) && left[$0, default: 0] > 0 }) {
                    left[key, default: 0] -= 1
                } else {
                    unexpected.append("\(name): \(trimmed)")
                }
            }
        }
        #expect(unexpected.isEmpty, "Use applyLocal so Mute in the island silences these: \(unexpected)")
        #expect(left.values.allSatisfy { $0 == 0 }, "Allowed sites that are gone: \(left.filter { $0.value != 0 })")
    }

    @Test func previewsCantBeMuted() {
        #expect(!MutedSources.canMute("preview"))
        #expect(MutedSources.canMute("battery"))
        #expect(MutedSources.canMute(KeepAwake.source))
        #expect(MutedSources.canMute("com.tinyspeck.slackmacgap"))
    }

    @Test func onlyBatterySaysWhatStillShows() {
        #expect(MutedSources.stillShows("battery") != nil)
        #expect(MutedSources.stillShows("audio") == nil)
    }
}
