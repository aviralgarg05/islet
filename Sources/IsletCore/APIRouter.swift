import Foundation

/// What the app exposes to the local API. The app implements this on the main actor;
/// tests implement it with an in-memory fake.
public protocol IsletBackend: Sendable {
    func listActivities() async -> [Activity]
    func applyActivity(_ spec: ActivitySpec) async throws -> Activity
    func removeActivity(id: String) async -> Bool
    func removeActivities(source: String) async -> Int
    func showHUD(kind: HUDKind, value: Double, muted: Bool, label: String?) async
    func pushMedia(_ media: NowPlaying?) async
    func mediaCommand(_ command: PlaybackCommand, position: Double?) async -> Bool
    func setExpanded(_ expanded: Bool) async
    func stateSnapshot() async -> StateSnapshot
    /// What MenuBarAgent exposes right now (diagnostics for Live Activity mirroring).
    func menuBarItems() async -> [MenuBarItemInfo]
    /// Start or stop keep awake (nil only reads the state).
    func keepAwake(_ change: KeepAwakeChange?) async -> KeepAwakeStatus
    /// Timers and the Pomodoro, ringing first, then by end time.
    func listTimers() async -> [TimerItem]
    /// Runs a timer command; returns the timer it started or changed, nil when it stopped one.
    func timerCommand(_ command: TimerCommand) async throws -> TimerItem?
    /// Coding-agent approvals: `.ask` shows a card and returns the user's answer (nil: no
    /// decision); it must return promptly once its task is cancelled. `.settle` returns nil.
    func handleApproval(_ event: ApprovalEvent) async -> ApprovalDecision?
    /// Whether scripts may read Live Activities mirrored from the menu bar (the
    /// `shareMirroredActivities` setting). The router leaves them out otherwise.
    func sharesMirroredActivities() async -> Bool
}

extension IsletBackend {
    public func sharesMirroredActivities() async -> Bool { false }
}

public struct StateSnapshot: Codable, Equatable, Sendable {
    public var version: String
    public var presentation: String
    public var activities: [Activity]
    public var nowPlaying: NowPlayingSummary?
    public var battery: BatteryState?
    /// Calendar and reminders access, and how many events are left today; never a title.
    public var calendar: CalendarStatus?

    public init(version: String, presentation: String, activities: [Activity], nowPlaying: NowPlayingSummary?, battery: BatteryState?,
                calendar: CalendarStatus? = nil) {
        self.version = version; self.presentation = presentation; self.activities = activities
        self.nowPlaying = nowPlaying; self.battery = battery; self.calendar = calendar
    }
}

/// Now playing without the artwork bytes (keeps API responses small).
public struct NowPlayingSummary: Codable, Equatable, Sendable {
    public var source: MediaSourceKind
    public var bundleID: String?
    public var title: String
    public var artist: String?
    public var album: String?
    public var isPlaying: Bool
    public var duration: Double?
    public var position: Double?

    public init(_ np: NowPlaying, now: Date) {
        source = np.source; bundleID = np.bundleID; title = np.title; artist = np.artist
        album = np.album; isPlaying = np.isPlaying; duration = np.duration; position = np.position(at: now)
    }
}

/// Body of `POST /v1/media`: lets browser extensions, players and scripts report playback.
public struct MediaPush: Codable, Sendable {
    public var title: String
    public var artist: String?
    public var album: String?
    public var isPlaying: Bool?
    public var duration: Double?
    public var elapsed: Double?
    public var bundleID: String?
    public var appName: String?
    public var artworkURL: URL?
}

struct HUDPush: Codable {
    var kind: HUDKind
    var value: Double
    var muted: Bool?
    var label: String?
}

struct NotifyPush: Codable {
    var title: String
    var subtitle: String?
    var icon: ActivityIcon?
    var tint: String?
    var ttl: Double?
    var priority: ActivityPriority?
    var source: String?
}

struct TimerPush: Codable {
    var seconds: Double?
    /// "20m", "tea 4m", "in 20 minutes to take the pizza out", "at 18:30".
    var inText: String?
    var title: String?
    var id: String?

