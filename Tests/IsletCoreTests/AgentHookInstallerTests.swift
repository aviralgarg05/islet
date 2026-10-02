import Foundation
import Testing
@testable import IsletCore

@Suite struct CodexHookInstallerTests {
    func commands(_ data: Data, _ event: String) -> [String] {
        (JSONValue.parse(data)?["hooks"]?[event]?.arrayValue ?? [])
            .flatMap { ($0["hooks"]?.arrayValue ?? []).compactMap { $0["command"]?.stringValue } }
    }

    @Test func freshInstall() throws {
        let plan = try CodexHookInstaller.plan(existing: nil, wait: 300)
        #expect(plan.changes == ["Add PermissionRequest: isletctl hook codex --wait 300", "Add PostToolUse: isletctl hook codex",
                                 "Add UserPromptSubmit: isletctl hook codex", "Add Stop: isletctl hook codex"])
        #expect(commands(plan.merged, "PermissionRequest") == ["isletctl hook codex --wait 300"])
        let hook = JSONValue.parse(plan.merged)?["hooks"]?["PermissionRequest"]?.arrayValue?.first?["hooks"]?.arrayValue?.first
        #expect(hook?["timeout"] == .number(330))
    }

    @Test func keepsTheUsersHooksAndClaudesAreNotCodexs() throws {
        let existing = #"{"hooks": {"Stop": [{"hooks": [{"type": "command", "command": "isletctl hook claude"}]}]}}"#
        let plan = try CodexHookInstaller.plan(existing: Data(existing.utf8), wait: 300)
        #expect(commands(plan.merged, "Stop") == ["isletctl hook claude", "isletctl hook codex"])
    }

    @Test func idempotentAndFollowsTheWait() throws {
        let first = try CodexHookInstaller.plan(existing: nil, wait: 300)
        #expect(try CodexHookInstaller.plan(existing: first.merged, wait: 300).isUpToDate)
        let longer = try CodexHookInstaller.plan(existing: first.merged, wait: 120)
        #expect(longer.changes == ["Update PermissionRequest: isletctl hook codex --wait 120"])
    }

    @Test func shippedHooksMatchTheInstaller() throws {
        let repo = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let shipped = try Data(contentsOf: repo.appendingPathComponent("integrations/codex/hooks.json"))
        #expect(try CodexHookInstaller.plan(existing: shipped, wait: 300).isUpToDate)
    }
}

@Suite struct CursorHookInstallerTests {
    func commands(_ data: Data, _ event: String) -> [String] {
        (JSONValue.parse(data)?["hooks"]?[event]?.arrayValue ?? []).compactMap { $0["command"]?.stringValue }
    }

    @Test func freshInstall() throws {
        let plan = try CursorHookInstaller.plan(existing: nil, executable: "/Applications/Islet.app/Contents/MacOS/isletctl", wait: 300)
        #expect(plan.changes.count == 5)
        let root = try #require(JSONValue.parse(plan.merged))
        #expect(root["version"] == .number(1))
        #expect(commands(plan.merged, "beforeShellExecution") == ["/Applications/Islet.app/Contents/MacOS/isletctl hook cursor --wait 300"])
        #expect(root["hooks"]?["beforeMCPExecution"]?.arrayValue?.first?["timeout"] == .number(330))
        #expect(commands(plan.merged, "stop") == ["/Applications/Islet.app/Contents/MacOS/isletctl hook cursor"])
    }

    @Test func keepsTheUsersHooksAndVersion() throws {
        let existing = #"{"version": 2, "hooks": {"stop": [{"command": "say done"}], "beforeReadFile": [{"command": "./guard.sh"}]}}"#
        let plan = try CursorHookInstaller.plan(existing: Data(existing.utf8), wait: 300)
        let root = try #require(JSONValue.parse(plan.merged))
        #expect(root["version"] == .number(2))
        #expect(commands(plan.merged, "stop") == ["say done", "isletctl hook cursor"])
        #expect(commands(plan.merged, "beforeReadFile") == ["./guard.sh"])
    }

