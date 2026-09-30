import Foundation
import Testing
@testable import IsletCore

@Suite struct AgentHookTests {
    @Test func silentAgentsGoStaleButWaitingOnesDont() throws {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let working = #"{"hook_event_name":"PreToolUse","session_id":"s1","tool_name":"Bash","tool_input":{"command":"make"}}"#
        guard case .upsert(let a) = try AgentHooks.map(provider: "claude", payload: Data(working.utf8), now: now) else {
            Issue.record("expected an update"); return
        }
        #expect(a.staleAt == now.addingTimeInterval(AgentHooks.staleAfter))
        let waiting = #"{"hook_event_name":"Notification","session_id":"s1","message":"Claude needs your permission"}"#
        guard case .upsert(let b) = try AgentHooks.map(provider: "claude", payload: Data(waiting.utf8), now: now) else {
            Issue.record("expected an update"); return
        }
        #expect(b.staleAt == .distantFuture)
    }

    @Test func commandsShownInTheNotchHideSecrets() {
        // Fake credentials are assembled here so the source never contains anything shaped like
        // a real one (secret scanners would flag it).
        let filler = String(repeating: "x", count: 24)
        let apiKey = ["sk", "proj", filler].joined(separator: "-")
        let pat = "gh" + "p_" + filler
        let bearer = ["Bear", "er ", filler].joined()
        #expect(AgentHooks.redactSecrets("export OPENAI_API_KEY=\(apiKey) && run") == "export OPENAI_API_KEY=••• && run")
        #expect(AgentHooks.redactSecrets("curl -H \"Authorization: \(bearer)\" https://x").contains("Bearer •••"))
        #expect(AgentHooks.redactSecrets("gh auth login --with-token \(pat)") == "gh auth login --with-token •••")
        #expect(AgentHooks.redactSecrets("mysql --pass" + "word=" + filler + " db") == "mysql --password=••• db")
        #expect(AgentHooks.redactSecrets("swift test --filter Foo") == "swift test --filter Foo")
    }

    func map(_ provider: String, _ json: String) throws -> AgentHooks.Result {
        try AgentHooks.map(provider: provider, payload: Data(json.utf8))
    }

    func spec(_ r: AgentHooks.Result) -> ActivitySpec? {
        if case .upsert(let s) = r { return s }
        return nil
    }

    @Test func claudeLifecycle() throws {
        let base = #""session_id":"0f1e2d3c-4b5a","cwd":"/Users/me/proj/web""#
        let prompt = spec(try map("claude", "{\(base),\"hook_event_name\":\"UserPromptSubmit\",\"prompt\":\"fix it\"}"))!
        #expect(prompt.id == "claude-0f1e2d3c-4b5")
        #expect(prompt.state == .running)
        #expect(prompt.progress == -1)
        #expect(prompt.sneak == false)
        #expect(prompt.title == "Claude · web")

        let tool = spec(try map("claude", "{\(base),\"hook_event_name\":\"PreToolUse\",\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"swift test --parallel\"}}"))!
        #expect(tool.subtitle == "Running swift test --parallel")

        let edit = spec(try map("claude", "{\(base),\"hook_event_name\":\"PreToolUse\",\"tool_name\":\"Edit\",\"tool_input\":{\"file_path\":\"/a/b/App.swift\"}}"))!
        #expect(edit.subtitle == "Editing App.swift")

        let waiting = spec(try map("claude", "{\(base),\"hook_event_name\":\"Notification\",\"message\":\"Claude needs your permission to use Bash\"}"))!
        #expect(waiting.state == .waiting)
        #expect(waiting.priority == .high)
        #expect(waiting.sneak == true)

        let stop = spec(try map("claude", "{\(base),\"hook_event_name\":\"Stop\"}"))!
        #expect(stop.state == .success)
        #expect(stop.ttl == 30)

        #expect(try map("claude", "{\(base),\"hook_event_name\":\"PostToolUse\"}") == .ignore)
        #expect(try map("claude", "{\(base),\"hook_event_name\":\"SessionEnd\"}") == .remove(id: "claude-0f1e2d3c-4b5"))
    }

    @Test func mcpToolNamesAreReadable() {
        #expect(AgentHooks.describeTool("mcp__github__create_issue", input: nil) == "Using github")
        #expect(AgentHooks.describeTool("Grep", input: ["pattern": "TODO"]) == "Searching for TODO")
        #expect(AgentHooks.describeTool("Frobnicate", input: nil) == "Using Frobnicate")
    }