    enum CodingKeys: String, CodingKey {
        case seconds, inText = "in", title, id
    }
}

struct TimerControlPush: Codable {
    var action: TimerAction
    var seconds: Double?
    var inText: String?

    enum CodingKeys: String, CodingKey {
        case action, seconds, inText = "in"
    }
}

struct PomodoroPush: Codable {
    var action: PomodoroAction
}

struct FocusPush: Codable {
    var name: String?
    var on: Bool?
}

struct CommandPush: Codable {
    var command: PlaybackCommand
    var position: Double?
}

struct AwakePush: Codable {
    /// Omitted or 0 = until turned off.
    var minutes: Double?
}

/// Authenticates and routes local API requests.
public struct APIRouter: Sendable {
    public let token: String
    public let version: String
    public let backend: any IsletBackend
    public let clock: @Sendable () -> Date
    /// Which listener this router serves; `.lan` narrows the routes (APIRouter+LAN.swift).
    public let scope: APIScope
    /// Serving the local network (iPhone Shortcuts): any Host header is accepted, but the
    /// token is still required and browser origins are still refused.
    public var allowRemoteHosts: Bool { scope == .lan }

    public init(token: String, version: String, backend: any IsletBackend, scope: APIScope = .local,
                clock: @escaping @Sendable () -> Date = { Date() }) {
        self.token = token
        self.version = version
        self.backend = backend
        self.scope = scope
        self.clock = clock
    }

    /// `allowRemoteHosts: true` is the local-network scope.
    public init(token: String, version: String, backend: any IsletBackend, allowRemoteHosts: Bool,
                clock: @escaping @Sendable () -> Date = { Date() }) {
        self.init(token: token, version: version, backend: backend, scope: allowRemoteHosts ? .lan : .local, clock: clock)
    }

    /// Constant-time comparison so the token can't be guessed byte by byte from timing.
    static func tokensMatch(_ a: String, _ b: String) -> Bool {
        let x = Array(a.utf8), y = Array(b.utf8)
        guard x.count == y.count else { return false }
        var diff: UInt8 = 0
        for i in 0..<x.count { diff |= x[i] ^ y[i] }
        return diff == 0
    }

    /// Reject requests that come from a web page (CSRF) or through DNS rebinding.
    static func isAllowedOrigin(_ request: HTTPRequest, remote: Bool = false) -> Bool {
        if !remote, let host = request.headers["host"] {
            let name = host.split(separator: ":").first.map(String.init)?.lowercased() ?? ""
            guard ["127.0.0.1", "localhost", "[::1]", "::1"].contains(name) || host.hasPrefix("[::1]") else { return false }
        }
        guard let origin = request.headers["origin"]?.lowercased() else { return true }
        // Browser extensions are allowed (they still need the token); web pages are not.
        return origin.hasPrefix("chrome-extension://") || origin.hasPrefix("moz-extension://")
            || origin.hasPrefix("safari-web-extension://") || origin == "null"
    }

    func authorized(_ request: HTTPRequest) -> Bool {
        if let auth = request.headers["authorization"], auth.lowercased().hasPrefix("bearer ") {
            return Self.tokensMatch(String(auth.dropFirst(7)).trimmingCharacters(in: .whitespaces), token)
        }
        if let t = request.headers["x-islet-token"] { return Self.tokensMatch(t, token) }
        return false
    }

