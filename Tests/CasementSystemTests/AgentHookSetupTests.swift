import Foundation
import Testing
@testable import CasementCore
@testable import CasementSystem

@Suite struct AgentHookSetupTests {
    func tempHome() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("casement-agents-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    @Test func connectsCodexAndKeepsBackups() throws {
        let home = try tempHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let codex = home.appendingPathComponent(".codex")
        try FileManager.default.createDirectory(at: codex, withIntermediateDirectories: true)
        let config = Data("model = \"gpt-5\"\n".utf8)
        try config.write(to: codex.appendingPathComponent("config.toml"))

        #expect(AgentHookSetup.connection(.codex, home: home, executable: "casementctl", wait: 300) == .notConnected)
        let plan = try AgentHookSetup.plan(.codex, home: home, executable: "casementctl", wait: 300)
        try AgentHookSetup.apply(plan)

        #expect(try String(contentsOf: codex.appendingPathComponent("config.toml"), encoding: .utf8)
                == "model = \"gpt-5\"\n\n[features]\nhooks = true\n")
        #expect(try Data(contentsOf: codex.appendingPathComponent("config.toml.bak")) == config)
        // hooks.json was new, so it has no backup.
        #expect(!FileManager.default.fileExists(atPath: codex.appendingPathComponent("hooks.json.bak").path))
        #expect(AgentHookSetup.connection(.codex, home: home, executable: "casementctl", wait: 300) == .connected)
        #expect(AgentHookSetup.connection(.codex, home: home, executable: "casementctl", wait: 60) == .needsUpdate)
    }

    @Test func reportsAgentsThatHaveNotRunAndBrokenFiles() throws {
        let home = try tempHome()
        defer { try? FileManager.default.removeItem(at: home) }
        #expect(AgentHookSetup.connection(.cursor, home: home, executable: "casementctl", wait: 300) == .notFound)

        let cursor = home.appendingPathComponent(".cursor")
        try FileManager.default.createDirectory(at: cursor, withIntermediateDirectories: true)
        let broken = Data("{ \"hooks\": ".utf8)
        try broken.write(to: cursor.appendingPathComponent("hooks.json"))
        #expect(AgentHookSetup.connection(.cursor, home: home, executable: "casementctl", wait: 300)
                == .problem("Cursor\u{2019}s settings file couldn\u{2019}t be read, so Casement left it alone. You can set it up by hand in Advanced."))
        #expect(throws: ClaudeHookInstaller.InstallError.notJSON) {
            try AgentHookSetup.plan(.cursor, home: home, executable: "casementctl", wait: 300)
        }
        #expect(try Data(contentsOf: cursor.appendingPathComponent("hooks.json")) == broken)
    }

    @Test func claudeCodeGoesThroughTheSameInstaller() throws {
        let home = try tempHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let plan = try AgentHookSetup.plan(.claudeCode, home: home, executable: "casementctl", wait: 300)
        #expect(plan.changes.count == 10)
        try AgentHookSetup.apply(plan)
        let url = home.appendingPathComponent(".claude/settings.json")
        #expect(try ClaudeHookSetup.plan(at: url, executable: "casementctl", wait: 300).isUpToDate)
        #expect(AgentHookSetup.connection(.claudeCode, home: home, executable: "casementctl", wait: 300) == .connected)
    }
}