    @Test func idempotentAndFollowsTheWait() throws {
        let first = try CursorHookInstaller.plan(existing: nil, wait: 300)
        let again = try CursorHookInstaller.plan(existing: first.merged, wait: 300)
        #expect(again.isUpToDate)
        #expect(again.merged == first.merged)
        let shorter = try CursorHookInstaller.plan(existing: first.merged, wait: 60)
        #expect(shorter.changes == ["Update beforeShellExecution: isletctl hook cursor --wait 60",
                                    "Update beforeMCPExecution: isletctl hook cursor --wait 60"])
        #expect(JSONValue.parse(shorter.merged)?["hooks"]?["beforeShellExecution"]?.arrayValue?.count == 1)
    }

    @Test func refusesFilesItDoesNotUnderstand() {
        #expect(throws: ClaudeHookInstaller.InstallError.notJSON) { try CursorHookInstaller.plan(existing: Data("nope".utf8), wait: 300) }
        #expect(throws: ClaudeHookInstaller.InstallError.unexpectedShape("hooks.stop")) {
            try CursorHookInstaller.plan(existing: Data(#"{"hooks": {"stop": {"command": "x"}}}"#.utf8), wait: 300)
        }
    }

    @Test func shippedHooksMatchTheInstaller() throws {
        let repo = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let shipped = try Data(contentsOf: repo.appendingPathComponent("integrations/cursor/hooks.json"))
        #expect(try CursorHookInstaller.plan(existing: shipped, wait: 300).isUpToDate)
    }
}

@Suite struct CodexConfigEditorTests {
    @Test func addsTheTableToAMissingOrEmptyFile() throws {
        #expect(try CodexConfigEditor.enableHooks(in: nil).text == "[features]\nhooks = true\n")
        #expect(try CodexConfigEditor.enableHooks(in: "").text == "[features]\nhooks = true\n")
    }

    @Test func appendsAfterTheUsersSettings() throws {
        let edit = try CodexConfigEditor.enableHooks(in: "model = \"gpt-5\"\n\n[profiles.fast]\nmodel = \"mini\"\n\n")
        #expect(edit.text == "model = \"gpt-5\"\n\n[profiles.fast]\nmodel = \"mini\"\n\n[features]\nhooks = true\n")
        #expect(edit.changes == ["Turn on hooks in [features]"])
    }

    @Test func addsTheKeyToAnExistingTable() throws {
        let edit = try CodexConfigEditor.enableHooks(in: "[features] # experiments\nweb_search = true\n\n[tui]\ntheme = \"dark\"\n")
        #expect(edit.text == "[features] # experiments\nhooks = true\nweb_search = true\n\n[tui]\ntheme = \"dark\"\n")
    }

    @Test func turnsOnAKeyThatIsOff() throws {
        let edit = try CodexConfigEditor.enableHooks(in: "[features]\n  hooks = false # for now\n")
        #expect(edit.text == "[features]\n  hooks = true\n")
        #expect(try CodexConfigEditor.enableHooks(in: "features.hooks = false\n").text == "features.hooks = true\n")
    }

    @Test func leavesAFileThatIsAlreadyOnAlone() throws {
        let text = "notify = [\"isletctl\", \"hook\", \"codex\"]\n[features]\nhooks = true"
        let edit = try CodexConfigEditor.enableHooks(in: text)
        #expect(edit.isUpToDate)
        #expect(edit.text == text)
        #expect(try CodexConfigEditor.enableHooks(in: "features . hooks = true # yes\n").isUpToDate)
    }

    @Test func ignoresLookalikes() throws {
        // A key in another table, a sub-table and a string are not the setting.
        let text = "[other]\nhooks = false\nnote = \"[features] hooks = false\"\n[features.extra]\nx = 1\n"
        let edit = try CodexConfigEditor.enableHooks(in: text)
        #expect(edit.text == text + "\n[features]\nhooks = true\n")
    }

