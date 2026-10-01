import Foundation
import Testing
@testable import IsletCore

@Suite struct ClaudeUsageHintTests {
    let cli = "/Applications/Islet.app/Contents/MacOS/isletctl"

    func decide(enabled: Bool = true, dismissed: Bool = false, installed: Bool = true,
                statusLine: ClaudeStatusLineSetup.Status? = .notInstalled(current: nil),
                hasUsage: Bool = false, canInstall: Bool = true) -> ClaudeUsageHint? {
        ClaudeUsageHint.decide(enabled: enabled, dismissed: dismissed, claudeInstalled: installed,
                               statusLine: statusLine, hasUsage: hasUsage, canInstall: canInstall)
    }

    @Test func offersToShowUsageWhenClaudeCodeHasNoStatusLineFromIslet() {
        #expect(decide() == .offer)
        // Also when the user has a status line of their own: Islet would wrap it.
        #expect(decide(statusLine: .notInstalled(current: "~/.claude/statusline.sh")) == .offer)
    }

    @Test func waitsOnceSetUpUntilFiguresArrive() {
        #expect(decide(statusLine: .installed(original: nil)) == .waiting)
        #expect(decide(statusLine: .installed(original: "bun x ccstatusline")) == .waiting)
        #expect(decide(statusLine: .installed(original: nil), canInstall: false) == .waiting)
        #expect(decide(statusLine: .installed(original: nil), hasUsage: true) == nil)
    }

    @Test func quietWhenItCantHelp() {
        #expect(decide(installed: false) == nil, "Claude Code isn't installed")
        #expect(decide(hasUsage: true) == nil, "usage is connected")
        #expect(decide(enabled: false) == nil, "Claude usage is switched off")
        #expect(decide(dismissed: true) == nil, "the x hides it for good")
        #expect(decide(dismissed: true, statusLine: .installed(original: nil)) == nil)
        #expect(decide(canInstall: false) == nil, "no isletctl to add")
        #expect(decide(statusLine: .unsupported("statusLine isn't a command")) == nil)
        #expect(decide(statusLine: nil) == nil)
    }

    @Test func followsTheStatusLineThroughSetUp() throws {
        let before = Data(#"{"model": "opus"}"#.utf8)
        #expect(decide(statusLine: ClaudeStatusLineSetup.status(of: before)) == .offer)
        let edit = try ClaudeStatusLineSetup.install(into: before, cli: cli)
        #expect(decide(statusLine: ClaudeStatusLineSetup.status(of: edit.settings)) == .waiting)
        let removed = try ClaudeStatusLineSetup.remove(from: edit.settings)
        #expect(decide(statusLine: ClaudeStatusLineSetup.status(of: removed.settings)) == .offer)
    }

    @Test func claudeCodeLooksInstalledOnceItsSettingsFolderExists() throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent("islet-hint-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: home) }
        let folder = ClaudeCodeInstall.configDirectory(home: home)
        #expect(folder.lastPathComponent == ".claude")
        #expect(ClaudeCodeInstall.settingsFile(in: folder).lastPathComponent == "settings.json")
        #expect(!ClaudeCodeInstall.looksInstalled(configDirectory: folder))
        // A file with the folder's name doesn't count.
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        try Data().write(to: folder)
        #expect(!ClaudeCodeInstall.looksInstalled(configDirectory: folder))
        try FileManager.default.removeItem(at: folder)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        #expect(ClaudeCodeInstall.looksInstalled(configDirectory: folder))
    }
}

@Suite struct ClaudeUsageHintSettingTests {
    @Test func shownByDefaultAndSavedToTheConfig() throws {
        let s = IsletSettings()
        #expect(s.claudeUsageHint)
        #expect(!IsletSettings.decodeLenient(Data(#"{"claudeUsageHint": false}"#.utf8)).claudeUsageHint)
        // A bad value falls back to the default without touching the other keys.
        let bad = IsletSettings.decodeLenient(Data(#"{"claudeUsageHint": "later", "claudeUsageEnabled": false}"#.utf8))
        #expect(bad.claudeUsageHint)
        #expect(!bad.claudeUsageEnabled)
        let keys = try JSONSerialization.jsonObject(with: JSONEncoder().encode(s)) as? [String: Any]
        #expect(keys?["claudeUsageHint"] as? Bool == true)
    }
}
