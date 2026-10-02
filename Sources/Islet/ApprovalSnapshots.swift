import AppKit
import IsletCore

extension Snapshots {
    /// Approval cards: a risky command with more waiting, an ordinary command, an edit, a
    /// Codex request from a subagent, questions and a plan.
    @MainActor
    static func renderApprovals(model: AppModel, shoot: (String) -> Void) {
        let cwd = "/Users/me/code/islet"
        let terminal = TerminalContext(values: ["TERM_PROGRAM": "Apple_Terminal", "__CFBundleIdentifier": "com.apple.Terminal"])
        func claude(_ tool: String, _ input: JSONValue, kind: ApprovalRequest.Kind = .tool, hook: ApprovalRequest.Hook = .permissionRequest,
                    suggestions: [JSONValue] = [], agent: String? = nil) -> ApprovalRequest {
            ApprovalRequest(provider: .claude, hook: hook, sessionID: "demo", cwd: cwd, toolName: tool, toolInput: input,
                            kind: kind, suggestions: suggestions, agentType: agent, terminal: terminal)
        }
        let rule: JSONValue = .object([
            "type": "addRules", "behavior": "allow", "destination": "localSettings",
            "rules": .array([.object(["toolName": "Bash", "ruleContent": "swift test:*"])]),
        ])
        let risky = claude("Bash", .object([
            "command": "rm -rf .build ~/Library/Caches/org.swift.swiftpm && git push --force origin main",
            "description": "Clean every build cache and force-push the rewritten history",
        ]))
        let tests = claude("Bash", .object(["command": "swift test --filter ApprovalTests", "description": "Run the approval tests"]),
                           suggestions: [rule])
        let edit = claude("Edit", .object([
            "file_path": .string("\(cwd)/Sources/IsletCore/RiskRules.swift"),
            "old_string": "case \"sudo\", \"doas\":\n    return [\"Runs with administrator rights\"]",
            "new_string": "case \"sudo\", \"doas\", \"run0\":\n    return [\"Runs with administrator rights\"]",
        ]), suggestions: [.object(["type": "setMode", "mode": "acceptEdits", "destination": "session"])])
        let codex = ApprovalRequest(provider: .codex, hook: .permissionRequest, sessionID: "c1", cwd: "/Users/me/code/api",
                                    toolName: "shell", toolInput: .object(["command": .array(["bash", "-lc", "npm publish --access public"])]),
                                    agentType: "release", terminal: terminal)
        // An MCP tool from a subagent: what it does in words, its input as plain lines.
        let mcp = claude("mcp__github__create_issue", .object([
            "repo": "me/islet", "title": "Approval card shows raw JSON", "labels": .array(["bug", "ui"]),
            "body": "The card for an MCP tool shows braces and quotes.\nIt should read as plain lines.",
        ]), suggestions: [.object([
            "type": "addRules", "behavior": "allow", "destination": "localSettings",
            "rules": .array([.object(["toolName": "mcp__github__create_issue"])]),
        ])], agent: "general-purpose")
        let questions = claude("AskUserQuestion", .object([:]), kind: .questions([
            AgentQuestion(question: "Which storage should the shelf use for large files?", header: "Storage", options: [
                .init(label: "Keep in place", detail: "Store a bookmark to the original file"),
                .init(label: "Copy to Application Support"),
                .init(label: "Ask each time"),
                .init(label: "Move to iCloud Drive"),
            ]),
            AgentQuestion(question: "Also show the shelf on external displays?", options: [.init(label: "Yes"), .init(label: "No")]),
        ]), hook: .preToolUse)
        let multi = claude("AskUserQuestion", .object([:]), kind: .questions([
            AgentQuestion(question: "Which checks should run before release?", header: "Checks", options: [
                .init(label: "Unit tests"), .init(label: "UI snapshots"), .init(label: "Performance"), .init(label: "Notarisation"),
            ], multiSelect: true),
        ]), hook: .preToolUse)
        let plan = claude("ExitPlanMode", .object([:]), kind: .plan("""
        ## Plan: approvals from the notch
        1. Parse `PermissionRequest` payloads in **IsletCore**
        2. Hold the hook request until the card is answered
           - fall back to the terminal after the wait
        3. Show the card with Allow, Always and Deny
        - [ ] Snapshot every card
        ```
        swift test
        ```
        """), hook: .preToolUse)

        model.forcedPresentation = .expanded
        model.tab = .home
        let cards: [(String, [ApprovalRequest])] = [
            ("30-approval-risky", [risky, tests, edit]),
            ("31-approval-command", [tests]),
            ("32-approval-edit", [edit]),
            ("33-approval-codex-subagent", [codex]),
            ("34-approval-question", [questions]),
            ("35-approval-multiselect", [multi]),
            ("36-approval-plan", [plan]),
            ("37-approval-mcp", [mcp]),
        ]
        for (name, requests) in cards {
            model.approvals.showForSnapshot(requests)
            shoot(name)
        }
        // Increase Contrast: a clear edge round the command, the buttons and the options.
        increasedContrast = true
        model.approvals.showForSnapshot([risky, tests])
        shoot("84-contrast-approval-risky")
        model.approvals.showForSnapshot([multi])
        shoot("85-contrast-approval-question")
        increasedContrast = false
        model.approvals.showForSnapshot([])
    }
}
