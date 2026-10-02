import Foundation
import IsletCore

let usage = """
isletctl — control the Islet notch app from scripts, hooks and CI.

USAGE
  isletctl notify <title> [--subtitle S] [--icon sf:NAME|emoji:X] [--tint COLOR] [--ttl SECONDS]
  isletctl set <id> [--title T] [--subtitle S] [--progress 0-1|0-100] [--state STATE]
                    [--trailing TEXT] [--icon ICON] [--tint COLOR] [--priority P] [--ttl SECONDS]
                    [--steps N --step K] [--url URL] [--relevance 0-100] [--stale-in SECONDS]
                    [--ends-in SECONDS] [--started-ago SECONDS] [--action "Title=URL"]
                    [--template NAME] [--json FILE|-]   (a full activity; flags win)
  isletctl rm <id>                     remove an activity
  isletctl clear --source NAME         remove all activities from a source
  isletctl ls                          list activities (JSON)
  isletctl timer <5m|90s|1h 30m|"tea 4m"|"at 18:30"> [--title T] [--id ID]
                                       a bare number is seconds; prints the new timer's id
  isletctl timer ls                    list timers (JSON)
  isletctl timer pause|resume|stop|restart|snooze [ID]   no ID: the ringing or newest timer
  isletctl timer add [ID] <1m>         add time to a timer
  isletctl pomodoro start|stop|toggle  25 min focus, 5 min break, long break every 4th
  isletctl run [--title T] -- <command…>   show a command's progress and result in the notch
  isletctl hud <volume|brightness|keyboardBrightness> <0-1>
  isletctl media <play|pause|playpause|next|previous|forward|rewind|shuffle|repeat>
  isletctl media seek <90s|2m|1:30|0>  jump to a place in the track (0: the start)
  isletctl awake [15m|1h|2h|on|off|status]   keep the Mac awake (default: until turned off)
  isletctl focus <name> [on|off]       show a Focus change (for Shortcuts automations)
  isletctl open | close                expand or collapse the island
  isletctl hook <claude|codex|AGENT> [JSON]   forward an agent hook payload (stdin or last arg)
  isletctl statusline [-- <command…>]  Claude Code status line: record plan usage, run your own line
               [--wait SECONDS]              for approvals: wait for an answer in the notch, print it
  isletctl state | health | token
  isletctl token --lan                 the iPhone bridge's token (not the local API's)
  isletctl debug menubar [--watch]      what Islet sees in the menu bar (--watch: print each change)
  isletctl mcp                         run as an MCP server on stdio (for Claude Code, Codex, Cursor…)

STATES     info running success warning failure waiting
TEMPLATES  eta stages flight route score timer workout gauge live-audio media agent progress
PRIORITIES low normal high critical
Reads the port and token from ~/Library/Application Support/Islet/api.json.
Env overrides: ISLET_PORT, ISLET_TOKEN.
"""

struct CLIError: Error, CustomStringConvertible {
    var description: String
    init(_ d: String) { description = d }
}

struct Client {
    let port: Int
    let token: String

    static func discover() throws -> Client {
        let env = ProcessInfo.processInfo.environment
        var port = env["ISLET_PORT"].flatMap(Int.init)
        var token = env["ISLET_TOKEN"]
        if port == nil || token == nil {
            if let data = try? Data(contentsOf: IsletPaths.apiDiscoveryFile),
               let d = try? JSONDecoder().decode(APIDiscovery.self, from: data) {
                port = port ?? d.port
                token = token ?? d.token
            }
        }
        guard let port, let token else {
            throw CLIError("Islet does not seem to be running (no \(IsletPaths.apiDiscoveryFile.path)). Start Islet.app first.")
        }
        return Client(port: port, token: token)
    }

