import Foundation
import Testing
@testable import IsletCore

@Suite struct StocksTests {
    static let chart = """
    {"chart":{"result":[{"meta":{"currency":"USD","symbol":"^GSPC","shortName":"S&P 500","regularMarketPrice":6688.46,
      "chartPreviousClose":6661.21,"regularMarketTime":1790875646},
      "timestamp":[1,2,3,4],"indicators":{"quote":[{"close":[6664.0,null,6670.5,6688.46]}]}}],"error":null}}
    """

    @Test func symbolsAreTickersOnly() {
        #expect(StocksAPI.normalisedSymbol(" aapl ") == "AAPL")
        #expect(StocksAPI.normalisedSymbol("^gspc") == "^GSPC")
        #expect(StocksAPI.normalisedSymbol("eurusd=x") == "EURUSD=X")
        #expect(StocksAPI.normalisedSymbol("BRK.B") == "BRK.B")
        #expect(StocksAPI.normalisedSymbol("") == nil)
        #expect(StocksAPI.normalisedSymbol("AA PL") == nil)
        #expect(StocksAPI.normalisedSymbol("../../x") == nil)
        #expect(StocksAPI.normalisedSymbol("ÄPPLE") == nil)
        #expect(StocksAPI.normalisedSymbol(String(repeating: "A", count: 16)) == nil)
    }

    @Test func requestNeedsNoKeyAndEncodesTheSymbol() throws {
        let r = try #require(StocksAPI.request(symbol: "^gspc"))
        #expect(r.url.absoluteString == "https://query1.finance.yahoo.com/v8/finance/chart/%5EGSPC?range=1d&interval=5m")
        #expect(r.headers["Authorization"] == nil)
        #expect(r.isAllowed(hosts: [StocksAPI.host]))
        #expect(StocksAPI.request(symbol: "a/b") == nil)
    }

    @Test func parsesPriceChangeAndTheDaysLine() throws {
        let q = try StocksAPI.parse(Data(Self.chart.utf8))
        #expect(q.symbol == "^GSPC" && q.displayName == "S&P 500" && q.currency == "USD")
        #expect(q.price == 6688.46 && q.previousClose == 6661.21)
        #expect(q.closes == [6664.0, 6670.5, 6688.46])
        #expect(q.changeText == "+0.41%")
        #expect(q.time == Date(timeIntervalSince1970: 1_790_875_646))
        let down = StockQuote(symbol: "X", price: 99, previousClose: 100)
        #expect(down.changeText == "\u{2212}1.00%")
        #expect(StockQuote(symbol: "X", price: 1).changeText == nil)
        #expect(StockQuote(symbol: "X", price: 0.123456).priceText.hasSuffix("1235"))
    }

    @Test func anUnknownSymbolSaysWhy() {
        let json = #"{"chart":{"result":null,"error":{"code":"Not Found","description":"No data found, symbol may be delisted"}}}"#
        #expect(throws: WebProblem.message("No data found, symbol may be delisted")) { try StocksAPI.parse(Data(json.utf8)) }
        #expect(throws: WebProblem.unreadable) { try StocksAPI.parse(Data("{}".utf8)) }
    }

    @Test func sparklineFitsItsBox() {
        let pts = Sparkline.points([1, 3, 2], width: 100, height: 20)
        #expect(pts == [CGPoint(x: 0, y: 20), CGPoint(x: 50, y: 0), CGPoint(x: 100, y: 10)])
        #expect(Sparkline.points([5, 5], width: 10, height: 20).map(\.y) == [10, 10])
        #expect(Sparkline.points([1], width: 10, height: 10).isEmpty)
        #expect(Sparkline.points(Array(0..<500).map(Double.init), width: 10, height: 10, limit: 60).count == 60)
        // The previous close widens the scale and sits on it.
        let widened = Sparkline.points([2, 3], width: 10, height: 10, including: 1)
        #expect(widened.map(\.y) == [5, 0])
        #expect(Sparkline.y(of: 1, in: [2, 3], including: 1, height: 10) == 10)
    }

    @Test func pricesAreAskedForOnlyWhileThePageIsOpen() {
        let now = Date(timeIntervalSince1970: 1_790_000_000)
        #expect(StocksSchedule.nextRefresh(last: nil, pageOpen: false, hasSymbols: true, now: now) == nil)
        #expect(StocksSchedule.nextRefresh(last: nil, pageOpen: true, hasSymbols: true, now: now) == now)
        #expect(StocksSchedule.nextRefresh(last: now, pageOpen: true, hasSymbols: true, now: now) == now.addingTimeInterval(120))
        #expect(StocksSchedule.nextRefresh(last: nil, pageOpen: true, hasSymbols: false, now: now) == nil)
        #expect(StocksSchedule.isStale(now.addingTimeInterval(-60), now: now) && !StocksSchedule.isStale(now.addingTimeInterval(-59), now: now))
    }
}

@Suite struct ToolUsageTests {
    let now = Date(timeIntervalSince1970: 1_790_000_000)

    @Test func openRouterWithALimitShowsWhatIsLeft() throws {
        let json = """
        {"data":{"label":"islet","limit":50,"limit_remaining":8.9,"usage":41.1,"usage_daily":1.12,"usage_weekly":5,"usage_monthly":20,"is_free_tier":false}}
        """
        let card = try OpenRouterUsage.parse(Data(json.utf8), now: now)
        #expect(card.headline == "$8.90 left" && card.detail == "$1.12 today")
        #expect(abs((card.fraction ?? 0) - 0.822) < 0.001)
        #expect(card.source == .openRouter && card.updatedAt == now)
    }