    @Test func longCommandsAreTruncated() {
        let s = AgentHooks.describeTool("Bash", input: ["command": String(repeating: "x", count: 200)])
        #expect(s.count <= "Running ".count + 44)
        #expect(s.hasSuffix("…"))
    }

    @Test func codexNotify() throws {
        let s = spec(try map("codex", #"{"type":"agent-turn-complete","turn-id":"T123","last-assistant-message":"All tests pass.","cwd":"/x/api"}"#))!
        #expect(s.id == "codex-t123")
        #expect(s.state == .success)
        #expect(s.subtitle == "All tests pass.")
        #expect(s.title == "Codex · api")
        #expect(try map("codex", #"{"type":"something-else"}"#) == .ignore)
    }

    @Test func genericAgents() throws {
        let run = spec(try map("aider", #"{"event":"start","session":"s1","message":"Refactoring"}"#))!
        #expect(run.id == "aider-s1")
        #expect(run.state == .running)
        let err = spec(try map("x", #"{"agent":"Gemini CLI","event":"error","session":"s1"}"#))!
        #expect(err.id == "geminicli-s1")
        #expect(err.state == .failure)
        #expect(try map("aider", #"{"event":"end","session":"s1"}"#) == .remove(id: "aider-s1"))
        #expect(try map("aider", #"{"event":"weird"}"#) == .ignore)
    }

    @Test func rejectsNonObjects() {
        #expect(throws: (any Error).self) { try map("claude", "[1,2]") }
        #expect(throws: (any Error).self) { try map("claude", "not json") }
    }

    @Test func mappedSpecsAreAcceptedByTheCenter() throws {
        var c = ActivityCenter()
        let events = ["SessionStart", "UserPromptSubmit", "PreToolUse", "Notification", "PreCompact", "Stop"]
        for e in events {
            let r = try map("claude", "{\"session_id\":\"abc\",\"hook_event_name\":\"\(e)\"}")
            if case .upsert(let s) = r { try c.apply(s, now: t0) }
        }
        let a = c.activities["claude-abc"]!
        #expect(a.state == .success)
        #expect(a.trailing == "Done")
    }
}

@Suite struct URLCommandTests {
    func parse(_ s: String) throws -> URLCommand { try URLCommand.parse(URL(string: s)!) }

    @Test func notify() throws {
        guard case .activity(let s) = try parse("islet://notify?title=Build%20done&icon=sf:hammer&tint=green&ttl=5") else {
            Issue.record("expected activity"); return
        }
        #expect(s.title == "Build done")
        #expect(s.icon == .symbol("hammer"))
        #expect(s.ttl == 5)
        #expect(s.sneak == true)
        #expect(throws: URLCommand.ParseError.missing("title")) { try parse("islet://notify") }
    }

    @Test func activity() throws {
        guard case .activity(let s) = try parse("islet://activity?id=deploy&title=Deploying&progress=0.4&state=running&priority=high") else {
            Issue.record("expected activity"); return
        }
        #expect(s.id == "url-deploy")
        #expect(s.progress == 0.4)
        #expect(s.state == .running)
        #expect(s.priority == .high)
        #expect(throws: URLCommand.ParseError.invalid("state", "bogus")) { try parse("islet://activity?id=x&state=bogus") }
        #expect(throws: URLCommand.ParseError.invalid("progress", "abc")) { try parse("islet://activity?id=x&progress=abc") }
    }

    @Test func activityExtras() throws {
        let u = "islet://activity?id=pizza&title=Pizza&endsIn=1200&url=https://example.com/o/1&actionTitle=Track&actionURL=https://example.com/t&steps=4&step=2"
        guard case .activity(let s) = try parse(u) else { Issue.record("expected activity"); return }
        #expect(abs((s.endsAt?.timeIntervalSinceNow ?? 0) - 1200) < 5)
        #expect(s.url == URL(string: "https://example.com/o/1"))
        #expect(s.actions == [ActivityAction(title: "Track", url: URL(string: "https://example.com/t"))])
        #expect(s.steps == 4 && s.step == 2)
        #expect(throws: URLCommand.ParseError.invalid("url", "nope")) { try parse("islet://activity?id=x&url=nope") }
    }

    @Test func urlSchemeCantImpersonateOrLaunch() throws {
        // Its own id namespace: a link can't replace Islet's battery warning.
        guard case .activity(let s) = try parse("islet://activity?id=battery-low&title=x&priority=critical") else {
            Issue.record("expected activity"); return
        }
        #expect(s.id == "url-battery-low")
        #expect(s.priority == .high)
        #expect(try parse("islet://dismiss?id=battery-low") == .dismiss(id: "url-battery-low"))
        // Only https links, and no file or remote icons.
        #expect(throws: URLCommand.ParseError.self) { try parse("islet://activity?id=x&url=file:///Applications/Calculator.app") }
        #expect(throws: URLCommand.ParseError.self) { try parse("islet://activity?id=x&url=http://example.com") }
        #expect(throws: URLCommand.ParseError.self) { try parse("islet://activity?id=x&actionTitle=Go&actionURL=shortcuts://run-shortcut?name=x") }
        guard case .activity(let n) = try parse("islet://notify?title=Hi&icon=file:/tmp/huge.png") else { return }
        #expect(n.icon == .symbol("bell.fill"))
    }

    @Test func urlSchemeCantReachMirroredLiveActivities() throws {
        // A mirrored activity's id gets the url- prefix like any other, so it's never touched.
        guard case .activity(let s) = try parse("islet://activity?id=live-abc123&title=x") else {
            Issue.record("expected activity"); return
        }
        #expect(s.id == "url-live-abc123")
        #expect(try parse("islet://dismiss?id=live-abc123") == .dismiss(id: "url-live-abc123"))
        #expect(try parse("islet://remove?id=live-abc123") == .dismiss(id: "url-live-abc123"))
        // Nor can a link pass itself off as one.
        #expect(throws: URLCommand.ParseError.invalid("source", "live-activity")) { try parse("islet://activity?id=x&title=x&source=live-activity") }
        #expect(throws: URLCommand.ParseError.invalid("source", "live-activity")) { try parse("islet://notify?title=x&source=live-activity") }
    }

    @Test func misc() throws {
        #expect(try parse("islet://dismiss?id=deploy") == .dismiss(id: "url-deploy"))
        #expect(try parse("islet://timer?minutes=5&title=Tea") == .timer(seconds: 300, title: "Tea"))
        #expect(try parse("islet://timer?seconds=90") == .timer(seconds: 90, title: nil))
        #expect(throws: URLCommand.ParseError.self) { try parse("islet://timer?seconds=-1") }
        #expect(try parse("islet://hud?kind=volume&value=1.5") == .hud(.volume, 1))
        #expect(try parse("islet://media/next") == .media(.next))
        #expect(try parse("islet://media/playpause") == .media(.togglePlayPause))
        #expect(try parse("islet://media?command=previous") == .media(.previous))
        #expect(try parse("islet://open") == .open)
        #expect(try parse("islet://toggle") == .toggle)
        #expect(try parse("islet://settings") == .settings)
        #expect(throws: URLCommand.ParseError.unknownCommand("launch-missiles")) { try parse("islet://launch-missiles") }
        #expect(throws: URLCommand.ParseError.wrongScheme("https")) { try parse("https://example.com") }
    }
}

@Suite struct ScriptPluginTests {
    @Test func xbarOutput() {
        let out = """
        🟢 3 PRs | color=green sfimage=arrow.triangle.pull
        ---
        Fix login bug | href=https://github.com/o/r/pull/1
        --Details | shell=/usr/bin/open param1=-a param2="Visual Studio Code" terminal=false
        ---
        Refresh | refresh=true
        """
        guard case .text(let header, let items) = ScriptPlugins.parse(out) else { Issue.record("expected text"); return }
        #expect(header.count == 1)
        #expect(header[0].text == "🟢 3 PRs")
        #expect(header[0].color == "green")
        #expect(header[0].sfSymbol == "arrow.triangle.pull")
        #expect(items.count == 4)
        #expect(items[0].href == URL(string: "https://github.com/o/r/pull/1"))
        #expect(items[1].depth == 1)
        #expect(items[1].shellCommand == ["/usr/bin/open", "-a", "Visual Studio Code"])
        #expect(items[2].text == "---")
        #expect(items[3].refreshOnClick)
    }

    @Test func linkAndCommandOnOneLineRunsNoCommand() {
        // An unquoted link from outside data could add its own shell= parameter.
        let line = ScriptPlugins.parseLine("Post | href=https://example.com/a shell=/bin/rm param1=-rf")
        #expect(line.href != nil)
        #expect(line.shellCommand == nil)
    }

    @Test func pipeWithoutParamsStaysInText() {
        #expect(ScriptPlugins.parseLine("a | b").text == "a | b")
        #expect(ScriptPlugins.parseLine("plain").params.isEmpty)
        #expect(ScriptPlugins.parseLine("x | key='single quoted' other=1").params == ["key": "single quoted", "other": "1"])
        #expect(ScriptPlugins.parseLine(#"x | k="esc \" quote""#).params["k"] == "esc \" quote")
    }

    @Test func jsonOutputBecomesActivity() {
        let out = #"{"id":"cpu","title":"CPU 42%","progress":0.42}"#
        guard case .activity(let s) = ScriptPlugins.parse(out) else { Issue.record("expected activity"); return }
        #expect(s.id == "cpu")
        #expect(s.progress == 0.42)
        #expect(ScriptPlugins.parse("   \n") == .empty)
    }

    @Test func intervalsFromFileNames() {
        #expect(ScriptPlugins.interval(fromFileName: "cpu.10s.sh") == 10)
        #expect(ScriptPlugins.interval(fromFileName: "weather.30m.py") == 1800)
        #expect(ScriptPlugins.interval(fromFileName: "x.1h.rb") == 3600)
        #expect(ScriptPlugins.interval(fromFileName: "x.1d.rb") == 86400)
        #expect(ScriptPlugins.interval(fromFileName: "fast.100ms.sh") == 1)
        #expect(ScriptPlugins.interval(fromFileName: "noint.sh") == nil)
        #expect(ScriptPlugins.interval(fromFileName: "bad.xyz.sh") == nil)
        #expect(ScriptPlugins.displayName(fromFileName: "github-prs.5m.py") == "github-prs")
    }
}

@Suite struct SettingsTests {
    @Test func defaultsRoundTrip() throws {
        let s = IsletSettings()
        let data = try JSONEncoder().encode(s)
        #expect(try JSONDecoder().decode(IsletSettings.self, from: data) == s)
    }

    @Test func lenientDecoding() throws {
        let json = #"{"hoverToOpen": false, "apiPort": "not a number", "expandedWidth": 99999, "unknownKey": 1, "disabledMediaSources": ["browser"], "theme": "neon", "sizePreset": "large", "appRules": [{"bundleID": "us.zoom.xos", "tint": "blue", "showInFullscreen": true}]}"#
        let s = IsletSettings.decodeLenient(Data(json.utf8))
        #expect(s.hoverToOpen == false)
        #expect(s.apiPort == IsletSettings().apiPort)
        #expect(s.expandedWidth == 1200)
        #expect(s.disabledMediaSources == [.browser])
        #expect(s.clipboardEnabled == false)
        #expect(s.theme == .black)          // unknown enum value falls back
        #expect(s.sizePreset == .large)
        #expect(s.expandedSize.width == 660)
        #expect(s.rule(for: "us.zoom.xos")?.showInFullscreen == true)
        #expect(IsletSettings.decodeLenient(Data("not json".utf8)) == IsletSettings())
    }

    @Test func customSizeUsesExplicitValues() {
        var s = IsletSettings()
        #expect(s.expandedSize.width == 468)       // compact by default
        s.sizePreset = .custom
        s.expandedWidth = 720
        s.wingWidth = 100
        #expect(s.expandedSize.width == 720)
        #expect(s.effectiveWingWidth == 100)
    }

    @Test func sanitizeFixesPortsAndAccent() {
        var s = IsletSettings()
        s.lanPort = s.apiPort
        s.accentColor = "nonsense"
        let fixed = s.sanitized()
        #expect(fixed.lanPort != fixed.apiPort)
        #expect(fixed.accentColor == "auto")
    }

    @Test func saveAndLoad() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("islet-test-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("config.json")
        #expect(IsletSettings.load(from: url) == IsletSettings())
        var s = IsletSettings()
        s.displayMode = .allScreens
        s.mutedSources = ["ci"]
        try s.save(to: url)
        #expect(IsletSettings.load(from: url) == s)
        try Data("garbage".utf8).write(to: url)
        #expect(IsletSettings.load(from: url) == IsletSettings())
    }

    @Test func tokenLooksRandom() {
        let a = APIDiscovery.generateToken(), b = APIDiscovery.generateToken()
        #expect(a.count == 48)
        #expect(a != b)
    }
}