    /// Islet is on this Mac: no proxy (a system proxy could catch 127.0.0.1), no cookies, no cache.
    static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.connectionProxyDictionary = [:]
        config.httpCookieStorage = nil
        config.urlCache = nil
        return URLSession(configuration: config)
    }()

    func send(_ method: String, _ path: String, json: Data? = nil, timeout: TimeInterval = 3) async throws -> (Int, Data) {
        var req = URLRequest(url: URL(string: "http://127.0.0.1:\(port)\(path)")!)
        req.httpMethod = method
        req.timeoutInterval = timeout
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        if let json {
            req.httpBody = json
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        let (data, resp) = try await Self.session.data(for: req)
        return ((resp as? HTTPURLResponse)?.statusCode ?? 0, data)
    }

    func send<T: Encodable>(_ method: String, _ path: String, body: T, timeout: TimeInterval = 3) async throws -> (Int, Data) {
        try await send(method, path, json: try APIJSON.encoder.encode(body), timeout: timeout)
    }
}

/// Parses `--flag value` pairs and positional arguments.
struct Args {
    /// Flags that take no value.
    static let switches: Set<String> = ["watch", "lan"]

    var positional: [String] = []
    var flags: [String: String] = [:]
    var trailing: [String] = []

    init(_ argv: ArraySlice<String>) throws {
        var it = argv.makeIterator()
        while let a = it.next() {
            if a == "--" {
                while let rest = it.next() { trailing.append(rest) }
                break
            }
            if a.hasPrefix("--") {
                let name = String(a.dropFirst(2))
                if let eq = name.firstIndex(of: "=") {
                    flags[String(name[..<eq])] = String(name[name.index(after: eq)...])
                } else if Self.switches.contains(name) {
                    flags[name] = "true"
                } else {
                    guard let v = it.next() else { throw CLIError("--\(name) needs a value") }
                    flags[name] = v
                }
            } else {
                positional.append(a)
            }
        }
    }

    func double(_ name: String) throws -> Double? {
        guard let raw = flags[name] else { return nil }
        guard let v = Double(raw) else { throw CLIError("--\(name) must be a number, got '\(raw)'") }
        return v
    }
}

/// "5m", "1h 30m", "tea 4m", "in 20 minutes to check the oven", "at 18:30". A bare number is
/// seconds, as it always was for `isletctl timer 300`.
func parseDuration(_ s: String) throws -> DurationParser.Result {
    do {
        return try DurationParser.parse(s, bareNumberUnit: 1)
    } catch {
        throw CLIError(String(describing: error))
    }
}

func timerCommand(_ a: Args) async throws -> Int32 {
    let words = a.positional
    let sub = words.first?.lowercased() ?? ""
    func control(_ body: [String: Any], id: String?) async throws {
        // The id can be a title, so a '/' in it must stay inside the one path segment.
        let segment = CharacterSet.urlPathAllowed.subtracting(CharacterSet(charactersIn: "/"))
        let path = id.map { "/v1/timers/\($0.addingPercentEncoding(withAllowedCharacters: segment) ?? $0)" } ?? "/v1/timers"
        try expectOK(try await Client.discover().send("PATCH", path, json: try JSONSerialization.data(withJSONObject: body)))
    }
    switch sub {
    case "ls", "list":
        try expectOK(try await Client.discover().send("GET", "/v1/timers"), print: true)
    case "pause", "resume", "stop", "restart", "snooze", "rm":
        try await control(["action": sub == "rm" ? "stop" : sub], id: words.count > 1 ? words[1] : nil)
    case "add":
        guard words.count == 2 || words.count == 3 else { throw CLIError("usage: isletctl timer add [ID] <duration>") }
        let seconds = try parseDuration(words[words.count - 1]).seconds
        try await control(["action": "add", "seconds": seconds], id: words.count == 3 ? words[1] : nil)
    default:
        guard !words.isEmpty else { throw CLIError("timer needs a duration, e.g. isletctl timer 5m or isletctl timer \"tea 4m\"") }
        let parsed = try parseDuration(words.joined(separator: " "))
        var body: [String: Any] = ["seconds": parsed.seconds]
        body["title"] = a.flags["title"] ?? parsed.title
        body["id"] = a.flags["id"]
        let data = try expectOK(try await Client.discover().send("POST", "/v1/timer", json: try JSONSerialization.data(withJSONObject: body)))
        if let timer = try? APIJSON.decoder.decode(TimerItem.self, from: data) { print(timer.id) }
    }
    return 0
}

