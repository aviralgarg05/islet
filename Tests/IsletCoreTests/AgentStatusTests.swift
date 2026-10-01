import Foundation
import Testing
@testable import IsletCore

private func spec(_ provider: String, _ json: String) throws -> ActivitySpec {
    guard case .upsert(let s) = try AgentHooks.map(provider: provider, payload: Data(json.utf8), now: t0) else {
        Issue.record("expected an activity for \(json)")
        return ActivitySpec()
    }
    return s
}

/// Codex and Cursor connected from Settings report what they are doing, not only approvals.
@Suite struct CodexAndCursorStatusTests {
    @Test func codexHooksFollowOneSession() throws {
        let base = #""session_id":"019a-codex","cwd":"/Users/me/code/api""#
        let prompt = try spec("codex", "{\(base),\"hook_event_name\":\"UserPromptSubmit\",\"prompt\":\"fix the build\"}")
        #expect(prompt.id == "codex-019a-codex")
        #expect(prompt.title == "Codex · api")
        #expect(prompt.state == .running && prompt.subtitle == "Thinking…" && prompt.sneak == false)
        #expect(prompt.staleAt == t0.addingTimeInterval(AgentHooks.staleAfter))

        let tool = try spec("codex", "{\(base),\"hook_event_name\":\"PostToolUse\",\"tool_name\":\"shell\",\"tool_input\":{\"command\":[\"bash\",\"-lc\",\"swift build\"]}}")
        #expect(tool.id == prompt.id)
        #expect(tool.subtitle == "Running swift build" && tool.state == .running)

        let ask = try spec("codex", HookFixtures.codexPermission)
        #expect(ask.id == prompt.id)
        #expect(ask.state == .waiting && ask.priority == .high && ask.trailing == "Waiting")
        #expect(ask.subtitle == "Needs approval: Running git push --force origin main")

        let done = try spec("codex", "{\(base),\"hook_event_name\":\"Stop\"}")
        #expect(done.id == prompt.id)
        #expect(done.state == .success && done.subtitle == "Done. Your turn." && done.ttl == 30 && done.sneak == true)
        let said = try spec("codex", "{\(base),\"hook_event_name\":\"Stop\",\"last_assistant_message\":\"All 12 tests pass.\"}")
        #expect(said.subtitle == "All 12 tests pass.")
        #expect(try AgentHooks.map(provider: "codex", payload: Data("{\(base),\"hook_event_name\":\"SessionEnd\"}".utf8)) == .remove(id: prompt.id ?? ""))
        #expect(try AgentHooks.map(provider: "codex", payload: Data("{\(base),\"hook_event_name\":\"Elsewhere\"}".utf8)) == .ignore)
    }

