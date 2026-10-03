import Foundation
import Testing
@testable import IsletCore

/// In-memory backend used to exercise the router.
actor FakeBackend: IsletBackend {
    var center = ActivityCenter()
    var hud: (HUDKind, Double)?
    var media: NowPlaying?
    var commands: [PlaybackCommand] = []
    var expanded = false
    var awake: KeepAwakeSession?
    let now: Date

    init(now: Date) { self.now = now }

    func listActivities() async -> [Activity] { center.ordered(now: now) }
    func applyActivity(_ spec: ActivitySpec) async throws -> Activity { try center.apply(spec, now: now, makeID: { "generated" }) }
    func removeActivity(id: String) async -> Bool { center.remove(id: id) != nil }
    func removeActivities(source: String) async -> Int { center.removeAll(source: source) }
    func showHUD(kind: HUDKind, value: Double, muted: Bool, label: String?) async { hud = (kind, value) }
    func pushMedia(_ media: NowPlaying?) async { self.media = media }
    func mediaCommand(_ command: PlaybackCommand, position: Double?) async -> Bool {
        commands.append(command)
        return media != nil
    }
    func setExpanded(_ expanded: Bool) async { self.expanded = expanded }
    var calendar: CalendarStatus?
    func setCalendar(_ status: CalendarStatus?) { calendar = status }
    func stateSnapshot() async -> StateSnapshot {
        StateSnapshot(version: "test", presentation: "idle", activities: center.ordered(now: now), nowPlaying: nil, battery: nil,
                      calendar: calendar)
    }
    var menuBar: [MenuBarItemInfo] = []
    func menuBarItems() async -> [MenuBarItemInfo] { menuBar }
    var sharesMirrored = false
    func sharesMirroredActivities() async -> Bool { sharesMirrored }
    func share(_ on: Bool, menuBar items: [MenuBarItemInfo] = []) {
        sharesMirrored = on
        menuBar = items
    }
    func keepAwake(_ change: KeepAwakeChange?) async -> KeepAwakeStatus {
        switch change {
        case .start(let minutes)?: awake = KeepAwakeSession(since: now, until: minutes.map { now.addingTimeInterval($0 * 60) })
        case .stop?: awake = nil
        case nil: break
        }
        return KeepAwake.status(awake, now: now)
    }
    var timers = TimerEngine()
    func listTimers() async -> [TimerItem] { timers.ordered }
    func timerCommand(_ command: TimerCommand) async throws -> TimerItem? { try timers.perform(command, now: now) }

    var approvalEvents: [ApprovalEvent] = []
    /// What `.ask` answers; with `hangs` it waits until cancelled instead.
    var decision: ApprovalDecision?
    var hangs = false
    var cancelledAsks = 0

    func script(_ decision: ApprovalDecision?, hangs: Bool = false) {
        self.decision = decision
        self.hangs = hangs
    }

    func handleApproval(_ event: ApprovalEvent) async -> ApprovalDecision? {
        approvalEvents.append(event)
        guard case .ask = event else { return nil }
        if hangs {
            try? await Task.sleep(nanoseconds: 3_600_000_000_000)
            if Task.isCancelled { cancelledAsks += 1 }
            return nil
        }
        return decision
    }
}

@Suite struct HTTPParserTests {
    @Test func parsesCompleteRequest() {
        let raw = "POST /v1/activities?x=1&y=two%20words HTTP/1.1\r\nHost: 127.0.0.1:47831\r\nContent-Length: 5\r\nX-Thing: a:b\r\n\r\nhello"
        guard case .complete(let r) = HTTPParser.parse(Data(raw.utf8)) else { Issue.record("not complete"); return }
        #expect(r.method == "POST")
        #expect(r.path == "/v1/activities")
        #expect(r.segments == ["v1", "activities"])
        #expect(r.query == ["x": "1", "y": "two words"])
        #expect(r.headers["x-thing"] == "a:b")
        #expect(String(decoding: r.body, as: UTF8.self) == "hello")
    }

    @Test func incompleteUntilBodyArrives() {
        let head = "POST / HTTP/1.1\r\nContent-Length: 10\r\n\r\n12345"
        #expect(HTTPParser.parse(Data(head.utf8)) == .incomplete)
        #expect(HTTPParser.parse(Data("GET / HTTP/1.1\r\nHost: x".utf8)) == .incomplete)
    }