func spec(from a: Args, id: String?) throws -> ActivitySpec {
    var s = ActivitySpec(id: id)
    s.title = a.flags["title"]
    s.subtitle = a.flags["subtitle"]
    s.trailing = a.flags["trailing"]
    s.template = a.flags["template"]
    s.tint = a.flags["tint"]
    s.source = a.flags["source"] ?? "cli"
    s.progress = try a.double("progress")
    s.ttl = try a.double("ttl")
    if let i = a.flags["icon"] {
        guard let icon = ActivityIcon(string: i) else { throw CLIError("bad --icon '\(i)'") }
        s.icon = icon
    }
    if let st = a.flags["state"] {
        guard let v = ActivityState(rawValue: st) else { throw CLIError("bad --state '\(st)'") }
        s.state = v
    }
    if let p = a.flags["priority"] {
        s.priority = try APIJSON.decoder.decode(ActivityPriority.self, from: Data("\"\(p)\"".utf8))
    }
    if let sneak = a.flags["sneak"] { s.sneak = sneak == "true" || sneak == "1" }
    if let v = try a.double("steps") { s.steps = Int(v) }
    if let v = try a.double("step") { s.step = Int(v) }
    if let v = try a.double("relevance") { s.relevance = v }
    if let v = try a.double("stale-in") { s.staleAt = Date().addingTimeInterval(v) }
    if let v = try a.double("ends-in") { s.endsAt = Date().addingTimeInterval(v) }
    if let v = try a.double("started-ago") { s.startedAt = Date().addingTimeInterval(-v) }
    if let raw = a.flags["action"] {
        guard let eq = raw.firstIndex(of: "="), let url = URL(string: String(raw[raw.index(after: eq)...])), url.scheme != nil else {
            throw CLIError("--action must look like \"Title=https://…\"")
        }
        s.actions = [ActivityAction(title: String(raw[..<eq]), url: url)]
    }
    if let u = a.flags["url"] {
        guard let url = URL(string: u), url.scheme != nil else { throw CLIError("bad --url '\(u)'") }
        s.url = url
    }
    return s
}

/// The iPhone bridge's own token, read from `lan.json`; Islet needn't be running.
func lanToken() throws -> String {
    let url = IsletPaths.lanTokenFile
    guard FileManager.default.fileExists(atPath: url.path) else {
        throw CLIError("the iPhone bridge has never been turned on, so it has no token yet. Turn it on in Settings → Advanced → iPhone bridge, then run this again.")
    }
    guard let token = LANTokenFile.read(from: url) else { throw CLIError("could not read the iPhone bridge token from \(url.path)") }
    return token
}

@discardableResult
func expectOK(_ result: (Int, Data), print output: Bool = false) throws -> Data {
    let (status, data) = result
    guard (200..<300).contains(status) else {
        let msg = (try? JSONDecoder().decode([String: String].self, from: data))?["error"] ?? String(decoding: data, as: UTF8.self)
        throw CLIError("Islet returned \(status): \(msg)")
    }
    if output, !data.isEmpty { print(String(decoding: data, as: UTF8.self)) }
    return data
}

