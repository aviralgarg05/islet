import Foundation
import Testing
@testable import IsletCore

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
        // Focus keeps its fixed id: the iPhone's Focus is the Mac's Focus pill.
        #expect(await b.center.activities["focus"]?.title == "Work")
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
        // Islet's own and the API's activities are out of reach: the id stays under lan-.
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
