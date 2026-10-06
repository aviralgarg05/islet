import Foundation
import Testing
@testable import CasementCore

/// The local-network bridge: its own token, a short allow-list, and activities it can't use
/// to open links, show files or outrank everything.
@Suite struct LANScopeTests {
    let lanToken = "lan-" + String(repeating: "b", count: 8)
    let apiToken = "api-" + String(repeating: "a", count: 8)

    func lan(_ b: FakeBackend) -> APIRouter { APIRouter(token: lanToken, version: "t", backend: b, scope: .lan, clock: { t0 }) }
    func local(_ b: FakeBackend) -> APIRouter { APIRouter(token: apiToken, version: "t", backend: b, clock: { t0 }) }

    func req(_ method: String, _ path: String, token: String?, body: String? = nil) -> HTTPRequest {
        var headers = ["Host": "my-mac.local:47832"]
        if let token { headers["Authorization"] = "Bearer \(token)" }
        let parts = path.split(separator: "?", maxSplits: 1)
        var query: [String: String] = [:]
        if parts.count == 2 {
            for pair in parts[1].split(separator: "&") {
                let kv = pair.split(separator: "=", maxSplits: 1).map(String.init)
                query[kv[0]] = kv.count == 2 ? kv[1] : ""
            }
        }
        return HTTPRequest(method: method, path: String(parts[0]), query: query, headers: headers, body: Data((body ?? "").utf8))
    }

    func activity(_ r: HTTPResponse) -> Activity? { try? APIJSON.decoder.decode(Activity.self, from: r.body) }

