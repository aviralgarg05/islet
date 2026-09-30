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
    func stateSnapshot() async -> StateSnapshot {
        StateSnapshot(version: "test", presentation: "idle", activities: center.ordered(now: now), nowPlaying: nil, battery: nil)
    }
    func menuBarItems() async -> [MenuBarItemInfo] { [] }

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
        #expect(try APIJSON.decoder.decode(Activity.self, from: t.body).endsAt == t0.addingTimeInterval(300))
        #expect(await rt.handle(request("POST", "/v1/timer", body: #"{"seconds":0}"#)).status == 422)

        #expect(await rt.handle(request("POST", "/v1/hud", body: #"{"kind":"volume","value":0.4}"#)).status == 204)
        #expect(await b.hud?.0 == .volume)

        // No player yet: command reports 503.
        #expect(await rt.handle(request("POST", "/v1/media/command", body: #"{"command":"next"}"#)).status == 503)
        #expect(await rt.handle(request("POST", "/v1/media", body: #"{"title":"Song","artist":"X","isPlaying":true}"#)).status == 204)
        #expect(await b.media?.source == .external)
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
