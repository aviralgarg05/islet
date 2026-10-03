import Foundation
import IsletCore
import Testing
@testable import IsletSystem

/// Answers lrclib.net and open-meteo.com requests inside the test process. Replies are keyed by
/// the song title or place in the query, so tests can run in parallel.
final class MockTools: URLProtocol {
    struct Reply {
        var status = 200
        var body = ""
        /// Fail as if offline.
        var offline = false
        /// Where a 3xx reply points, so a test can check the redirect isn't followed.
        var location: String?
    }

    private static let lock = NSLock()
    private static var replies: [String: [String: Reply]] = [:]
    private static var seen: [String: [URLRequest]] = [:]

    /// `replies` by URL path ("/api/get", "/api/search", "/v1/forecast").
    static func script(_ key: String, _ byPath: [String: Reply]) { lock.withLock { replies[key] = byPath } }
    static func requests(_ key: String) -> [URLRequest] { lock.withLock { seen[key] ?? [] } }

    static func key(of r: URLRequest) -> String {
        let items = r.url.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false)?.queryItems } ?? []
        return items.first { ["track_name", "name", "latitude"].contains($0.name) }?.value ?? ""
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let key = Self.key(of: request)
        let reply: Reply? = Self.lock.withLock {
            Self.seen[key, default: []].append(request)
            return Self.replies[key]?[request.url?.path ?? ""]
        }
        guard let reply, !reply.offline else {
            client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
            return
        }
        var headers = ["content-type": "application/json"]
        if let location = reply.location { headers["Location"] = location }
        let response = HTTPURLResponse(url: request.url!, statusCode: reply.status, httpVersion: "HTTP/1.1",
                                       headerFields: headers)!
        if (300..<400).contains(reply.status), let location = reply.location, let to = URL(string: location) {
            client?.urlProtocol(self, wasRedirectedTo: URLRequest(url: to), redirectResponse: response)
        }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(reply.body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

@Suite struct LyricsServiceTests {
    func service() -> (LyricsService, URL) {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("islet-lyrics-service-\(UUID().uuidString)")
        return (LyricsService(cache: LyricsCache(directory: dir), version: "test", protocolClasses: [MockTools.self]), dir)
    }

    func lookUp(_ s: LyricsService, _ q: LyricsQuery) async -> Result<LyricsLookup, Error> {
        await withCheckedContinuation { done in s.lookUp(q) { done.resume(returning: $0) } }
    }

    @Test func exactMatchIsUsedAndRemembered() async throws {
        let (s, dir) = service()
        defer { try? FileManager.default.removeItem(at: dir) }
        let title = "Exact \(UUID().uuidString)"
        MockTools.script(title, ["/api/get": .init(body: #"{"id":1,"syncedLyrics":"[00:01.00] Hello\n[00:02.00] There"}"#)])
        let q = LyricsQuery(title: title, artist: "Band", album: "LP", duration: 200)
        guard case .success(.found(let lyrics)) = await lookUp(s, q) else { Issue.record("no lyrics"); return }
        #expect(lyrics.lines.map(\.text) == ["Hello", "There"])
        // Asked once, with the app's name, and only the song's details.
        let sent = MockTools.requests(title)
        #expect(sent.count == 1)
        #expect(sent[0].value(forHTTPHeaderField: "User-Agent")?.hasPrefix("Islet test") == true)
        #expect(sent[0].value(forHTTPHeaderField: "Cookie") == nil)
        // The second time comes from the cache.
        guard case .success(.found) = await lookUp(s, q) else { Issue.record("not cached"); return }
        #expect(MockTools.requests(title).count == 1)
    }

    @Test func fallsBackToSearchThenRemembersAMiss() async throws {
        let (s, dir) = service()
        defer { try? FileManager.default.removeItem(at: dir) }
        let found = "Search \(UUID().uuidString)"
        MockTools.script(found, [
            "/api/get": .init(status: 404, body: #"{"code":404}"#),
            "/api/search": .init(body: #"[{"id":7,"trackName":"x","duration":201,"syncedLyrics":"[00:03.00] Found it"}]"#),
        ])
        guard case .success(.found(let lyrics)) = await lookUp(s, LyricsQuery(title: found, artist: "Band", duration: 200)) else {
            Issue.record("search not used")
            return
        }
        #expect(lyrics.lines.first?.text == "Found it")

        let missing = "Missing \(UUID().uuidString)"
        MockTools.script(missing, ["/api/get": .init(status: 404), "/api/search": .init(body: "[]")])
        let q = LyricsQuery(title: missing, artist: "Band", duration: 200)
        guard case .success(.missing) = await lookUp(s, q) else { Issue.record("expected a miss"); return }
        #expect(s.cached(q) == .missing)
    }

    /// A redirect could carry the song's title to a third party, so it isn't followed.
    @Test func redirectsAreNotFollowed() async throws {
        let (s, dir) = service()
        defer { try? FileManager.default.removeItem(at: dir) }
        let title = "Redirect \(UUID().uuidString)"
        let elsewhere = "https://example.com/steal?track_name=\(title.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")"
        MockTools.script(title, ["/api/get": .init(status: 302, location: elsewhere)])
        let q = LyricsQuery(title: title, artist: "Band", duration: 200)
        guard case .failure = await lookUp(s, q) else { Issue.record("expected a failure"); return }
        let sent = MockTools.requests(title)
        #expect(sent.count == 1)
        #expect(sent.first?.url?.host == "lrclib.net")
        #expect(s.cached(q) == nil)
    }

    @Test func aNetworkFailureIsNotRemembered() async throws {
        let (s, dir) = service()
        defer { try? FileManager.default.removeItem(at: dir) }
        let title = "Offline \(UUID().uuidString)"
        MockTools.script(title, ["/api/get": .init(offline: true)])
        let q = LyricsQuery(title: title, artist: "Band", duration: 200)
        guard case .failure = await lookUp(s, q) else { Issue.record("expected a failure"); return }
        #expect(s.cached(q) == nil)
    }
}

@Suite struct WeatherServiceTests {
    @Test func fetchesAForecastForARoundedPosition() async throws {
        let s = WeatherService(version: "test", protocolClasses: [MockTools.self])
        MockTools.script("12.35", ["/v1/forecast": .init(body: #"""
        {"current":{"temperature_2m":21.5,"weather_code":2,"is_day":0},
         "daily":{"time":["2026-10-01"],"weather_code":[2],"temperature_2m_max":[24],"temperature_2m_min":[15]}}
        """#)])
        let result: Result<WeatherReport, Error> = await withCheckedContinuation { done in
            s.forecast(latitude: 12.3456, longitude: 45.6789) { done.resume(returning: $0) }
        }
        let report = try result.get()
        #expect(report.current.temperature == 21.5)
        #expect(!report.current.isDay)
        #expect(report.days.count == 1)
        let url = try #require(MockTools.requests("12.35").first?.url)
        #expect(url.absoluteString.contains("longitude=45.68"))
        #expect(!url.absoluteString.contains("12.3456"))
    }

    /// A redirect could carry a rounded position or a typed place to a third party, so it isn't
    /// followed.
    @Test func redirectsAreNotFollowed() async throws {
        let s = WeatherService(version: "test", protocolClasses: [MockTools.self])
        MockTools.script("33.33", ["/v1/forecast": .init(status: 302, location: "https://example.com/steal?latitude=33.33")])
        let result: Result<WeatherReport, Error> = await withCheckedContinuation { done in
            s.forecast(latitude: 33.3333, longitude: 44.4444) { done.resume(returning: $0) }
        }
        #expect((try? result.get()) == nil)
        let sent = MockTools.requests("33.33")
        #expect(sent.count == 1)
        #expect(sent.first?.url?.host == OpenMeteo.forecastHost)
    }

    @Test func findsPlacesAndReportsFailures() async throws {
        let s = WeatherService(version: "test", protocolClasses: [MockTools.self])
        let name = "Town \(UUID().uuidString.prefix(8))"
        MockTools.script(name, ["/v1/search": .init(body: #"{"results":[{"name":"Town","latitude":1,"longitude":2,"country":"Somewhere"}]}"#)])
        let places: Result<[WeatherPlace], Error> = await withCheckedContinuation { done in
            s.places(named: name) { done.resume(returning: $0) }
        }
        #expect(try places.get().map(\.label) == ["Town, Somewhere"])
        let broken = "Broken \(UUID().uuidString.prefix(8))"
        MockTools.script(broken, ["/v1/search": .init(status: 500)])
        let failed: Result<[WeatherPlace], Error> = await withCheckedContinuation { done in
            s.places(named: broken) { done.resume(returning: $0) }
        }
        #expect(throws: (any Error).self) { try failed.get() }
    }
}

@Suite struct ShortcutsRunnerTests {
    @Test func usesMacOSsOwnTool() {
        #expect(ShortcutsRunner.tool.path == "/usr/bin/shortcuts")
    }
}