func run(_ argv: [String]) async throws -> Int32 {
    guard let command = argv.first else {
        print(usage)
        return 0
    }
    let a = try Args(argv.dropFirst())

    switch command {
    case "help", "-h", "--help":
        print(usage)
        return 0

    case "notify":
        guard let title = a.positional.first ?? a.flags["title"] else { throw CLIError("notify needs a title") }
        var body: [String: String] = ["title": title]
        body["subtitle"] = a.flags["subtitle"]
        body["icon"] = a.flags["icon"]
        body["tint"] = a.flags["tint"]
        body["source"] = a.flags["source"]
        var json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(body)) as! [String: Any]
        if let ttl = try a.double("ttl") { json["ttl"] = ttl }
        try expectOK(try await Client.discover().send("POST", "/v1/notify", json: try JSONSerialization.data(withJSONObject: json)))
        return 0

    case "set", "update":
        guard let id = a.positional.first else { throw CLIError("set needs an id") }
        let s = try spec(from: a, id: id)
        let body = try a.flags["json"].map { try mergedSpecJSON(file: $0, flags: s, keepSource: a.flags["source"] != nil) } ?? APIJSON.encoder.encode(s)
        try expectOK(try await Client.discover().send("PUT", "/v1/activities/\(id)", json: body))
        return 0

    case "rm", "remove", "dismiss":
        guard let id = a.positional.first else { throw CLIError("rm needs an id") }
        let enc = id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? id
        try expectOK(try await Client.discover().send("DELETE", "/v1/activities/\(enc)"))
        return 0

    case "clear":
        guard let source = a.flags["source"] else { throw CLIError("clear needs --source NAME") }
        let enc = source.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? source
        try expectOK(try await Client.discover().send("DELETE", "/v1/activities?source=\(enc)"), print: true)
        return 0

    case "ls", "list":
        try expectOK(try await Client.discover().send("GET", "/v1/activities"), print: true)
        return 0

    case "debug":
        guard a.positional.first == "menubar" else { throw CLIError("usage: isletctl debug menubar [--watch]") }
        return try await debugMenuBar(watch: a.flags["watch"] != nil)

    case "state":
        try expectOK(try await Client.discover().send("GET", "/v1/state"), print: true)
        return 0

    case "health":
        let c = try Client.discover()
        try expectOK(try await c.send("GET", "/v1/health"), print: true)
        return 0

    case "token":
        if a.flags["lan"] != nil {
            print(try lanToken())
            return 0
        }
        print(try Client.discover().token)
        return 0

    case "timer", "timers":
        return try await timerCommand(a)

    case "pomodoro":
        let action = a.positional.first?.lowercased() ?? "toggle"
        guard PomodoroAction(rawValue: action) != nil else { throw CLIError("usage: isletctl pomodoro start|stop|toggle") }
        try expectOK(try await Client.discover().send("POST", "/v1/pomodoro", json: Data("{\"action\":\"\(action)\"}".utf8)))
        return 0

    case "hud":
        guard a.positional.count == 2, let v = Double(a.positional[1]) else { throw CLIError("usage: isletctl hud <kind> <0-1>") }
        let body: [String: Any] = ["kind": a.positional[0], "value": v]
        try expectOK(try await Client.discover().send("POST", "/v1/hud", json: try JSONSerialization.data(withJSONObject: body)))
        return 0

    case "media":
        let map = ["play": "play", "pause": "pause", "playpause": "togglePlayPause", "toggle": "togglePlayPause",
                   "next": "next", "previous": "previous", "prev": "previous",
                   "forward": "skipForward", "rewind": "skipBackward", "shuffle": "toggleShuffle", "repeat": "toggleRepeat"]
        if a.positional.first?.lowercased() == "seek" {
            guard a.positional.count >= 2 else { throw CLIError("usage: isletctl media seek <90s|2m|1:30|0>") }
            let typed = a.positional.dropFirst().joined(separator: " ")
            guard let position = MediaSeek.parsePosition(typed) else {
                throw CLIError("can't read '\(typed)' as a place in the track; try 90s, 2m, 1:30 or 0 for the start")
            }
            let body: [String: Any] = ["command": "seek", "position": position]
            try expectOK(try await Client.discover().send("POST", "/v1/media/command", json: try JSONSerialization.data(withJSONObject: body)))
            return 0
        }
        guard let name = a.positional.first, let cmd = map[name.lowercased()] else {
            throw CLIError("usage: isletctl media <play|pause|playpause|next|previous|forward|rewind|shuffle|repeat|seek>")
        }
        try expectOK(try await Client.discover().send("POST", "/v1/media/command", json: Data("{\"command\":\"\(cmd)\"}".utf8)))
        return 0

    case "awake":
        let arg = a.positional.first ?? "on"
        if arg.lowercased() == "status" {
            try expectOK(try await Client.discover().send("GET", "/v1/awake"), print: true)
            return 0
        }
        guard let change = KeepAwake.parse(arg) else {
            throw CLIError("usage: isletctl awake [15m|1h|2h|on|off|status] (up to 24h)")
        }
        let client = try Client.discover()
        switch change {
        case .stop:
            try expectOK(try await client.send("DELETE", "/v1/awake"), print: true)
        case .start(let minutes):
            let body: [String: Any] = ["minutes": minutes ?? 0]
            try expectOK(try await client.send("POST", "/v1/awake", json: try JSONSerialization.data(withJSONObject: body)), print: true)
        }
        return 0

    case "focus":
        guard let name = a.positional.first else { throw CLIError("usage: isletctl focus <name> [on|off]") }
        let on = (a.positional.count > 1 ? a.positional[1] : "on").lowercased() != "off"
        let body: [String: Any] = ["name": name, "on": on]
        try expectOK(try await Client.discover().send("POST", "/v1/focus", json: try JSONSerialization.data(withJSONObject: body)))
        return 0

    case "open", "close":
        try expectOK(try await Client.discover().send("POST", "/v1/island/\(command)"))
        return 0

    case "hook":
        // Hooks must never break the agent that calls them: always exit 0, fail fast.
        guard let provider = a.positional.first else { throw CLIError("hook needs a provider: claude, codex, …") }
        let payload: Data
        if a.positional.count >= 2 {
            payload = Data(a.positional[1].utf8)
        } else {
            payload = FileHandle.standardInput.readDataToEndOfFile()
        }
        await forwardHook(provider: provider, payload: payload, wait: a.flags["wait"].flatMap { Int($0) })
        return 0

    case "run":
        guard !a.trailing.isEmpty else { throw CLIError("usage: isletctl run [--title T] -- <command…>") }
        return try await runWrapped(a)

    case "mcp":
        return await MCPServer.run()

    case "statusline":
        return runStatusLine(a.trailing)

    default:
        throw CLIError("unknown command '\(command)'. Run `isletctl help`.")
    }
}

