import Foundation
import Testing
@testable import CasementCore
@testable import CasementSystem

/// Answers the tools' requests without the network. Replies are found by the request's
/// Authorization header (or its host for keyless requests), so tests running at once don't meet.
final class FakeWeb: URLProtocol {
    struct Reply {
        var status = 200
        var body = "{}"
        var headers: [String: String] = ["content-type": "application/json"]
        var fail: URLError.Code?
    }

    private static let lock = NSLock()
    private static var replies: [String: [Reply]] = [:]
    private static var seen: [String: [URLRequest]] = [:]

    static func script(_ key: String, _ list: [Reply]) { lock.withLock { replies[key] = list } }
    static func requests(_ key: String) -> [URLRequest] { lock.withLock { seen[key] ?? [] } }

    static func key(of r: URLRequest) -> String {
        r.value(forHTTPHeaderField: "Authorization")?.replacingOccurrences(of: "Bearer ", with: "")
            ?? r.value(forHTTPHeaderField: "X-Shopify-Access-Token") ?? r.url?.host ?? ""
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let key = Self.key(of: request)
        let reply: Reply? = Self.lock.withLock {
            Self.seen[key, default: []].append(request)
            guard var list = Self.replies[key], !list.isEmpty else { return nil }
            let first = list.removeFirst()
            Self.replies[key] = list.isEmpty ? [first] : list
            return first
        }
        guard let reply else {
            client?.urlProtocol(self, didFailWithError: URLError(.cannotConnectToHost))
            return
        }
        if let code = reply.fail {
            client?.urlProtocol(self, didFailWithError: URLError(code))
            return
        }
        let response = HTTPURLResponse(url: request.url!, statusCode: reply.status, httpVersion: "HTTP/1.1", headerFields: reply.headers)!
        if (300..<400).contains(reply.status), let location = reply.headers["Location"], let to = URL(string: location) {
            client?.urlProtocol(self, wasRedirectedTo: URLRequest(url: to), redirectResponse: response)
        }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(reply.body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

@Suite struct ToolsServiceTests {
    let service = ToolsService(protocolClasses: [FakeWeb.self], timeout: 5)
    let since = Date(timeIntervalSince1970: 1_790_809_200)
    let now = Date(timeIntervalSince1970: 1_790_850_000)

    @Test func salesFollowPagesAndAddThemUp() async {
        let key = "stripe-pages-0123456789"
        FakeWeb.script(key, [
            FakeWeb.Reply(body: #"{"has_more":true,"data":[{"id":"ch_a","paid":true,"status":"succeeded","amount_captured":1000,"amount_refunded":0,"currency":"gbp"}]}"#),
            FakeWeb.Reply(body: #"{"has_more":false,"data":[{"id":"ch_b","paid":true,"status":"succeeded","amount_captured":250,"amount_refunded":0,"currency":"gbp"}]}"#),
        ])
        let result = await service.sales(.stripe, key: key, shop: nil, since: since, now: now)
        #expect(result.problem == nil)
        #expect(result.figures == SalesFigures(amounts: ["GBP": 1250], orders: 2))
        #expect(result.updatedAt == now)
        let seen = FakeWeb.requests(key)
        #expect(seen.count == 2)
        #expect(seen.last?.url?.query?.contains("starting_after=ch_a") == true)
        #expect(seen.allSatisfy { $0.httpShouldHandleCookies == false })
    }

    @Test func aTurnedDownKeyIsAProblemNotAZero() async {
        let key = "polar-denied-0123456789"
        FakeWeb.script(key, [FakeWeb.Reply(status: 401, body: #"{"detail":"Unauthorized"}"#)])
        let result = await service.sales(.polar, key: key, shop: nil, since: since, now: now)
        #expect(result.problem == .rejectedKey)
        #expect(result.figures.isEmpty)
    }

    @Test func pagesStopAtTheLimit() async {
        let key = "dodo-many-0123456789"
        let item = #"{"payment_id":"p","total_amount":100,"currency":"USD","status":"succeeded"}"#
        let full = "{\"items\":[" + Array(repeating: item, count: 100).joined(separator: ",") + "]}"
        FakeWeb.script(key, [FakeWeb.Reply(body: full)])
        let result = await service.sales(.dodo, key: key, shop: nil, since: since, now: now)
        #expect(FakeWeb.requests(key).count == SalesAPI.maxPages)
        #expect(result.figures.orders == 100 * SalesAPI.maxPages)
        #expect(FakeWeb.requests(key).last?.url?.query?.contains("page_number=\(SalesAPI.maxPages - 1)") == true)
    }

    @Test func nothingGoesToAHostTheToolDidntName() async {
        let r = WebRequest(url: URL(string: "https://example.com/steal")!, headers: ["Authorization": "Bearer never-sent-0123"])
        await #expect(throws: WebProblem.self) { _ = try await service.send(r, hosts: ["api.stripe.com"]) }
        #expect(FakeWeb.requests("never-sent-0123").isEmpty)
    }

    @Test func redirectsAreNotFollowed() async throws {
        let key = "redirect-0123456789"
        FakeWeb.script(key, [FakeWeb.Reply(status: 302, headers: ["Location": "https://example.com/elsewhere"])])
        let r = OpenRouterUsage.request(key: key)
        let reply = try await service.send(r, hosts: [OpenRouterUsage.host])
        #expect(reply.status == 302)
        #expect(FakeWeb.requests(key).count == 1)
        #expect(FakeWeb.requests(key).first?.url?.host == "openrouter.ai")
    }

    @Test func anOversizedReplyIsRefusedWhileItArrives() async throws {
        let small = ToolsService(protocolClasses: [FakeWeb.self], timeout: 5, maxReply: 1024)
        let big = "{\"pad\":\"" + String(repeating: "x", count: 4096) + "\"}"
        let key = "oversized-0123456789"
        FakeWeb.script(key, [FakeWeb.Reply(body: big)])
        await #expect(throws: WebProblem.unreadable) { _ = try await small.send(OpenRouterUsage.request(key: key), hosts: [OpenRouterUsage.host]) }
        // Saying so up front is enough.
        let declared = "declared-0123456789"
        FakeWeb.script(declared, [FakeWeb.Reply(body: big, headers: ["content-type": "application/json", "Content-Length": "4108"])])
        await #expect(throws: WebProblem.unreadable) { _ = try await small.send(OpenRouterUsage.request(key: declared), hosts: [OpenRouterUsage.host]) }
        // A reply under the cap arrives whole.
        let fine = "fine-0123456789"
        FakeWeb.script(fine, [FakeWeb.Reply(body: #"{"data":{"usage_daily":1}}"#)])
        let reply = try await small.send(OpenRouterUsage.request(key: fine), hosts: [OpenRouterUsage.host])
        #expect(String(decoding: reply.data, as: UTF8.self) == #"{"data":{"usage_daily":1}}"#)
        small.invalidate()
    }

    @Test func noConnectionIsUnreachable() async {
        let key = "offline-0123456789"
        FakeWeb.script(key, [FakeWeb.Reply(fail: .notConnectedToInternet)])
        let result = await service.openRouter(key: key, now: now)
        #expect(result == .failure(.unreachable))
    }

    @Test func usageSources() async throws {
        let key = "openrouter-ok-0123456789"
        FakeWeb.script(key, [FakeWeb.Reply(body: #"{"data":{"limit":null,"usage_daily":2,"usage_monthly":9}}"#)])
        let card = try await service.openRouter(key: key, now: now).get()
        #expect(card.headline == "$2.00 today")

        let token = "copilot-ok-0123456789"
        FakeWeb.script(token, [
            FakeWeb.Reply(body: #"{"login":"octo-cat"}"#),
            FakeWeb.Reply(body: #"{"usageItems":[{"product":"Copilot","grossQuantity":12}]}"#),
        ])
        let login = try await service.copilotLogin(token: token).get()
        #expect(login == "octo-cat")
        #expect(try await service.copilot(token: token, login: login, now: now).get() == 12)
        #expect(FakeWeb.requests(token).last?.url?.path == "/users/octo-cat/settings/billing/premium_request/usage")
    }

    @Test func stocksSayWhyASymbolIsUnknown() async {
        // Keyless requests are found by host; this is the only test that asks for prices.
        FakeWeb.script(StocksAPI.host, [
            FakeWeb.Reply(status: 404, body: #"{"chart":{"result":null,"error":{"code":"Not Found","description":"No data found, symbol may be delisted"}}}"#),
        ])
        let result = await service.quote("NOPE")
        #expect(result == .failure(.message("No data found, symbol may be delisted")))
        #expect(await service.quote("a b") == .failure(.notFound))
    }
}