    @Test func rejectsBadInput() {
        if case .invalid(let status, _) = HTTPParser.parse(Data("NONSENSE\r\n\r\n".utf8)) { #expect(status == 400) } else { Issue.record("expected invalid") }
        if case .invalid(let status, _) = HTTPParser.parse(Data("POST / HTTP/1.1\r\nTransfer-Encoding: chunked\r\n\r\n".utf8)) { #expect(status == 411) } else { Issue.record("expected 411") }
        if case .invalid(let status, _) = HTTPParser.parse(Data("POST / HTTP/1.1\r\nContent-Length: 99999999\r\n\r\n".utf8)) { #expect(status == 413) } else { Issue.record("expected 413") }
        if case .invalid(let status, _) = HTTPParser.parse(Data(repeating: 65, count: 20_000)) { #expect(status == 413) } else { Issue.record("expected 413 for huge headers") }
    }

    /// The server reads up to 64 KB at a time, so oversized headers can arrive with their
    /// terminator in one go. They are refused either way.
    @Test func oversizedHeadersAreRefusedEvenWithTheirTerminator() {
        let padding = String(repeating: "a", count: HTTPParser.maxHeaderBytes)
        let raw = "GET / HTTP/1.1\r\nHost: x\r\nX-Pad: \(padding)\r\n\r\n"
        if case .invalid(let status, _) = HTTPParser.parse(Data(raw.utf8)) { #expect(status == 413) } else { Issue.record("expected 413") }
        if case .invalid(let status, _) = HTTPParser.parseHead(Data(raw.utf8)) { #expect(status == 413) } else { Issue.record("expected 413") }
        // Just inside the limit still parses, terminator included.
        let fits = "GET / HTTP/1.1\r\nHost: x\r\nX-Pad: " + String(repeating: "a", count: HTTPParser.maxHeaderBytes - 40) + "\r\n\r\n"
        #expect(fits.utf8.count <= HTTPParser.maxHeaderBytes)
        guard case .complete = HTTPParser.parse(Data(fits.utf8)) else { Issue.record("should parse"); return }
    }

    @Test func percentEncodedSegments() {
        guard case .complete(let r) = HTTPParser.parse(Data("DELETE /v1/activities/a%3Ab HTTP/1.1\r\n\r\n".utf8)) else { Issue.record("x"); return }
        #expect(r.segments == ["v1", "activities", "a:b"])
    }

    @Test func responseSerialization() {
        let s = String(decoding: HTTPResponse.error(404, "nope").serialized(), as: UTF8.self)
        #expect(s.hasPrefix("HTTP/1.1 404 Not Found\r\n"))
        #expect(s.contains("Content-Length: 16\r\n"))
        #expect(s.hasSuffix("\r\n\r\n{\"error\":\"nope\"}"))
    }

    @Test func datesAcceptSecondsMillisAndISO() throws {
        struct D: Decodable { var d: Date }
        let a = try APIJSON.decoder.decode(D.self, from: Data(#"{"d": 1800000000}"#.utf8))
        let b = try APIJSON.decoder.decode(D.self, from: Data(#"{"d": 1800000000000}"#.utf8))
        let c = try APIJSON.decoder.decode(D.self, from: Data(#"{"d": "2027-01-15T08:00:00Z"}"#.utf8))
        let e = try APIJSON.decoder.decode(D.self, from: Data(#"{"d": "2027-01-15T08:00:00.000Z"}"#.utf8))
        #expect(a.d == t0)
        #expect(b.d == t0)
        #expect(c.d == t0)
        #expect(e.d == t0)
    }
}

@Suite struct APIRouterTests {
    let token = "secret-token"

    func request(_ method: String, _ path: String, body: String? = nil, token: String? = "secret-token", headers: [String: String] = [:]) -> HTTPRequest {
        var h = headers
        if let token { h["Authorization"] = "Bearer \(token)" }
        let raw = "\(method) \(path) HTTP/1.1\r\n" + h.map { "\($0.key): \($0.value)\r\n" }.joined()
            + "Content-Length: \(body?.utf8.count ?? 0)\r\n\r\n" + (body ?? "")
        guard case .complete(let r) = HTTPParser.parse(Data(raw.utf8)) else { fatalError("bad test request") }
        return r
    }

    func router(_ b: FakeBackend) -> APIRouter {
        APIRouter(token: token, version: "1.0-test", backend: b, clock: { t0 })
    }

    @Test func healthNeedsNoToken() async {
        let r = await router(FakeBackend(now: t0)).handle(request("GET", "/v1/health", token: nil))
        #expect(r.status == 200)
        // Loopback gives the version; the bridge's reply leaves it out (LANBridgeTests).
        #expect(String(decoding: r.body, as: UTF8.self).contains("\"version\":\"1.0-test\""))
    }

    /// On loopback the Focus pill keeps its plain id: `isletctl focus` drives the Mac's own.
    @Test func focusOnLoopbackKeepsItsID() async {
        let b = FakeBackend(now: t0)
        let rt = router(b)
        #expect(await rt.handle(request("POST", "/v1/focus", body: #"{"name":"Work","on":true}"#)).status == 201)
        #expect(await b.center.activities["focus"]?.title == "Work")
    }

    @Test func authIsEnforced() async {
        let rt = router(FakeBackend(now: t0))
        #expect(await rt.handle(request("GET", "/v1/activities", token: nil)).status == 401)
        #expect(await rt.handle(request("GET", "/v1/activities", token: "wrong")).status == 401)
        #expect(await rt.handle(request("GET", "/v1/activities")).status == 200)
        let alt = request("GET", "/v1/activities", token: nil, headers: ["X-Islet-Token": token])
        #expect(await rt.handle(alt).status == 200)
    }

    @Test func webPagesAndRebindingAreBlocked() async {
        let rt = router(FakeBackend(now: t0))
        let fromPage = request("POST", "/v1/notify", body: #"{"title":"x"}"#, headers: ["Origin": "https://evil.example"])
        #expect(await rt.handle(fromPage).status == 403)
        let rebinding = request("GET", "/v1/activities", headers: ["Host": "evil.example:47831"])
        #expect(await rt.handle(rebinding).status == 403)
        let ext = request("GET", "/v1/activities", headers: ["Origin": "chrome-extension://abc", "Host": "127.0.0.1:47831"])
        #expect(await rt.handle(ext).status == 200)
        let localhost = request("GET", "/v1/activities", headers: ["Host": "localhost:47831"])
        #expect(await rt.handle(localhost).status == 200)
    }

    @Test func activityCRUD() async throws {
        let b = FakeBackend(now: t0)
        let rt = router(b)
        let created = await rt.handle(request("POST", "/v1/activities", body: #"{"id":"build","title":"Build","progress":0.25,"icon":"sf:hammer"}"#))
        #expect(created.status == 201)
        let a = try APIJSON.decoder.decode(Activity.self, from: created.body)
        #expect(a.id == "build")
        #expect(a.icon == .symbol("hammer"))

        let updated = await rt.handle(request("PATCH", "/v1/activities/build", body: #"{"progress":0.9}"#))
        #expect(updated.status == 200)
        #expect(try APIJSON.decoder.decode(Activity.self, from: updated.body).progress == 0.9)

        let list = await rt.handle(request("GET", "/v1/activities"))
        #expect(try APIJSON.decoder.decode([Activity].self, from: list.body).map(\.id) == ["build"])

        #expect(await rt.handle(request("DELETE", "/v1/activities/build")).status == 204)
        #expect(await rt.handle(request("DELETE", "/v1/activities/build")).status == 404)
    }

    @Test func validationErrorsAreReadable() async {
        let rt = router(FakeBackend(now: t0))
        let noTitle = await rt.handle(request("POST", "/v1/activities", body: #"{"id":"x"}"#))
        #expect(noTitle.status == 422)
        #expect(String(decoding: noTitle.body, as: UTF8.self).contains("title"))
        let badJSON = await rt.handle(request("POST", "/v1/activities", body: "{nope"))
        #expect(badJSON.status == 422)
        let empty = await rt.handle(request("POST", "/v1/activities"))
        #expect(empty.status == 422)
        let badPriority = await rt.handle(request("POST", "/v1/activities", body: #"{"title":"x","priority":"meh"}"#))
        #expect(badPriority.status == 422)
    }

    @Test func notifyTimerHudMediaIsland() async throws {
        let b = FakeBackend(now: t0)
        let rt = router(b)
        let n = await rt.handle(request("POST", "/v1/notify", body: #"{"title":"Hi","ttl":3}"#))
        #expect(n.status == 201)
        let na = try APIJSON.decoder.decode(Activity.self, from: n.body)
        #expect(na.expiresAt == t0.addingTimeInterval(3))

        let t = await rt.handle(request("POST", "/v1/timer", body: #"{"seconds":300,"title":"Tea"}"#))
        #expect(t.status == 201)
        #expect(try APIJSON.decoder.decode(TimerItem.self, from: t.body).endsAt == t0.addingTimeInterval(300))
        #expect(await rt.handle(request("POST", "/v1/timer", body: #"{"seconds":0}"#)).status == 422)

        #expect(await rt.handle(request("POST", "/v1/hud", body: #"{"kind":"volume","value":0.4}"#)).status == 204)
        #expect(await b.hud?.0 == .volume)

        // No player yet: command reports 503.
        #expect(await rt.handle(request("POST", "/v1/media/command", body: #"{"command":"next"}"#)).status == 503)
        #expect(await rt.handle(request("POST", "/v1/media", body: #"{"title":"Song","artist":"X","isPlaying":true}"#)).status == 204)
        #expect(await b.media?.source == .external)
        // A length or position wider than any recording would put the song's end at a date no
        // one will see, where it holds the app's one deadline timer.
        #expect(await rt.handle(request("POST", "/v1/media", body: #"{"title":"Song","duration":1e300}"#)).status == 422)
        #expect(await rt.handle(request("POST", "/v1/media", body: #"{"title":"Song","elapsed":-1e300}"#)).status == 422)
        #expect(await rt.handle(request("POST", "/v1/media", body: #"{"title":"Song","duration":243.4,"elapsed":12}"#)).status == 204)
        #expect(await rt.handle(request("POST", "/v1/media/command", body: #"{"command":"next"}"#)).status == 204)
        #expect(await b.commands == [.next, .next])
        #expect(await rt.handle(request("DELETE", "/v1/media")).status == 204)
        #expect(await b.media == nil)

        #expect(await rt.handle(request("POST", "/v1/island/open")).status == 204)
        #expect(await b.expanded)
        #expect(await rt.handle(request("POST", "/v1/island/close")).status == 204)
        #expect(await !b.expanded)
    }

    @Test func removeBySource() async throws {
        let b = FakeBackend(now: t0)
        let rt = router(b)
        _ = await rt.handle(request("POST", "/v1/activities", body: #"{"id":"a","source":"ci","title":"x"}"#))
        _ = await rt.handle(request("POST", "/v1/activities", body: #"{"id":"b","source":"ci","title":"x"}"#))
        #expect(await rt.handle(request("DELETE", "/v1/activities")).status == 400)
        let r = await rt.handle(request("DELETE", "/v1/activities?source=ci"))
        #expect(String(decoding: r.body, as: UTF8.self) == #"{"removed":2}"#)
    }

    @Test func unknownRoutes() async {
        let rt = router(FakeBackend(now: t0))
        #expect(await rt.handle(request("GET", "/v2/whatever")).status == 404)
        #expect(await rt.handle(request("GET", "/v1/nope")).status == 404)
        #expect(await rt.handle(request("PUT", "/v1/notify", body: "{}")).status == 405)
    }

    @Test func hooksEndpointMapsClaudePayload() async throws {
        let b = FakeBackend(now: t0)
        let rt = router(b)
        let payload = #"{"hook_event_name":"Notification","session_id":"abc123def456789","cwd":"/Users/me/code/islet","message":"Claude needs your permission to use Bash"}"#
        let r = await rt.handle(request("POST", "/v1/hooks/claude", body: payload))
        #expect(r.status == 200)
        let a = try APIJSON.decoder.decode(Activity.self, from: r.body)
        #expect(a.id == "claude-abc123def456")
        #expect(a.state == .waiting)
        #expect(a.priority == .high)
        #expect(a.title == "Claude · islet")
        let end = #"{"hook_event_name":"SessionEnd","session_id":"abc123def456789"}"#
        #expect(await rt.handle(request("POST", "/v1/hooks/claude", body: end)).status == 204)
        #expect(await b.center.activities.isEmpty)
    }

    @Test func tokenComparison() {
        #expect(APIRouter.tokensMatch("abc", "abc"))
        #expect(!APIRouter.tokensMatch("abc", "abd"))
        #expect(!APIRouter.tokensMatch("abc", "abcd"))
    }
}

/// Live Activities mirrored from the menu bar belong to the mirror: scripts can't change them,
/// and only read them when the user shares them.
extension APIRouterTests {
    static let mirroredID = "live-abc123"

    /// A mirrored activity, added the way the app's mirror adds it rather than through the API,
    /// next to a script's own.
    func addMirrored(to b: FakeBackend) async throws {
        var spec = MenuBarLiveActivities.activity(for: MirroredLiveActivity(key: "pill", appName: "Uber", detail: "4 min · 12 Acacia Avenue"),
                                                  look: nil, isNew: true)
        spec.id = Self.mirroredID
        _ = try await b.applyActivity(spec)
        _ = try await b.applyActivity(ActivitySpec(id: "build", source: "ci", title: "Build"))
    }

    func leaks(_ r: HTTPResponse) -> Bool {
        let text = String(decoding: r.body, as: UTF8.self)
        return text.contains("Uber") || text.contains("Acacia")
    }

    @Test func mirroredActivitiesCantBeWritten() async throws {
        for sharing in [false, true] {
            let b = FakeBackend(now: t0)
            try await addMirrored(to: b)
            await b.share(sharing)
            let rt = router(b)
            // The answer is the same whether or not the id exists, whatever the body.
            let writes: [(String, String?)] = [("PATCH", #"{"subtitle":"x"}"#), ("PUT", #"{"title":"x"}"#), ("POST", #"{"title":"x"}"#),
                                               ("PATCH", "{nope"), ("PATCH", nil), ("DELETE", nil)]
            for (method, body) in writes {
                let hit = await rt.handle(request(method, "/v1/activities/\(Self.mirroredID)", body: body))
                let miss = await rt.handle(request(method, "/v1/activities/live-nothing", body: body))
                #expect(hit.status == 403, "\(method) \(body ?? "")")
                #expect(hit.status == miss.status && hit.body == miss.body, "\(method) \(body ?? "")")
                #expect(!leaks(hit))
            }
            let refused = [
                await rt.handle(request("POST", "/v1/activities", body: #"{"id":"live-abc123","title":"x"}"#)),
                await rt.handle(request("POST", "/v1/activities", body: #"{"id":"mine","source":"live-activity","title":"x"}"#)),
                await rt.handle(request("POST", "/v1/notify", body: #"{"title":"x","source":"live-activity"}"#)),
                // The count would say how many are showing.
                await rt.handle(request("DELETE", "/v1/activities?source=live-activity")),
                // A generic agent's name becomes the source.
                await rt.handle(request("POST", "/v1/hooks/x", body: #"{"agent":"live-activity","session":"abc123","event":"running"}"#)),
            ]
            for r in refused {
                #expect(r.status == 403)
                #expect(String(decoding: r.body, as: UTF8.self).contains("mirrored from the menu bar"))
                #expect(!leaks(r))
            }
            // The approvals path answers as usual but shows nothing.
            let held = await rt.handle(request("POST", "/v1/hooks/x?wait=1", body: #"{"agent":"live-activity","session":"abc123","event":"running"}"#))
            #expect(held.status == 204)
            // An agent called "live" gets its own activity, not the mirrored one with its would-be id.
            let agent = await rt.handle(request("POST", "/v1/hooks/live", body: #"{"agent":"live","session":"abc123","event":"running"}"#))
            #expect(agent.status == 200)
            #expect(try APIJSON.decoder.decode(Activity.self, from: agent.body).id == "agent-live-abc123")
            #expect(!leaks(agent))
            #expect(await rt.handle(request("POST", "/v1/hooks/live", body: #"{"agent":"live","session":"abc123","event":"end"}"#)).status == 204)
            // A timer shows as the activity with its id.
            let timer = await rt.handle(request("POST", "/v1/timer", body: #"{"seconds":60,"id":"live-abc123"}"#))
            #expect(timer.status == 422)
            #expect(!leaks(timer))
            #expect(await b.timers.timers.isEmpty)

            let a = await b.center.activities[Self.mirroredID]
            #expect(a?.title == "Uber")
            #expect(a?.subtitle == "4 min · 12 Acacia Avenue")
            #expect(await b.center.activities.count == 2)
            // The script's own activities still work.
            #expect(await rt.handle(request("PATCH", "/v1/activities/build", body: #"{"progress":0.5}"#)).status == 200)
            #expect(await rt.handle(request("DELETE", "/v1/activities?source=ci")).status == 200)
        }
    }

    /// A mirrored banner carries its own words, so it is read only when the user shares what
    /// Islet mirrors, the same as a mirrored Live Activity.
    @Test func mirroredNotificationsAreReadOnlyWhenShared() async throws {
        let b = FakeBackend(now: t0)
        let banner = MirroredNotification(appName: "Messages", bundleID: "com.apple.MobileSMS",
                                          title: "Sam", body: "the spare key is under the mat")
        let spec = banner.activity(rule: nil)
        #expect(MirroredNotification.isMirrored(id: spec.id ?? ""))
        _ = try await b.applyActivity(spec)
        _ = try await b.applyActivity(ActivitySpec(id: "build", source: "ci", title: "Build"))
        let rt = router(b)

        func reads() async -> [HTTPResponse] {
            [await rt.handle(request("GET", "/v1/activities")), await rt.handle(request("GET", "/v1/state"))]
        }
        await b.share(false)
        for r in await reads() {
            let text = String(decoding: r.body, as: UTF8.self)
            #expect(!text.contains("spare key") && !text.contains("Sam"), "\(text)")
        }
        #expect(try APIJSON.decoder.decode([Activity].self, from: await rt.handle(request("GET", "/v1/activities")).body)
                .map(\.id) == ["build"])

        await b.share(true)
        for r in await reads() {
            #expect(String(decoding: r.body, as: UTF8.self).contains("spare key"))
        }
    }

    @Test func mirroredActivitiesAreReadOnlyWhenShared() async throws {
        #expect(MenuBarLiveActivities.isMirrored(id: MenuBarLiveActivities.activityID("pill")))
        let b = FakeBackend(now: t0)
        try await addMirrored(to: b)
        var pill = MenuBarItemInfo(identifier: "live-activity-pill-9", description: "Live Activity", texts: ["4 min", "12 Acacia Avenue"])
        pill.kind = .liveActivity
        var unknown = MenuBarItemInfo(role: "AXMenuBarItem", texts: ["Uber"])
        unknown.kind = .unknown
        var battery = MenuBarItemInfo(identifier: "com.apple.menuextra.battery", description: "Battery 76%")
        battery.kind = .systemItem
        let rt = router(b)

        await b.share(false, menuBar: [pill, unknown, battery])
        let list = await rt.handle(request("GET", "/v1/activities"))
        #expect(try APIJSON.decoder.decode([Activity].self, from: list.body).map(\.id) == ["build"])
        let state = await rt.handle(request("GET", "/v1/state"))
        #expect(try APIJSON.decoder.decode(StateSnapshot.self, from: state.body).activities.map(\.id) == ["build"])
        // There's no read by id; asking for one says nothing about it.
        let byID = await rt.handle(request("GET", "/v1/activities/\(Self.mirroredID)"))
        #expect(byID.status == 405)
        // Diagnostics keep what each item is and where, without the text.
        let debug = await rt.handle(request("GET", "/v1/debug/menubar"))
        let items = try APIJSON.decoder.decode([MenuBarItemInfo].self, from: debug.body)
        #expect(items.map(\.identifier) == ["live-activity-pill-9", nil, "com.apple.menuextra.battery"])
        #expect(items.map(\.kind) == [.liveActivity, .unknown, .systemItem])
        #expect(items.map(\.allText) == [[], [], ["Battery 76%"]])
        for r in [list, state, byID, debug] { #expect(!leaks(r)) }

        await b.share(true, menuBar: [pill, unknown, battery])
        let shared = await rt.handle(request("GET", "/v1/activities"))
        #expect(Set(try APIJSON.decoder.decode([Activity].self, from: shared.body).map(\.id)) == [Self.mirroredID, "build"])
        let sharedState = await rt.handle(request("GET", "/v1/state"))
        #expect(try APIJSON.decoder.decode(StateSnapshot.self, from: sharedState.body).activities.count == 2)
        let sharedDebug = await rt.handle(request("GET", "/v1/debug/menubar"))
        #expect(try APIJSON.decoder.decode([MenuBarItemInfo].self, from: sharedDebug.body).map(\.allText)
                == [["Live Activity", "4 min", "12 Acacia Avenue"], ["Uber"], ["Battery 76%"]])
    }
}