    @Test func codexNotifyStillWorks() throws {
        let s = try spec("codex", #"{"type":"agent-turn-complete","thread-id":"019a-codex","cwd":"/Users/me/code/api","last-assistant-message":"Done here"}"#)
        #expect(s.id == "codex-019a-codex" && s.state == .success && s.subtitle == "Done here")
        #expect(try AgentHooks.map(provider: "codex", payload: Data(#"{"type":"something-else"}"#.utf8)) == .ignore)
    }

    @Test func codexToolsInAFewWords() {
        #expect(AgentHooks.describeCodexTool("shell", input: ["command": ["git", "status"]]) == "Running git status")
        #expect(AgentHooks.describeCodexTool("exec_command", input: ["cmd": "make test"]) == "Running make test")
        #expect(AgentHooks.describeCodexTool("apply_patch", input: ["input": "*** Begin Patch\n*** Update File: Sources/App.swift\n@@"]) == "Editing App.swift")
        #expect(AgentHooks.describeCodexTool("apply_patch", input: nil) == "Editing files")
        #expect(AgentHooks.describeCodexTool("update_plan", input: nil) == "Updating the plan")
        #expect(AgentHooks.describeCodexTool("shell", input: [:]) == "Running a command")
    }

    @Test func secretsAreHiddenInCommands() throws {
        let codex = try spec("codex", #"{"session_id":"s1","hook_event_name":"PostToolUse","tool_name":"shell","tool_input":{"command":["bash","-lc","API_KEY=sk-abcdefgh12345 make deploy"]}}"#)
        #expect(codex.subtitle?.contains("sk-abcdefgh12345") == false)
        #expect(codex.subtitle?.contains("•••") == true)
        let cursor = try spec("cursor", #"{"conversation_id":"c1","hook_event_name":"afterShellExecution","command":"curl -H 'Authorization: Bearer abcdefghijklmnop' https://x.dev","output":"ok"}"#)
        #expect(cursor.subtitle?.contains("abcdefghijklmnop") == false)
    }

    @Test func cursorHooksFollowOneConversation() throws {
        let shell = try spec("cursor", HookFixtures.cursorShell)
        #expect(shell.id == "cursor-conv-1")
        #expect(shell.source == "cursor")
        #expect(shell.title == "Cursor · web")
        #expect(shell.state == .running && shell.subtitle == "Running npm install left-pad")

        let mcp = try spec("cursor", #"{"conversation_id":"conv-1","hook_event_name":"afterMCPExecution","tool_name":"create_issue","workspace_roots":["/Users/me/web"]}"#)
        #expect(mcp.id == shell.id && mcp.subtitle == "Using create_issue")

        let done = try spec("cursor", #"{"conversation_id":"conv-1","hook_event_name":"stop","status":"completed","workspace_roots":["/Users/me/web"]}"#)
        #expect(done.id == shell.id && done.state == .success && done.sneak == true && done.ttl == 30)
        let failed = try spec("cursor", #"{"conversation_id":"conv-1","hook_event_name":"stop","status":"error"}"#)
        #expect(failed.state == .failure && failed.priority == .high && failed.trailing == "Error")
        let stopped = try spec("cursor", #"{"conversation_id":"conv-1","hook_event_name":"stop","status":"aborted"}"#)
        #expect(stopped.state == .success && stopped.sneak == false && stopped.subtitle == "Stopped")
        #expect(try AgentHooks.map(provider: "cursor", payload: Data(#"{"conversation_id":"c","hook_event_name":"beforeReadFile"}"#.utf8)) == .ignore)
    }

    @Test func cursorWithoutHookEventNameIsTheGenericShape() throws {
        let s = try spec("cursor", #"{"session":"s1","event":"waiting","message":"Pick one"}"#)
        #expect(s.id == "cursor-s1" && s.state == .waiting)
    }
}

/// Hooks left pointing at an old isletctl plan an Update, and Disconnect takes out only Islet's.
@Suite struct AgentHookUpkeepTests {
    let home = URL(fileURLWithPath: "/Users/someone")
    let old = "/Volumes/Old/Islet.app/Contents/MacOS/isletctl"
    let new = "/Applications/Islet.app/Contents/MacOS/isletctl"

    @Test func aMovedAppPlansAnUpdate() throws {
        for agent in CodingAgent.allCases {
            let first = try AgentHookPlan.make(agent, home: home, executable: old, wait: 300) { _ in nil }
            let installed = Dictionary(uniqueKeysWithValues: first.files.map { ($0.url, $0.contents) })
            let moved = try AgentHookPlan.make(agent, home: home, executable: new, wait: 300) { installed[$0] }
            #expect(moved.wasConnected, "\(agent)")
            #expect(!moved.changes.isEmpty && moved.changes.allSatisfy { $0.hasPrefix("Update ") }, "\(agent): \(moved.changes)")
            #expect(AgentConnection.decide(agent, installed: true, plan: .success(moved)) == .needsUpdate)
            let commands = ClaudeHookInstaller.commands(in: moved.files[0].contents)
            #expect(!commands.contains { $0.contains(old) }, "\(agent)")
            // Updated, it is connected again.
            let updated = Dictionary(uniqueKeysWithValues: moved.files.map { ($0.url, $0.contents) })
            let again = try AgentHookPlan.make(agent, home: home, executable: new, wait: 300) { updated[$0] }
            #expect(AgentConnection.decide(agent, installed: true, plan: .success(again)) == .connected)
        }
    }

    @Test func aMissingHookOnAConnectedAgentIsAnUpdateToo() throws {
        let one = #"{"hooks": {"Stop": [{"hooks": [{"type": "command", "command": "isletctl hook claude"}]}]}}"#
        let plan = try AgentHookPlan.make(.claudeCode, home: home, executable: "isletctl", wait: 300) { _ in Data(one.utf8) }
        #expect(plan.wasConnected && plan.changes.contains { $0.hasPrefix("Add ") })
        #expect(AgentConnection.decide(.claudeCode, installed: true, plan: .success(plan)) == .needsUpdate)
        let other = #"{"hooks": {"Stop": [{"hooks": [{"type": "command", "command": "isletctl hook codex"}]}]}}"#
        let notOurs = try AgentHookPlan.make(.claudeCode, home: home, executable: "isletctl", wait: 300) { _ in Data(other.utf8) }
        #expect(AgentConnection.decide(.claudeCode, installed: true, plan: .success(notOurs)) == .notConnected)
    }

    @Test func disconnectKeepsTheUsersHooks() throws {
        let installed = try ClaudeHookInstaller.plan(existing: Data(#"""
        {"model": "opus", "env": {"FOO": "1"},
         "hooks": {"Stop": [{"hooks": [{"type": "command", "command": "say done", "timeout": 5}]}],
                   "PreToolUse": [{"matcher": "Bash", "hooks": [{"type": "command", "command": "./guard.sh"}]}]}}
        """#.utf8), executable: new, wait: 300).merged
        let plan = try AgentHookPlan.disconnect(.claudeCode, home: home) { _ in installed }
        #expect(plan.kind == .disconnect)
        #expect(plan.changes.count == ClaudeHookInstaller.entries(wait: 300).count)
        #expect(plan.changes.allSatisfy { $0.hasPrefix("Remove ") })
        let after = try #require(JSONValue.parse(plan.files[0].contents))
        #expect(after["model"] == "opus")
        #expect(after["env"] == .object(["FOO": "1"]))
        #expect(after["hooks"]?["Stop"] == .array([.object(["hooks": .array([.object(["type": "command", "command": "say done", "timeout": .number(5)])])])]))
        #expect(after["hooks"]?["PreToolUse"] == .array([.object(["matcher": "Bash", "hooks": .array([.object(["type": "command", "command": "./guard.sh"])])])]))
        #expect(!ClaudeHookInstaller.commands(in: plan.files[0].contents).contains { $0.contains("isletctl") })
        // Nothing of Islet's left: nothing to do, and the file isn't touched.
        let again = try AgentHookPlan.disconnect(.claudeCode, home: home) { _ in plan.files[0].contents }
        #expect(again.isUpToDate && again.files[0].contents == plan.files[0].contents)
        #expect(try AgentHookPlan.disconnect(.claudeCode, home: home) { _ in nil }.isUpToDate)
    }

    @Test func disconnectKeepsAnotherHookInTheSameGroup() throws {
        let mixed = #"{"hooks": {"Stop": [{"hooks": [{"type": "command", "command": "say done"}, {"type": "command", "command": "isletctl hook codex"}]}]}}"#
        let plan = try CodexHookInstaller.removal(existing: Data(mixed.utf8))
        #expect(plan.changes == ["Remove Stop: isletctl hook codex"])
        #expect(ClaudeHookInstaller.commands(in: plan.merged) == ["say done"])
    }

    @Test func disconnectCursorKeepsItsOtherHooks() throws {
        let installed = try CursorHookInstaller.plan(existing: Data(#"{"version": 2, "hooks": {"stop": [{"command": "say done"}], "beforeReadFile": [{"command": "./guard.sh"}]}}"#.utf8),
                                                     executable: new, wait: 300).merged
        let plan = try AgentHookPlan.disconnect(.cursor, home: home) { _ in installed }
        #expect(plan.changes.count == CursorHookInstaller.entries(wait: 300).count)
        let after = try #require(JSONValue.parse(plan.files[0].contents))
        #expect(after["version"] == .number(2))
        #expect(after["hooks"]?["stop"] == .array([.object(["command": "say done"])]))
        #expect(after["hooks"]?["beforeReadFile"] == .array([.object(["command": "./guard.sh"])]))
        #expect(after["hooks"]?["beforeShellExecution"] == nil)
    }

    @Test func hooksCallingAMissingIsletctlAreFound() throws {
        let installed = try ClaudeHookInstaller.plan(existing: nil, executable: old, wait: 300).merged
        let missing = AgentHookPlan.missingExecutables(.claudeCode, home: home, read: { _ in installed }, exists: { _ in false })
        #expect(missing == [old])
        #expect(AgentHookPlan.missingExecutables(.claudeCode, home: home, read: { _ in installed }, exists: { $0 == old }).isEmpty)
        // A name on PATH isn't checked, nor another agent's hooks, nor an unreadable file.
        let onPath = try ClaudeHookInstaller.plan(existing: nil, executable: "isletctl", wait: 300).merged
        #expect(AgentHookPlan.missingExecutables(.claudeCode, home: home, read: { _ in onPath }, exists: { _ in false }).isEmpty)
        #expect(AgentHookPlan.missingExecutables(.codex, home: home, read: { _ in installed }, exists: { _ in false }).isEmpty)
        #expect(AgentHookPlan.missingExecutables(.cursor, home: home, read: { _ in throw CocoaError(.fileReadNoPermission) },
                                                 exists: { _ in false }).isEmpty)
        // A quoted path with a space is read whole.
        #expect(ClaudeHookInstaller.isletExecutable("'/Users/me/My Apps/Islet.app/Contents/MacOS/isletctl' hook claude")
                == "/Users/me/My Apps/Islet.app/Contents/MacOS/isletctl")
    }
}