    @Test func refusesEverythingOutsideTheAllowList() async {
        let b = FakeBackend(now: t0)
        _ = try? await b.applyActivity(ActivitySpec(id: "build", source: "ci", title: "Build"))
        let rt = lan(b)
        let refused: [(String, String, String?)] = [
            ("GET", "/v1/state", nil),
            ("GET", "/v1/activities", nil),
            ("DELETE", "/v1/activities/build", nil),
            ("DELETE", "/v1/activities?source=ci", nil),
            ("PATCH", "/v1/activities/build", #"{"title":"x"}"#),
            ("POST", "/v1/media", #"{"title":"Song"}"#),
            ("DELETE", "/v1/media", nil),
            ("POST", "/v1/media/command", #"{"command":"next"}"#),
            ("POST", "/v1/hooks/claude", #"{"session_id":"a","hook_event_name":"Stop"}"#),
            ("POST", "/v1/hooks/claude?wait=5", #"{"session_id":"a","hook_event_name":"Stop"}"#),
            ("POST", "/v1/island/open", nil),
            ("POST", "/v1/island/close", nil),
            ("GET", "/v1/debug/menubar", nil),
            ("POST", "/v1/hud", #"{"kind":"volume","value":0.5}"#),
            ("GET", "/v1/awake", nil),
            ("POST", "/v1/awake", #"{"minutes":60}"#),
            ("GET", "/v1/timers", nil),
            ("PATCH", "/v1/timers/timer-1", #"{"action":"stop"}"#),
            ("DELETE", "/v1/timers/timer-1", nil),
            ("POST", "/v1/pomodoro", #"{"action":"start"}"#),
            ("POST", "/v1/nothing", #"{}"#),
            ("GET", "/health/extra", nil),
        ]
        for (method, path, body) in refused {
            let r = await rt.handle(req(method, path, token: lanToken, body: body))
            #expect(r.status == 403, "\(method) \(path) gave \(r.status)")
        }
        // Nothing reached the backend.
        #expect(await b.center.activities.keys.sorted() == ["build"])
        #expect(await b.expanded == false)
        #expect(await b.hud == nil)
        #expect(await b.media == nil)
        #expect(await b.approvalEvents.isEmpty)
        #expect(await b.awake == nil)
    }

    /// The bridge answers the health check without a token and is advertised over Bonjour, so
    /// its reply says only that Casement is there. Loopback still gives the version.
    @Test func lanHealthLeavesOutTheVersion() async {
        let b = FakeBackend(now: t0)
        let bridge = String(decoding: await lan(b).handle(req("GET", "/v1/health", token: nil)).body, as: UTF8.self)
        #expect(bridge.contains("\"ok\"") && !bridge.contains("version"))
    }

    @Test func acceptsNotifyTimerFocusAndActivities() async {
        let b = FakeBackend(now: t0)
        let rt = lan(b)
        #expect(await rt.handle(req("GET", "/v1/health", token: nil)).status == 200)
        #expect(await rt.handle(req("POST", "/v1/notify", token: lanToken, body: #"{"title":"Alarm"}"#)).status == 201)
        #expect(await rt.handle(req("POST", "/v1/timer", token: lanToken, body: #"{"seconds":300,"title":"Tea"}"#)).status == 201)
        #expect(await rt.handle(req("POST", "/v1/timers", token: lanToken, body: #"{"in":"20m"}"#)).status == 201)
        #expect(await rt.handle(req("POST", "/v1/focus", token: lanToken, body: #"{"name":"Work","on":true}"#)).status == 201)
        #expect(await rt.handle(req("POST", "/v1/activities", token: lanToken, body: #"{"id":"a","title":"A"}"#)).status == 201)
        #expect(await rt.handle(req("PUT", "/v1/activities/b", token: lanToken, body: #"{"title":"B"}"#)).status == 200)
        #expect(await rt.handle(req("POST", "/v1/activities/c", token: lanToken, body: #"{"title":"C"}"#)).status == 200)
        // Focus keeps its fixed id: the iPhone's Focus is the Mac's Focus pill, so it moves the
        // one already there rather than adding a second beside it. The rest of the admission
        // still applies, and the bridge has no route that removes an activity.
        #expect(await b.center.activities["focus"]?.title == "Work")
        #expect(await b.center.activities["lan-focus"] == nil)
    }

    @Test func activitiesAreNamespacedAndStripped() async throws {
        let b = FakeBackend(now: t0)
        let rt = lan(b)
        let body = """
        {"id":"deploy","title":"Deploy","icon":"https://example.com/i.png","priority":"critical",
         "url":"https://example.com","actions":[{"title":"Open","url":"file:///Applications/Calculator.app"}],
         "trackerIcon":"file:///tmp/x.png","stageSymbols":["sf:bag","https://example.com/s.png"]}
        """
        let created = activity(await rt.handle(req("POST", "/v1/activities", token: lanToken, body: body)))
        let a = try #require(created)
        #expect(a.id == "lan-deploy")
        #expect(a.url == nil)
        #expect(a.actions.isEmpty)
        #expect(a.icon == nil)
        #expect(a.priority == .high)
        #expect(a.trackerIcon == nil)
        #expect(a.stageSymbols == nil)
        // Casement's own and the API's activities are out of reach: the id stays under lan-.
        _ = try await b.applyActivity(ActivitySpec(id: "claude-abc", source: "claude-code", title: "Claude"))
        let put = activity(await rt.handle(req("PUT", "/v1/activities/claude-abc", token: lanToken, body: #"{"title":"Spoof"}"#)))
        #expect(put?.id == "lan-claude-abc")
        #expect(await b.center.activities["claude-abc"]?.title == "Claude")
        // Already prefixed ids aren't doubled; symbols, emoji and app icons pass.
        let again = activity(await rt.handle(req("PUT", "/v1/activities/lan-deploy", token: lanToken, body: #"{"icon":"sf:checkmark","url":"https://example.com"}"#)))
        #expect(again?.id == "lan-deploy")
        #expect(again?.icon == .symbol("checkmark"))
        #expect(again?.url == nil)
        // No id: a new one, still under lan-.
        let fresh = activity(await rt.handle(req("POST", "/v1/activities", token: lanToken, body: #"{"title":"Anon","icon":"emoji:🍕"}"#)))
        #expect(fresh?.id.hasPrefix("lan-") == true)
        #expect(fresh?.icon == .emoji("🍕"))
    }

    /// Every pill from the network expires. Without a ceiling a peer with the token could fill
    /// all 64 slots in about twenty seconds with pills that never go, pushing out the Mac's own.
    @Test func everyActivityFromTheNetworkExpires() async throws {
        let b = FakeBackend(now: t0)
        let rt = lan(b)
        let ceiling = t0.addingTimeInterval(APIRouter.lanMaxTTL)
        // No ttl at all, and a ttl of 0, both mean "until dismissed" elsewhere.
        #expect(activity(await rt.handle(req("POST", "/v1/activities", token: lanToken, body: #"{"id":"a","title":"A"}"#)))?.expiresAt == ceiling)
        #expect(activity(await rt.handle(req("POST", "/v1/activities", token: lanToken, body: #"{"id":"b","title":"B","ttl":0}"#)))?.expiresAt == ceiling)
        #expect(activity(await rt.handle(req("POST", "/v1/activities", token: lanToken, body: #"{"id":"c","title":"C","ttl":999999}"#)))?.expiresAt == ceiling)
        // A shorter ttl is kept as it is, and a renewal pushes it out again.
        #expect(activity(await rt.handle(req("POST", "/v1/activities", token: lanToken, body: #"{"id":"d","title":"D","ttl":30}"#)))?.expiresAt
                == t0.addingTimeInterval(30))
        #expect(activity(await rt.handle(req("PUT", "/v1/activities/lan-d", token: lanToken, body: #"{"title":"D2"}"#)))?.expiresAt == ceiling)
        // The loopback API is unchanged: a script on this Mac can still put up a pill that stays.
        let loopback = local(b)
        #expect(activity(await loopback.handle(req("POST", "/v1/activities", token: apiToken, body: #"{"id":"e","title":"E"}"#)))?.expiresAt == nil)
    }

    @Test func notificationsAndTimersAreLimitedToo() async throws {
        let b = FakeBackend(now: t0)
        let rt = lan(b)
        let n = activity(await rt.handle(req("POST", "/v1/notify", token: lanToken,
                                             body: #"{"title":"Hi","icon":"file:///etc/secret.png","priority":"critical"}"#)))
        #expect(n?.id.hasPrefix("lan-") == true)
        #expect(n?.icon == .symbol("bell.fill"))
        #expect(n?.priority == .high)
        _ = try await b.timerCommand(.start(seconds: 600, title: "Mac timer", id: "tea"))
        let r = await rt.handle(req("POST", "/v1/timer", token: lanToken, body: #"{"seconds":60,"id":"tea"}"#))
        #expect(r.status == 201)
        #expect((try? APIJSON.decoder.decode(TimerItem.self, from: r.body))?.id == "lan-tea")
        #expect(await b.timers.ordered.map(\.id).sorted() == ["lan-tea", "tea"])
    }

    @Test func loopbackScopeIsUnchanged() async {
        let b = FakeBackend(now: t0)
        let body = #"{"id":"deploy","title":"Deploy","url":"https://example.com","priority":"critical","icon":"file:///tmp/x.png"}"#
        let a = activity(await local(b).handle(HTTPRequest(method: "POST", path: "/v1/activities",
                                                          headers: ["Authorization": "Bearer \(apiToken)"], body: Data(body.utf8))))
        #expect(a?.id == "deploy")
        #expect(a?.url != nil)
        #expect(a?.priority == .critical)
        #expect(a?.icon == .file("/tmp/x.png"))
    }

    @Test func eachListenerTakesOnlyItsOwnToken() async {
        let b = FakeBackend(now: t0)
        let notify = #"{"title":"x"}"#
        #expect(await lan(b).handle(req("POST", "/v1/notify", token: apiToken, body: notify)).status == 401)
        #expect(await lan(b).handle(req("POST", "/v1/notify", token: lanToken, body: notify)).status == 201)
        let loopback = { (token: String) in
            HTTPRequest(method: "POST", path: "/v1/notify", headers: ["Authorization": "Bearer \(token)"], body: Data(notify.utf8))
        }
        #expect(await local(b).handle(loopback(lanToken)).status == 401)
        #expect(await local(b).handle(loopback(apiToken)).status == 201)
        // A missing or wrong token is a 401 even on a refused route, so it says nothing about routes.
        #expect(await lan(b).handle(req("GET", "/v1/state", token: apiToken)).status == 401)
    }

    @Test func preflightNeedsOnlyTheHead() {
        let rt = lan(FakeBackend(now: t0))
        #expect(rt.preflight(req("GET", "/v1/health", token: nil)) == nil)
        #expect(rt.preflight(req("POST", "/v1/notify", token: nil))?.status == 401)
        // The refusal says where the bridge's token is, by the Settings page's current name.
        let refusal = String(decoding: rt.preflight(req("POST", "/v1/notify", token: nil))?.body ?? Data(), as: UTF8.self)
        #expect(refusal.contains("Settings → \(SettingsPage.advanced.title) → iPhone bridge"), "\(refusal)")
        #expect(rt.preflight(req("POST", "/v1/notify", token: lanToken)) == nil)
        #expect(rt.preflight(req("POST", "/v1/media", token: lanToken))?.status == 403)
        var browser = req("POST", "/v1/notify", token: lanToken)
        browser.headers["origin"] = "https://evil.example"
        #expect(rt.preflight(browser)?.status == 403)
    }
}

@Suite struct HTTPHeadTests {
    @Test func headArrivesBeforeTheBody() throws {
        let head = "POST /v1/notify HTTP/1.1\r\nAuthorization: Bearer x\r\nContent-Length: 10\r\n\r\n"
        guard case .head(let h) = HTTPParser.parseHead(Data((head + "12345").utf8)) else { Issue.record("no head"); return }
        #expect(h.request.path == "/v1/notify")
        #expect(h.request.headers["authorization"] == "Bearer x")
        #expect(h.request.body.isEmpty)
        #expect(h.bodyLength == 10)
        #expect(h.request(from: Data((head + "12345").utf8)) == nil)
        #expect(h.request(from: Data((head + "1234567890").utf8)).map { String(decoding: $0.body, as: UTF8.self) } == "1234567890")
        #expect(HTTPParser.parseHead(Data("POST /v1/notify HTTP/1.1\r\nContent-".utf8)) == .incomplete)
    }

    @Test func parseStillLimitsTheBody() {
        let raw = "POST / HTTP/1.1\r\nContent-Length: \(HTTPParser.maxBodyBytes + 1)\r\n\r\n"
        #expect(HTTPParser.parse(Data(raw.utf8)) == .invalid(status: 413, reason: "body too large"))
        guard case .head(let h) = HTTPParser.parseHead(Data(raw.utf8)) else { Issue.record("no head"); return }
        #expect(h.bodyLength == HTTPParser.maxBodyBytes + 1)
    }
}

@Suite struct ConnectionTallyTests {
    @Test func limitsEachClientAndTheListener() {
        var t = ConnectionTally()
        func admit(_ client: String) -> ConnectionTally.Verdict { t.admit(client, limit: 3, perClient: 2) }
        #expect([admit("a"), admit("a"), admit("a")] == [.admitted, .admitted, .clientFull])
        #expect([admit("b"), admit("c")] == [.admitted, .full])
        // Refusals aren't counted.
        #expect(t.total == 3 && t.count(for: "a") == 2 && t.count(for: "c") == 0)
        t.release("a")
        #expect(t.count(for: "a") == 1)
        #expect(admit("c") == .admitted)
        // Releasing a client with nothing open changes nothing.
        t.release("d")
        #expect(t.total == 3)
        for client in ["a", "b", "c"] { t.release(client) }
        #expect(t.total == 0 && t.count(for: "a") == 0)
    }

    @Test func noLimitsStillCounts() {
        var t = ConnectionTally()
        for _ in 0..<100 { #expect(t.admit("a", limit: nil, perClient: nil) == .admitted) }
        #expect(t.total == 100 && t.count(for: "a") == 100)
        #expect(t.admit("a", limit: nil, perClient: 100) == .clientFull)
        #expect(t.admit("b", limit: 100, perClient: nil) == .full)
    }
}

@Suite struct LANTokenFileTests {
    @Test func sitsBesideTheDiscoveryFileAndReadsBack() throws {
        #expect(CasementPaths.lanTokenFile.lastPathComponent == "lan.json")
        #expect(CasementPaths.lanTokenFile.deletingLastPathComponent() == CasementPaths.apiDiscoveryFile.deletingLastPathComponent())
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("casement-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("lan.json")
        #expect(LANTokenFile.read(from: url) == nil)
        try Data(#"{"token":"abc"}"#.utf8).write(to: url)
        #expect(LANTokenFile.read(from: url) == "abc")
        try Data("not json".utf8).write(to: url)
        #expect(LANTokenFile.read(from: url) == nil)
    }
}
