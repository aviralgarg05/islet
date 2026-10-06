import Foundation
import Testing
@testable import CasementCore

@Suite struct TimerRouterTests {
    func request(_ method: String, _ path: String, body: String? = nil, token: String? = "secret-token") -> HTTPRequest {
        var headers: [String: String] = [:]
        if let token { headers["Authorization"] = "Bearer \(token)" }
        return HTTPRequest(method: method, path: path, headers: headers, body: Data((body ?? "").utf8))
    }

    func router(_ b: FakeBackend) -> APIRouter {
        APIRouter(token: "secret-token", version: "1.0-test", backend: b, clock: { t0 })
    }

    func timer(_ r: HTTPResponse) throws -> TimerItem { try APIJSON.decoder.decode(TimerItem.self, from: r.body) }

    @Test func createFromNaturalLanguage() async throws {
        let rt = router(FakeBackend(now: t0))
        let tea = await rt.handle(request("POST", "/v1/timer", body: #"{"in":"tea 4m"}"#))
        #expect(tea.status == 201)
        #expect(try timer(tea).title == "Tea")
        #expect(try timer(tea).endsAt == t0.addingTimeInterval(240))
        #expect(try timer(tea).id == "timer-1")

        let pizza = await rt.handle(request("POST", "/v1/timer", body: #"{"in":"in 20 minutes to take the pizza out","title":"Pizza"}"#))
        #expect(try timer(pizza).title == "Pizza")
        #expect(try timer(pizza).duration == 1200)

        let plural = await rt.handle(request("POST", "/v1/timers", body: #"{"seconds":90,"id":"eggs"}"#))
        #expect(plural.status == 201)
        #expect(try timer(plural).id == "eggs")
    }

    @Test func createErrorsAreReadable() async {
        let rt = router(FakeBackend(now: t0))
        let nonsense = await rt.handle(request("POST", "/v1/timer", body: #"{"in":"whenever"}"#))
        #expect(nonsense.status == 422)
        #expect(String(decoding: nonsense.body, as: UTF8.self).contains("can't find a duration"))
        let empty = await rt.handle(request("POST", "/v1/timer", body: "{}"))
        #expect(empty.status == 422)
        #expect(String(decoding: empty.body, as: UTF8.self).contains("'seconds' or 'in'"))
        #expect(await rt.handle(request("POST", "/v1/timer", body: #"{"seconds":90000}"#)).status == 422)
        #expect(await rt.handle(request("POST", "/v1/timer", body: #"{"in":"25 hours"}"#)).status == 422)
        #expect(await rt.handle(request("POST", "/v1/timer", body: #"{"seconds":60,"id":"pomodoro"}"#)).status == 422)
    }

    @Test func listAndControl() async throws {
        let b = FakeBackend(now: t0)
        let rt = router(b)
        _ = await rt.handle(request("POST", "/v1/timer", body: #"{"seconds":300,"title":"Tea"}"#))
        _ = await rt.handle(request("POST", "/v1/timer", body: #"{"seconds":1200,"title":"Pizza"}"#))

        let list = await rt.handle(request("GET", "/v1/timers"))
        #expect(list.status == 200)
        #expect(try APIJSON.decoder.decode([TimerItem].self, from: list.body).map(\.title) == ["Tea", "Pizza"])

        let paused = await rt.handle(request("PATCH", "/v1/timers/timer-1", body: #"{"action":"pause"}"#))
        #expect(paused.status == 200)
        #expect(try timer(paused).status == .paused)
        #expect(try timer(paused).remaining == 300)
        #expect(try await timer(rt.handle(request("PATCH", "/v1/timers/1", body: #"{"action":"resume"}"#))).status == .running)
        #expect(try await timer(rt.handle(request("PATCH", "/v1/timers/timer-1", body: #"{"action":"add","seconds":60}"#))).endsAt == t0.addingTimeInterval(360))
        #expect(try await timer(rt.handle(request("PATCH", "/v1/timers/timer-1", body: #"{"action":"add","in":"2m"}"#))).endsAt == t0.addingTimeInterval(480))
        #expect(try await timer(rt.handle(request("POST", "/v1/timers/pizza", body: #"{"action":"restart"}"#))).endsAt == t0.addingTimeInterval(1200))
        #expect(try await timer(rt.handle(request("PATCH", "/v1/timers/timer-1", body: #"{"action":"snooze"}"#))).endsAt == t0.addingTimeInterval(780))

        // Without an id: the newest timer.
        let newest = await rt.handle(request("PATCH", "/v1/timers", body: #"{"action":"pause"}"#))
        #expect(try timer(newest).title == "Pizza")

        #expect(await rt.handle(request("PATCH", "/v1/timers/timer-1", body: #"{"action":"stop"}"#)).status == 204)
        #expect(await rt.handle(request("PATCH", "/v1/timers/timer-1", body: #"{"action":"stop"}"#)).status == 404)
        #expect(await rt.handle(request("DELETE", "/v1/timers/timer-2")).status == 204)
        #expect(await rt.handle(request("PATCH", "/v1/timers", body: #"{"action":"stop"}"#)).status == 404)
        #expect(await b.timers.timers.isEmpty)
    }

    @Test func titleWithASlashIsOneSegment() async throws {
        let rt = router(FakeBackend(now: t0))
        _ = await rt.handle(request("POST", "/v1/timer", body: #"{"seconds":300,"title":"Wash/dry"}"#))
        let paused = await rt.handle(request("PATCH", "/v1/timers/Wash%2Fdry", body: #"{"action":"pause"}"#))
        #expect(paused.status == 200)
        #expect(try timer(paused).status == .paused)
    }

    @Test func controlErrors() async {
        let rt = router(FakeBackend(now: t0))
        _ = await rt.handle(request("POST", "/v1/timer", body: #"{"seconds":300}"#))
        #expect(await rt.handle(request("PATCH", "/v1/timers/timer-1", body: #"{"action":"explode"}"#)).status == 422)
        #expect(await rt.handle(request("PATCH", "/v1/timers/timer-1")).status == 422)
        #expect(await rt.handle(request("PATCH", "/v1/timers/timer-1", body: #"{"action":"add","seconds":-5}"#)).status == 422)
        #expect(await rt.handle(request("PATCH", "/v1/timers/nope", body: #"{"action":"pause"}"#)).status == 404)
        #expect(await rt.handle(request("DELETE", "/v1/timers")).status == 405)
        #expect(await rt.handle(request("GET", "/v1/pomodoro")).status == 405)
    }

    @Test func pomodoro() async throws {
        let b = FakeBackend(now: t0)
        let rt = router(b)
        let started = await rt.handle(request("POST", "/v1/pomodoro", body: #"{"action":"start"}"#))
        #expect(started.status == 201)
        #expect(try timer(started).id == "pomodoro")
        #expect(try timer(started).phase == .focus)
        #expect(try timer(started).endsAt == t0.addingTimeInterval(1500))
        #expect(await rt.handle(request("POST", "/v1/pomodoro", body: #"{"action":"stop"}"#)).status == 204)
        #expect(await rt.handle(request("POST", "/v1/pomodoro", body: #"{"action":"toggle"}"#)).status == 201)
        #expect(await rt.handle(request("POST", "/v1/pomodoro", body: #"{"action":"toggle"}"#)).status == 204)
        #expect(await rt.handle(request("POST", "/v1/pomodoro", body: #"{"action":"later"}"#)).status == 422)
        #expect(await b.timers.timers.isEmpty)
    }

    @Test func timersNeedTheToken() async {
        let rt = router(FakeBackend(now: t0))
        #expect(await rt.handle(request("GET", "/v1/timers", token: nil)).status == 401)
        #expect(await rt.handle(request("POST", "/v1/pomodoro", body: #"{"action":"start"}"#, token: "wrong")).status == 401)
    }
}

@Suite struct TimerURLTests {
    func parse(_ s: String) throws -> URLCommand { try URLCommand.parse(URL(string: s)!) }

    @Test func startWithIn() throws {
        #expect(try parse("casement://timer?in=20m&title=Pizza") == .timer(seconds: 1200, title: "Pizza"))
        #expect(try parse("casement://timer?in=tea%204m") == .timer(seconds: 240, title: "Tea"))
        #expect(try parse("casement://timer?in=1h%2030m") == .timer(seconds: 5400, title: nil))
        #expect(try parse("casement://timer?in=25") == .timer(seconds: 1500, title: nil))
        #expect(try parse("casement://timer?action=start&in=5m") == .timer(seconds: 300, title: nil))
        // seconds= and minutes= still work, and win over in=.
        #expect(try parse("casement://timer?seconds=300&in=1h") == .timer(seconds: 300, title: nil))
        #expect(try parse("casement://timer?minutes=5") == .timer(seconds: 300, title: nil))
        #expect(throws: URLCommand.ParseError.invalid("in", "whenever")) { try parse("casement://timer?in=whenever") }
        #expect(throws: URLCommand.ParseError.invalid("in", "30 hours")) { try parse("casement://timer?in=30%20hours") }
        #expect(throws: URLCommand.ParseError.missing("seconds")) { try parse("casement://timer") }
    }

    @Test func controls() throws {
        #expect(try parse("casement://timer?action=pause&id=timer-1") == .timerCommand(.control(.pause, id: "timer-1", seconds: nil)))
        #expect(try parse("casement://timer?action=STOP") == .timerCommand(.control(.stop, id: nil, seconds: nil)))
        #expect(try parse("casement://timer?action=stop&id=") == .timerCommand(.control(.stop, id: nil, seconds: nil)))
        #expect(try parse("casement://timer?action=add&id=tea&in=1m") == .timerCommand(.control(.add, id: "tea", seconds: 60)))
        #expect(try parse("casement://timer?action=snooze&seconds=120") == .timerCommand(.control(.snooze, id: nil, seconds: 120)))
        #expect(throws: URLCommand.ParseError.invalid("action", "explode")) { try parse("casement://timer?action=explode") }
    }

    @Test func pomodoro() throws {
        #expect(try parse("casement://pomodoro?action=start") == .timerCommand(.pomodoro(.start)))
        #expect(try parse("casement://pomodoro?action=stop") == .timerCommand(.pomodoro(.stop)))
        #expect(try parse("casement://pomodoro/toggle") == .timerCommand(.pomodoro(.toggle)))
        #expect(try parse("casement://pomodoro") == .timerCommand(.pomodoro(.start)))
        #expect(throws: URLCommand.ParseError.invalid("action", "later")) { try parse("casement://pomodoro?action=later") }
    }
}