    @Test func refusesFormsItDoesNotEdit() {
        #expect(throws: CodexConfigEditor.EditError.unexpectedShape("features")) {
            try CodexConfigEditor.enableHooks(in: "features = { hooks = false }\n")
        }
        #expect(throws: CodexConfigEditor.EditError.unexpectedShape("features.hooks")) {
            try CodexConfigEditor.enableHooks(in: "[features]\nhooks = \"yes\"\n")
        }
    }

    @Test func shippedConfigHasHooksOn() throws {
        let repo = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let shipped = try String(contentsOf: repo.appendingPathComponent("integrations/codex/config.toml"), encoding: .utf8)
        #expect(try CodexConfigEditor.enableHooks(in: shipped).isUpToDate)
    }
}

@Suite struct AgentHookPlanTests {
    let home = URL(fileURLWithPath: "/Users/someone")

    @Test func plansEveryFileOfAnAgent() throws {
        let plan = try AgentHookPlan.make(.codex, home: home, executable: "isletctl", wait: 300) { _ in nil }
        #expect(plan.files.map(\.url.path) == ["/Users/someone/.codex/hooks.json", "/Users/someone/.codex/config.toml"])
        #expect(plan.changes.last == "Turn on hooks in [features]")
        #expect(plan.changedFiles.count == 2)
    }

    @Test func connectionStates() throws {
        let fresh = try AgentHookPlan.make(.cursor, home: home, executable: "isletctl", wait: 300) { _ in nil }
        #expect(AgentConnection.decide(.cursor, installed: true, plan: .success(fresh)) == .notConnected)
        #expect(AgentConnection.decide(.cursor, installed: false, plan: .success(fresh)) == .notFound)

        let installed = fresh.files[0].contents
        let same = try AgentHookPlan.make(.cursor, home: home, executable: "isletctl", wait: 300) { _ in installed }
        #expect(AgentConnection.decide(.cursor, installed: true, plan: .success(same)) == .connected)
        let longer = try AgentHookPlan.make(.cursor, home: home, executable: "isletctl", wait: 600) { _ in installed }
        #expect(AgentConnection.decide(.cursor, installed: true, plan: .success(longer)) == .needsUpdate)

        let broken = AgentConnection.decide(.codex, installed: true, plan: .failure(ClaudeHookInstaller.InstallError.notJSON))
        #expect(broken == .problem("Codex\u{2019}s settings file couldn\u{2019}t be read, so Islet left it alone. You can set it up by hand in Advanced."))
        // Never a file's name, its format or a system error's codes.
        let shape = AgentConnection.decide(.claudeCode, installed: true, plan: .failure(ClaudeHookInstaller.InstallError.unexpectedShape("hooks.PreToolUse")))
        #expect(shape == .problem("Claude Code\u{2019}s settings are laid out in a way Islet doesn\u{2019}t change, so Islet left them alone. You can set it up by hand in Advanced."))
        let toml = AgentConnection.decide(.codex, installed: true, plan: .failure(CodexConfigEditor.EditError.unexpectedShape("features")))
        let disk = AgentConnection.problemText(for: CocoaError(.fileWriteNoPermission, userInfo: [NSFilePathErrorKey: "/Users/someone/.cursor/hooks.json"]), agent: .cursor)
        #expect(disk == "Islet couldn\u{2019}t change Cursor\u{2019}s settings. Check that you can edit them, then try again.")
        for case .problem(let text) in [broken, shape, toml, .problem(disk)] {
            for jargon in ["JSON", ".json", ".toml", "hooks", "[features]", "PreToolUse", "Error Domain", "Code="] {
                #expect(!text.contains(jargon), "\(text)")
            }
        }
        #expect(broken.label == "Can't connect")
    }

    @Test func eachAgentHasItsFolder() {
        #expect(CodingAgent.claudeCode.files(home: home).map(\.lastPathComponent) == ["settings.json"])
        #expect(CodingAgent.cursor.configDirectory(home: home).path == "/Users/someone/.cursor")
        #expect(CodingAgent.allCases.map(\.title) == ["Claude Code", "Codex", "Cursor"])
    }
}
