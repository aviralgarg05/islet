import Foundation
import CasementCore

/// `casementctl mcp`: a Model Context Protocol server over stdio, so coding agents and chat apps
/// (Claude Code, Claude Desktop, Codex, Cursor…) can show progress, notes and timers in the
/// notch as tools, without hooks. It speaks JSON-RPC 2.0, one message per line, and forwards
/// each tool call to the running app's local API.
enum MCPServer {
    static let supportedVersions = ["2025-06-18", "2025-03-26", "2024-11-05"]

    struct Tool {
        let name: String
        let description: String
        let schema: [String: Any]
    }

    static func object(_ properties: [String: [String: Any]], required: [String] = []) -> [String: Any] {
        ["type": "object", "properties": properties, "required": required, "additionalProperties": false]
    }

    static var tools: [Tool] { [
        Tool(name: "notify",
             description: "Show a short message in the Mac's notch for a few seconds. Use for something the user should notice now, such as a finished task.",
             schema: object([
                "title": ["type": "string", "description": "A few words."],
                "subtitle": ["type": "string", "description": "Optional second line."],
                "icon": ["type": "string", "description": "SF Symbol name, e.g. checkmark.circle.fill."],
                "seconds": ["type": "number", "description": "How long it stays (default 6)."],
             ], required: ["title"])),
        Tool(name: "show_progress",
             description: "Create or update a live activity in the notch that shows progress on a longer task. Call again with the same id to update it, and call finish when done.",
             schema: object([
                "id": ["type": "string", "description": "Stable id for this task, e.g. migrate-db."],
                "title": ["type": "string", "description": "What is being done."],
                "subtitle": ["type": "string", "description": "The current step, in a few words."],
                "progress": ["type": "number", "description": "0 to 1; omit for an indeterminate spinner."],
                "step": ["type": "integer", "description": "Current step, 1-based, with steps."],
                "steps": ["type": "integer", "description": "Total number of steps."],
             ], required: ["id", "title"])),
        Tool(name: "finish",
             description: "Mark a task started with show_progress as done or failed. It stays briefly, then goes away.",
             schema: object([
                "id": ["type": "string"],
                "success": ["type": "boolean"],
                "subtitle": ["type": "string", "description": "Outcome in a few words."],
             ], required: ["id", "success"])),
        Tool(name: "dismiss",
             description: "Remove an activity from the notch.",
             schema: object(["id": ["type": "string"]], required: ["id"])),
        Tool(name: "start_timer",
             description: "Start a countdown in the notch, e.g. to remind the user to check something later.",
             schema: object([
                "duration": ["type": "string", "description": "Like 90s, 5m, 1h 30m or 'half an hour'."],
                "title": ["type": "string"],
             ], required: ["duration"])),
        Tool(name: "list_activities",
             description: "List what the notch is showing right now (ids, titles, states).",
             schema: object([:])),
    ] }

    /// Activities made through MCP get their own id prefix, so a tool can't replace Casement's own.
    /// An id copied from list_activities already has it and is used as it is.
    static func activityID(_ raw: String) -> String {
        ActivityCenter.namespacedID(raw, prefix: "mcp-")
    }