/// The command `run` is waiting for, so a signal can be passed on to it.
nonisolated(unsafe) var runChildPID: pid_t = 0

/// Run a command, mirroring its lifecycle in the notch. Output passes through untouched.
func runWrapped(_ a: Args) async throws -> Int32 {
    let title = a.flags["title"] ?? a.trailing.joined(separator: " ")
    let id = "run-\(ProcessInfo.processInfo.processIdentifier)"
    let client = try? Client.discover()
    let started = Date()

    func post(_ s: ActivitySpec) async {
        _ = try? await client?.send("PUT", "/v1/activities/\(id)", body: s, timeout: 1.5)
    }

    await post(ActivitySpec(
        id: id, source: "run", title: String(title.prefix(80)), subtitle: "Running…",
        icon: .symbol("terminal.fill"), progress: -1, state: .running, ttl: 0, sneak: false
    ))

    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    p.arguments = a.trailing
    p.standardInput = FileHandle.standardInput
    p.standardOutput = FileHandle.standardOutput
    p.standardError = FileHandle.standardError
    // Ctrl-C or a kill reaches the command, and isletctl stays to report how it ended rather than
    // leaving "Running…" in the notch. (A caught signal reverts to the default in the child.)
    signal(SIGINT) { sig in if runChildPID > 0 { kill(runChildPID, sig) } }
    signal(SIGTERM) { sig in if runChildPID > 0 { kill(runChildPID, sig) } }
    try p.run()
    runChildPID = p.processIdentifier
    p.waitUntilExit()
    runChildPID = 0

    let elapsed = Format.clock(Date().timeIntervalSince(started))
    if p.terminationReason == .uncaughtSignal {
        await post(ActivitySpec(
            id: id, source: "run", title: String(title.prefix(80)), subtitle: "Cancelled after \(elapsed)",
            icon: .symbol("stop.circle.fill"), trailing: "Stopped", progress: 1, state: .warning,
            priority: .normal, ttl: 15, sneak: false
        ))
        return 128 + p.terminationStatus
    }
    let ok = p.terminationStatus == 0
    await post(ActivitySpec(
        id: id, source: "run", title: String(title.prefix(80)),
        subtitle: ok ? "Finished in \(elapsed)" : "Failed (exit \(p.terminationStatus)) after \(elapsed)",
        icon: .symbol(ok ? "checkmark.circle.fill" : "xmark.octagon.fill"),
        trailing: ok ? "Done" : "Failed", progress: 1, state: ok ? .success : .failure,
        priority: ok ? .normal : .high, ttl: ok ? 15 : 60, sneak: true
    ))
    return p.terminationStatus
}

do {
    let code = try await run(Array(CommandLine.arguments.dropFirst()))
    exit(code)
} catch {
    FileHandle.standardError.write(Data("isletctl: \(error)\n".utf8))
    exit(1)
}