    func decode<T: Decodable>(_ type: T.Type, from request: HTTPRequest) throws -> T {
        guard !request.body.isEmpty else {
            throw DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "request body is empty"))
        }
        return try APIJSON.decoder.decode(T.self, from: request.body)
    }

    static func describe(_ error: Error) -> String {
        if let e = error as? ActivityError { return e.description }
        if let e = error as? DecodingError {
            switch e {
            case .dataCorrupted(let c): return "invalid JSON: \(c.debugDescription)"
            case .keyNotFound(let k, _): return "missing field '\(k.stringValue)'"
            case .typeMismatch(_, let c), .valueNotFound(_, let c):
                return "wrong type for '\(c.codingPath.map(\.stringValue).joined(separator: "."))': \(c.debugDescription)"
            @unknown default: return "invalid JSON"
            }
        }
        return String(describing: error)
    }

    static func isHealthCheck(_ request: HTTPRequest) -> Bool {
        let seg = request.segments
        return request.method == "GET" && (seg == ["v1", "health"] || seg == ["health"])
    }

    /// What can be decided from the request line and headers alone: the origin, the token and,
    /// on the local network, the route. The server calls this before reading the body.
    /// Returns the refusal, or nil when the request may go on.
    public func preflight(_ request: HTTPRequest) -> HTTPResponse? {
        guard Self.isAllowedOrigin(request, remote: allowRemoteHosts) else { return .error(403, "requests from web pages are not allowed") }
        if Self.isHealthCheck(request) { return nil }
        guard authorized(request) else {
            return scope == .lan
                ? .error(401, "missing or wrong token; send 'Authorization: Bearer <token>' with the token from Settings → Advanced → iPhone bridge")
                : .error(401, "missing or wrong token; send 'Authorization: Bearer <token>' (see `isletctl token`)")
        }
        if scope == .lan, !Self.lanAllows(request) { return .error(403, Self.lanRefusal) }
        return nil
    }

    public func handle(_ request: HTTPRequest) async -> HTTPResponse {
        if let refusal = preflight(request) { return refusal }
        let seg = request.segments
        if Self.isHealthCheck(request) {
            // The bridge answers this without a token and advertises itself over Bonjour, so it
            // says only that Islet is here. The exact version stays on loopback.
            return .json(scope == .lan ? ["ok": "true"] : ["ok": "true", "version": version])
        }
        do {
            return try await route(request, seg)
        } catch ActivityError.mirrored {
            return .error(403, ActivityError.mirrored.description)
        } catch ActivityError.notFound(let id) {
            return .error(404, ActivityError.notFound(id).description)
        } catch {
            return .error(422, Self.describe(error))
        }
    }

    // MARK: Mirrored Live Activities

    /// Every write to an activity goes through here or `remove(id:)`. Mirrored Live Activities
    /// belong to the menu bar mirror, so they are refused, the same way whether or not one exists.
    func apply(_ spec: ActivitySpec) async throws -> Activity {
        if spec.source.map(MenuBarLiveActivities.isMirroredSource) == true || spec.id.map(MenuBarLiveActivities.isMirrored(id:)) == true {
            throw ActivityError.mirrored
        }
        if let id = spec.id, await isMeetingReminder(id) { throw ActivityError.notFound(id) }
        return try await backend.applyActivity(spec)
    }

    func remove(id: String) async throws -> Bool {
        guard !MenuBarLiveActivities.isMirrored(id: id) else { throw ActivityError.mirrored }
        guard !(await isMeetingReminder(id)) else { return false }
        return await backend.removeActivity(id: id)
    }

    /// Whether `id` is a meeting reminder on show. Scripts can't read those (`readable`), so to
    /// a script the id isn't there: it can't change one, learn its title from the answer, or
    /// dismiss it (which would keep it away for good).
    private func isMeetingReminder(_ id: String) async -> Bool {
        // Only ids in the reminders' namespace are looked up, so other writes cost nothing more.
        guard id.hasPrefix(MeetingReminders.idPrefix) else { return false }
        return await backend.listActivities().contains { $0.id == id && MeetingReminders.isReminder($0) }
    }

    /// `DELETE /v1/activities?source=`: everything from one source, except meeting reminders,
    /// which share the source `calendar` with what a script may push. A script clearing its own
    /// `calendar` activities neither dismisses today's meetings nor learns how many are showing.
    func removeAll(source: String) async -> Int {
        guard source == MeetingReminders.source else { return await backend.removeActivities(source: source) }
        var removed = 0
        for a in await backend.listActivities() where a.source == source && !MeetingReminders.isReminder(a) {
            if await backend.removeActivity(id: a.id) { removed += 1 }
        }
        return removed
    }

    /// What scripts may read: what Islet mirrors, from the menu bar and from notification
    /// banners, only when the user shares it, and meeting reminders never (they carry the
    /// meeting's title; `calendar` in the state says how many events are left instead).
    func readable(_ activities: [Activity]) async -> [Activity] {
        let shown = activities.filter { !MeetingReminders.isReminder($0) }
        if await backend.sharesMirroredActivities() { return shown }
        return shown.filter { !MenuBarLiveActivities.isMirrored($0) && !MirroredNotification.isMirrored($0) }
    }

    private func route(_ r: HTTPRequest, _ seg: [String]) async throws -> HTTPResponse {
        guard seg.first == "v1" else { return .error(404, "unknown endpoint; all endpoints live under /v1") }
        let rest = Array(seg.dropFirst())
        let head = rest.first ?? ""
        let sub = rest.count == 2 ? rest[1] : ""
        switch (r.method, rest.count, head) {
        case ("GET", 1, "state"):
            var state = await backend.stateSnapshot()
            state.activities = await readable(state.activities)
            return .json(state)

        case ("GET", 1, "activities"):
            return .json(await readable(await backend.listActivities()))

        case ("POST", 1, "activities"):
            let spec = try decode(ActivitySpec.self, from: r)
            return .json(try await apply(admitted(spec)), status: 201)

        case ("PUT", 2, "activities"), ("PATCH", 2, "activities"), ("POST", 2, "activities"):
            let id = sub
            // Refused before the body is read, so the answer is the same for any body.
            guard !MenuBarLiveActivities.isMirrored(id: id) else { throw ActivityError.mirrored }
            var spec = try decode(ActivitySpec.self, from: r)
            spec.id = id
            return .json(try await apply(admitted(spec)))

        case ("DELETE", 2, "activities"):
            let id = sub
            return try await remove(id: id) ? .noContent : .error(404, ActivityError.notFound(id).description)

        case ("DELETE", 1, "activities"):
            guard let source = r.query["source"], !source.isEmpty else {
                return .error(400, "pass ?source=<name> to remove all activities from one source")
            }
            // The count would also say how many are showing.
            guard !MenuBarLiveActivities.isMirroredSource(source) else { throw ActivityError.mirrored }
            return .json(["removed": await removeAll(source: source)])

        case ("POST", 1, "notify"):
            let n = try decode(NotifyPush.self, from: r)
            let spec = ActivitySpec(
                source: n.source ?? "notify", title: n.title, subtitle: n.subtitle, icon: admitted(n.icon) ?? .symbol("bell.fill"),
                state: .info, tint: n.tint, priority: n.priority ?? .normal, ttl: n.ttl ?? 6, sneak: true
            )
            return .json(try await apply(admitted(spec)), status: 201)

        case ("POST", 1, "timer"), ("POST", 1, "timers"):
            let t = try decode(TimerPush.self, from: r)
            var seconds = t.seconds
            var title = t.title
            if seconds == nil, let text = t.inText {
                let parsed = try DurationParser.parse(text, now: clock())
                seconds = parsed.seconds
                title = title ?? parsed.title
            }
            guard let seconds else { return .error(422, "send 'seconds' or 'in', e.g. {\"in\": \"20m\", \"title\": \"Tea\"}") }
            guard seconds > 0, seconds <= 24 * 3600 else { return .error(422, "'seconds' must be between 1 and 86400") }
            return try await timerReply(.start(seconds: seconds, title: title, id: admitted(timerID: t.id)), status: 201)

        case ("GET", 1, "timers"):
            return .json(await backend.listTimers())

        case ("PATCH", 1, "timers"), ("PATCH", 2, "timers"), ("POST", 2, "timers"):
            let c = try decode(TimerControlPush.self, from: r)
            var seconds = c.seconds
            if seconds == nil, let text = c.inText { seconds = try DurationParser.parse(text, now: clock()).seconds }
            return try await timerReply(.control(c.action, id: rest.count == 2 ? sub : nil, seconds: seconds))

        case ("DELETE", 2, "timers"):
            return try await timerReply(.control(.stop, id: sub, seconds: nil))

        case ("POST", 1, "pomodoro"):
            let p = try decode(PomodoroPush.self, from: r)
            return try await timerReply(.pomodoro(p.action), status: 201)

        case ("POST", 1, "hud"):
            let h = try decode(HUDPush.self, from: r)
            guard h.value.isFinite else { return .error(422, "'value' must be a number between 0 and 1") }
            await backend.showHUD(kind: h.kind, value: h.value, muted: h.muted ?? false, label: h.label)
            return .noContent

        case ("POST", 1, "media"):
            let m = try decode(MediaPush.self, from: r)
            let np = NowPlaying(
                source: .external, bundleID: m.bundleID, appName: m.appName, title: m.title, artist: m.artist,
                album: m.album, isPlaying: m.isPlaying ?? true, duration: m.duration, elapsed: m.elapsed,
                timestamp: clock(), artworkURL: m.artworkURL
            )
            await backend.pushMedia(np)
            return .noContent

        case ("DELETE", 1, "media"):
            await backend.pushMedia(nil)
            return .noContent

        case ("POST", 2, "media") where sub == "command":
            let c = try decode(CommandPush.self, from: r)
            let ok = await backend.mediaCommand(c.command, position: c.position)
            return ok ? .noContent : .error(503, "no player available for '\(c.command.rawValue)'")

        case ("POST", 2, "island") where sub == "open":
            await backend.setExpanded(true)
            return .noContent

        case ("POST", 2, "island") where sub == "close":
            await backend.setExpanded(false)
            return .noContent

        case (_, 1, "awake"):
            switch r.method {
            case "GET":
                return .json(await backend.keepAwake(nil))
            case "POST", "PUT":
                let minutes = r.body.isEmpty ? nil : try decode(AwakePush.self, from: r).minutes
                if let m = minutes, !(m >= 0 && m <= KeepAwake.maxMinutes) {
                    return .error(422, "'minutes' must be from 0 (until turned off) to \(Int(KeepAwake.maxMinutes))")
                }
                return .json(await backend.keepAwake(.start(minutes: minutes == 0 ? nil : minutes)))
            case "DELETE":
                return .json(await backend.keepAwake(.stop))
            default:
                return .error(405, "\(r.method) is not supported on \(r.path)")
            }

        case ("GET", 2, "debug") where sub == "menubar":
            let items = await backend.menuBarItems()
            return .json(await backend.sharesMirroredActivities() ? items : MenuBarLiveActivities.withoutActivityText(items))

        case ("POST", 1, "focus"):
            let f = try decode(FocusPush.self, from: r)
            return .json(try await apply(admitted(FocusPill.activity(name: f.name ?? "Focus", on: f.on ?? true))), status: 201)

        case ("POST", 2, "hooks"):
            let provider = sub
            if let held = await approvalHook(r, provider: provider) { return held }
            switch try AgentHooks.map(provider: provider, payload: r.body, now: clock()) {
            case .upsert(let spec): return .json(try await apply(spec))
            case .remove(let id):
                _ = try await remove(id: id)
                return .noContent
            case .ignore: return .noContent
            }

        default:
            let known = ["state", "activities", "notify", "timer", "hud", "media", "island", "hooks", "focus", "debug", "timers", "pomodoro"]
            if let first = rest.first, known.contains(first) {
                return .error(405, "\(r.method) is not supported on \(r.path)")
            }
            return .error(404, "unknown endpoint \(r.path)")
        }
    }

    /// The timer a command touched (`204` when it stopped one); unknown timers are `404`.
    private func timerReply(_ command: TimerCommand, status: Int = 200) async throws -> HTTPResponse {
        do {
            guard let timer = try await backend.timerCommand(command) else { return .noContent }
            return .json(timer, status: status)
        } catch let e as TimerError {
            switch e {
            case .notFound, .noTimers: return .error(404, e.description)
            default: throw e
            }
        }
    }
}