    static func run() async -> Int32 {
        let out = FileHandle.standardOutput
        func send(_ message: [String: Any]) {
            guard var data = try? JSONSerialization.data(withJSONObject: message, options: [.withoutEscapingSlashes]) else { return }
            data.append(0x0A)
            out.write(data)
        }
        while let line = readLine(strippingNewline: true) {
            guard !line.isEmpty,
                  let data = line.data(using: .utf8),
                  let msg = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                send(["jsonrpc": "2.0", "id": NSNull(), "error": ["code": -32700, "message": "Parse error"]])
                continue
            }
            let method = msg["method"] as? String ?? ""
            guard let id = msg["id"] else { continue } // a notification: nothing to answer
            let params = msg["params"] as? [String: Any] ?? [:]
            switch method {
            case "initialize":
                let asked = params["protocolVersion"] as? String ?? ""
                send(["jsonrpc": "2.0", "id": id, "result": [
                    "protocolVersion": supportedVersions.contains(asked) ? asked : supportedVersions[0],
                    "capabilities": ["tools": ["listChanged": false]],
                    "serverInfo": ["name": "casement", "version": "1"],
                    "instructions": "Shows progress, short notes and timers in the Mac's notch. Keep titles to a few words.",
                ]])
            case "ping":
                send(["jsonrpc": "2.0", "id": id, "result": [String: Any]()])
            case "tools/list":
                let list = tools.map { ["name": $0.name, "description": $0.description, "inputSchema": $0.schema] }
                send(["jsonrpc": "2.0", "id": id, "result": ["tools": list]])
            case "tools/call":
                let name = params["name"] as? String ?? ""
                let args = params["arguments"] as? [String: Any] ?? [:]
                let (text, isError) = await call(name, args)
                send(["jsonrpc": "2.0", "id": id, "result": ["content": [["type": "text", "text": text]], "isError": isError]])
            default:
                send(["jsonrpc": "2.0", "id": id, "error": ["code": -32601, "message": "Method not found: \(method)"]])
            }
        }
        return 0
    }

    /// Run one tool. Returns the text for the model and whether it failed.
    static func call(_ name: String, _ a: [String: Any]) async -> (String, Bool) {
        let client: Client
        do {
            client = try Client.discover()
        } catch {
            return ("Casement isn't running on this Mac, so nothing was shown.", true)
        }
        func string(_ key: String) -> String? { (a[key] as? String).flatMap { $0.isEmpty ? nil : String($0.prefix(200)) } }
        /// Bounded the way a link's numbers are. An agent does send `1e300` or `inf`, and an
        /// unchecked one reaching `Int(_:)` traps, which would end this server mid-session.
        func number(_ key: String) -> Double? {
            guard let v = (a[key] as? NSNumber)?.doubleValue, v.isFinite,
                  abs(v) <= URLCommand.numberLimit else { return nil }
            return v
        }
        do {
            switch name {
            case "notify":
                guard let title = string("title") else { return ("'title' is required.", true) }
                var spec = ActivitySpec(source: "mcp", title: title, subtitle: string("subtitle"),
                                        icon: string("icon").map { .symbol($0) } ?? .symbol("bell.fill"),
                                        state: .info, priority: .normal, ttl: min(60, max(1, number("seconds") ?? 6)), sneak: true)
                spec.id = activityID("note-\(Int(Date().timeIntervalSince1970 * 1000))")
                try expectOK(try await client.send("PUT", "/v1/activities/\(spec.id!)", body: spec))
                return ("Shown in the notch.", false)
            case "show_progress":
                guard let raw = string("id"), let title = string("title") else { return ("'id' and 'title' are required.", true) }
                let id = activityID(raw)
                var spec = ActivitySpec(id: id, source: "mcp", title: title, subtitle: string("subtitle"),
                                        icon: .symbol("gearshape.2.fill"), state: .running, ttl: 0, sneak: false)
                if let p = number("progress") { spec.progress = min(1, max(0, p)) } else if a["steps"] == nil { spec.progress = -1 }
                if let n = number("steps") { spec.steps = Int(n) }
                if let n = number("step") { spec.step = Int(n) }
                // Forgotten tasks dim after 15 minutes without an update.
                spec.staleAt = Date().addingTimeInterval(15 * 60)
                try expectOK(try await client.send("PUT", "/v1/activities/\(id)", body: spec))
                return ("Showing \(id).", false)
            case "finish":
                guard let raw = string("id"), let ok = a["success"] as? Bool else { return ("'id' and 'success' are required.", true) }
                let id = activityID(raw)
                let spec = ActivitySpec(id: id, subtitle: string("subtitle") ?? (ok ? "Done" : "Failed"),
                                        icon: .symbol(ok ? "checkmark.circle.fill" : "xmark.octagon.fill"),
                                        trailing: ok ? "Done" : "Failed", progress: 1, state: ok ? .success : .failure,
                                        ttl: ok ? 12 : 60, sneak: true)
                let (status, _) = try await client.send("PUT", "/v1/activities/\(id)", body: spec)
                if status == 422 { return ("No task with id \(raw) is showing.", true) }
                return ("Marked \(raw) as \(ok ? "done" : "failed").", false)
            case "dismiss":
                guard let raw = string("id") else { return ("'id' is required.", true) }
                let (status, _) = try await client.send("DELETE", "/v1/activities/\(activityID(raw))")
                return status == 404 ? ("Nothing with id \(raw) is showing.", false) : ("Removed.", false)
            case "start_timer":
                guard let raw = string("duration") else { return ("'duration' is required.", true) }
                var body: [String: Any] = ["in": raw]
                body["title"] = string("title")
                let (status, _) = try await client.send("POST", "/v1/timer", json: try JSONSerialization.data(withJSONObject: body))
                if status == 422 { return ("Couldn't read '\(raw)' as a duration; try 90s, 5m or 1h.", true) }
                return (200..<300).contains(status) ? ("Timer started.", false) : ("Casement refused it (\(status)).", true)
            case "list_activities":
                let data = try expectOK(try await client.send("GET", "/v1/activities"))
                let list = (try? APIJSON.decoder.decode([Activity].self, from: data)) ?? []
                if list.isEmpty { return ("The notch is showing nothing.", false) }
                return (list.map { "\($0.id): \($0.title) (\($0.state.rawValue))" }.joined(separator: "\n"), false)
            default:
                return ("Unknown tool \(name).", true)
            }
        } catch let e as URLError where [.cannotConnectToHost, .timedOut, .networkConnectionLost].contains(e.code) {
            return ("Casement isn't running on this Mac, so nothing was shown.", true)
        } catch {
            return ("Casement refused it: \(error)", true)
        }
    }
}