    @Test func openRouterWithoutALimitShowsSpending() throws {
        let json = #"{"data":{"limit":null,"limit_remaining":null,"usage":3,"usage_daily":0.004,"usage_monthly":2.5,"is_free_tier":false}}"#
        let card = try OpenRouterUsage.parse(Data(json.utf8), now: now)
        #expect(card.headline == "$0.004 today" && card.detail == "$2.50 this month" && card.fraction == nil)
        let free = #"{"data":{"limit":null,"usage":0,"usage_daily":0,"is_free_tier":true,"free_model_daily_requests":{"used":12,"limit":50,"remaining":38}}}"#
        let f = try OpenRouterUsage.parse(Data(free.utf8), now: now)
        #expect(f.headline == "12 of 50 free requests" && f.fraction == 0.24)
        #expect(throws: WebProblem.message("No auth credentials found")) {
            try OpenRouterUsage.parse(Data(#"{"error":{"message":"No auth credentials found","code":401}}"#.utf8), now: now)
        }
    }

    @Test func openRouterRequestCarriesTheKeyInAHeader() {
        let key = "test-key-0123456789"
        let r = OpenRouterUsage.request(key: key)
        #expect(r.url.absoluteString == "https://openrouter.ai/api/v1/key")
        #expect(r.headers["Authorization"] == "Bearer \(key)")
        #expect(!OpenRouterUsage.looksLikeKey(key))
        #expect(OpenRouterUsage.looksLikeKey("sk-" + "or-" + String(repeating: "x", count: 24)))
    }

    @Test func ollamaShowsTheLoadedModelAndIsQuietWithNone() throws {
        let json = """
        {"models":[{"name":"llama3.2:latest","model":"llama3.2:latest","size":3400000000,"size_vram":3100000000,
                    "expires_at":"2026-09-21T14:17:20Z"}]}
        """
        let models = try OllamaUsage.parse(Data(json.utf8))
        #expect(models == [OllamaUsage.Model(name: "llama3.2:latest", bytes: 3_100_000_000,
                                             unloadsAt: Date(timeIntervalSince1970: 1_790_000_000 + 240))])
        let card = try #require(OllamaUsage.card(models, now: now))
        #expect(card.headline == "llama3.2 · 3.1 GB" && card.detail == "Unloads in 4 min" && card.fraction == nil)
        #expect(OllamaUsage.card([], now: now) == nil)
        let two = OllamaUsage.card(models + [OllamaUsage.Model(name: "qwen3:8b", bytes: 5_000_000_000)], now: now)
        #expect(two?.headline == "qwen3:8b · 5.0 GB" && two?.detail == "2 models, 8.1 GB")
        #expect(OllamaUsage.request.url.absoluteString == "http://127.0.0.1:11434/api/ps")
    }

    @Test func copilotCountsThisMonthsPremiumRequests() throws {
        let token = "test-token-0123456789"
        #expect(try CopilotUsage.login(from: Data(#"{"login":"octo-cat","id":1}"#.utf8)) == "octo-cat")
        #expect(throws: WebProblem.unreadable) { try CopilotUsage.login(from: Data(#"{"login":"../evil"}"#.utf8)) }
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        let r = try #require(CopilotUsage.usageRequest(login: "octo-cat", token: token, now: now, calendar: utc))
        #expect(r.url.absoluteString == "https://api.github.com/users/octo-cat/settings/billing/premium_request/usage?year=2026&month=9")
        #expect(r.headers["Authorization"] == "Bearer \(token)" && r.headers["X-GitHub-Api-Version"] == "2022-11-28")
        #expect(CopilotUsage.usageRequest(login: "a/b", token: token, now: now) == nil)
        let json = """
        {"timePeriod":{"year":2026,"month":9},"user":"octo-cat","usageItems":[
          {"product":"Copilot","sku":"Copilot Premium Request","model":"Claude Sonnet 4.5","grossQuantity":100,"discountQuantity":100,"netQuantity":0},
          {"product":"Copilot","sku":"Copilot Premium Request","model":"GPT-5","grossQuantity":42.0,"discountQuantity":42,"netQuantity":0},
          {"product":"Actions","sku":"minutes","grossQuantity":900}]}
        """
        #expect(try CopilotUsage.requestsUsed(Data(json.utf8)) == 142)
        let card = CopilotUsage.card(used: 142, plan: .pro, now: now)
        #expect(card.headline == "142 of 300" && card.detail == "premium requests this month")
        #expect(abs((card.fraction ?? 0) - 142.0 / 300) < 0.0001)
        #expect(CopilotUsage.card(used: 400, plan: .pro, now: now).fraction == 1)
    }

    @Test func eachSourceHasItsOwnFreshnessAndNoSignInIsRead() {
        #expect(ToolUsageSource.openRouter.keyAccount == "openrouter")
        #expect(ToolUsageSource.copilot.keyAccount == "github-copilot")
        #expect(ToolUsageSource.ollama.keyAccount == nil)
        let card = ToolUsageCard(source: .ollama, headline: "x", updatedAt: now)
        #expect(!card.isStale(now: now.addingTimeInterval(10)) && card.isStale(now: now.addingTimeInterval(15)))
        var s = IsletSettings()
        #expect(ToolUsageSource.allCases.allSatisfy { !$0.isOn(s) })
        s.ollamaUsageEnabled = true
        #expect(ToolUsageSource.ollama.isOn(s))
    }
}
