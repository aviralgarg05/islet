import Foundation
import Testing
@testable import IsletCore

@Suite struct SalesTests {
    /// Midnight on 1 October 2026 in London (23:00 UTC the day before).
    static let since = Date(timeIntervalSince1970: 1_790_809_200)
    static let key = "test-key-0123456789"

    static func query(_ r: WebRequest) -> [String: String] {
        let items = URLComponents(url: r.url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        return Dictionary(items.map { ($0.name, $0.value ?? "") }, uniquingKeysWith: { a, _ in a })
    }

    @Test func requestsGoOnlyToEachStoresHostWithTheKeyInAHeader() throws {
        for store in SalesStore.allCases {
            let r = try SalesAPI.request(store, key: Self.key, shop: "example", since: Self.since)
            #expect(r.isAllowed(hosts: SalesAPI.hosts(store, shop: "example")), "\(store)")
            #expect(!r.url.absoluteString.contains(Self.key), "\(store) puts the key in the URL")
            #expect(r.headers.values.contains { $0.contains(Self.key) }, "\(store)")
            #expect(r.method == (store == .shopify ? "POST" : "GET"))
            #expect(store.keyAccount == "sales.\(store.rawValue)")
        }
    }

    @Test func eachRequestAsksForToday() throws {
        let stripe = try SalesAPI.request(.stripe, key: Self.key, since: Self.since, cursor: .after("ch_9"))
        #expect(Self.query(stripe)["created[gte]"] == "1790809200")
        #expect(Self.query(stripe)["starting_after"] == "ch_9")
        #expect(stripe.url.absoluteString.contains("created%5Bgte%5D"))

        let shopify = try SalesAPI.request(.shopify, key: Self.key, shop: "Example.myshopify.com", since: Self.since, cursor: .after("abc"))
        #expect(shopify.url.absoluteString == "https://example.myshopify.com/admin/api/\(SalesAPI.shopifyVersion)/graphql.json")
        #expect(shopify.headers["X-Shopify-Access-Token"] == Self.key)
        let body = try #require(shopify.body.flatMap { try JSONSerialization.jsonObject(with: $0) as? [String: Any] })
        let variables = try #require(body["variables"] as? [String: Any])
        #expect(variables["q"] as? String == "created_at:>='2026-09-30T23:00:00Z'")
        #expect(variables["after"] as? String == "abc")

        #expect(Self.query(try SalesAPI.request(.gumroad, key: Self.key, since: Self.since))["after"] == "2026-09-29")
        let dodo = Self.query(try SalesAPI.request(.dodo, key: Self.key, since: Self.since, cursor: .page(2)))
        #expect(dodo["created_at_gte"] == "2026-09-30T23:00:00Z" && dodo["status"] == "succeeded" && dodo["page_number"] == "2")
        let polar = Self.query(try SalesAPI.request(.polar, key: Self.key, since: Self.since))
        #expect(polar["created_after"] == "2026-09-30T23:00:00Z" && polar["page"] == "1")
        let paddle = try SalesAPI.request(.paddle, key: Self.key, since: Self.since)
        #expect(paddle.url.host == "api.paddle.com" && Self.query(paddle)["status"] == "completed")
        // Paddle refuses a page larger than 30 transactions.
        #expect(Int(Self.query(paddle)["per_page"] ?? "") == 30)
        #expect(Self.query(paddle)["created_at[GTE]"] == "2026-09-30T23:00:00Z")
        let sandbox = try SalesAPI.request(.paddle, key: "pdl" + "_sdbx_" + "apikey_0123456789", since: Self.since)
        #expect(sandbox.url.host == "sandbox-api.paddle.com")
        #expect(Self.query(try SalesAPI.request(.lemonSqueezy, key: Self.key, since: Self.since, cursor: .page(3)))["page[number]"] == "3")
    }

    @Test func paddlesNextPageMustStayOnPaddle() throws {
        let next = URL(string: "https://api.paddle.com/transactions?after=txn_1")!
        #expect(try SalesAPI.request(.paddle, key: Self.key, since: Self.since, cursor: .url(next)).url == next)
        #expect(throws: WebProblem.self) {
            try SalesAPI.request(.paddle, key: Self.key, since: Self.since, cursor: .url(URL(string: "https://example.com/steal")!))
        }
    }

    @Test func shopifyAddressesAreOnlyShopifyStores() {
        #expect(SalesAPI.shopifyHost("example") == "example.myshopify.com")
        #expect(SalesAPI.shopifyHost(" https://My-Shop.myshopify.com/admin ") == "my-shop.myshopify.com")
        #expect(SalesAPI.shopifyHost("example.com") == nil)
        #expect(SalesAPI.shopifyHost("evil.com/.myshopify.com") == nil)
        #expect(SalesAPI.shopifyHost("a b") == nil)
        #expect(SalesAPI.shopifyHost("") == nil)
        #expect(SalesAPI.hosts(.shopify, shop: "nope.example") == [])
    }

    @Test func stripeCountsPaidChargesLessRefunds() throws {
        let json = """
        {"object":"list","has_more":true,"data":[
          {"id":"ch_1","paid":true,"status":"succeeded","amount":2000,"amount_captured":2000,"amount_refunded":500,"currency":"gbp"},
          {"id":"ch_2","paid":true,"status":"succeeded","amount":1000,"amount_captured":1000,"amount_refunded":1000,"currency":"gbp"},
          {"id":"ch_3","paid":false,"status":"failed","amount":9000,"amount_captured":0,"amount_refunded":0,"currency":"gbp"},
          {"id":"ch_4","paid":true,"status":"succeeded","amount":500,"amount_captured":500,"amount_refunded":0,"currency":"jpy"}]}
        """
        let page = try SalesAPI.parse(.stripe, data: Data(json.utf8), since: Self.since)
        #expect(page.figures == SalesFigures(amounts: ["GBP": 1500, "JPY": 500], orders: 2))
        #expect(page.next == .after("ch_4"))
    }

    /// Figures come from someone else's API, so nothing from one reaches `Int64(_:)`, whose
    /// precondition traps beyond its range.
    @Test func afigureNoShopCouldTakeIsClampedRatherThanTrapping() throws {
        let stripe = """
        {"object":"list","has_more":false,"data":[
          {"id":"ch_1","paid":true,"status":"succeeded","amount":1e300,"amount_captured":1e300,"amount_refunded":0,"currency":"gbp"}]}
        """
        let page = try SalesAPI.parse(.stripe, data: Data(stripe.utf8), since: Self.since)
        #expect(page.figures.orders == 1)
        #expect(page.figures.amounts["GBP"] == 9_000_000_000_000_000_000)
        // Two of them in the same currency: clamping each one only moved the trap into the sum,
        // which is pinned to the end of its range instead.
        let twice = """
        {"object":"list","has_more":false,"data":[
          {"id":"ch_1","paid":true,"status":"succeeded","amount":1e300,"amount_captured":1e300,"amount_refunded":0,"currency":"gbp"},
          {"id":"ch_2","paid":true,"status":"succeeded","amount":1e300,"amount_captured":1e300,"amount_refunded":0,"currency":"gbp"}]}
        """
        let both = try SalesAPI.parse(.stripe, data: Data(twice.utf8), since: Self.since)
        #expect(both.figures.orders == 2)
        #expect(both.figures.amounts["GBP"] == Int64.max)
        // And across pages, which add one page's figures into another's.
        var running = page.figures
        running.add(both.figures)
        #expect(running.amounts["GBP"] == Int64.max)
        // Gumroad and Paddle read their own fields the same way.
        let gumroad = #"{"success":true,"sales":[{"created_at":"2026-10-01T08:00:00Z","price":1e300,"currency":"usd"}]}"#
        #expect(try SalesAPI.parse(.gumroad, data: Data(gumroad.utf8), since: Self.since).figures.orders == 1)
        let paddle = """
        {"data":[{"created_at":"2026-10-01T08:00:00Z","currency_code":"USD","status":"completed",
          "details":{"totals":{"grand_total":1e300,"currency_code":"USD"}}}]}
        """
        #expect(try SalesAPI.parse(.paddle, data: Data(paddle.utf8), since: Self.since).figures.orders == 1)
    }

    @Test func shopifySkipsCancelledAndTestOrdersAndReadsDecimals() throws {
        let json = """
        {"data":{"orders":{"pageInfo":{"hasNextPage":false,"endCursor":"c1"},"nodes":[
          {"createdAt":"2026-10-01T08:00:00Z","cancelledAt":null,"test":false,"currentTotalPriceSet":{"shopMoney":{"amount":"12.50","currencyCode":"GBP"}}},
          {"createdAt":"2026-10-01T09:00:00Z","cancelledAt":"2026-10-01T09:30:00Z","test":false,"currentTotalPriceSet":{"shopMoney":{"amount":"99.00","currencyCode":"GBP"}}},
          {"createdAt":"2026-10-01T10:00:00Z","cancelledAt":null,"test":true,"currentTotalPriceSet":{"shopMoney":{"amount":"5.00","currencyCode":"GBP"}}},
          {"createdAt":"2026-10-01T11:00:00Z","cancelledAt":null,"test":false,"currentTotalPriceSet":{"shopMoney":{"amount":"1500","currencyCode":"JPY"}}}]}}}
        """
        let page = try SalesAPI.parse(.shopify, data: Data(json.utf8), since: Self.since)
        #expect(page.figures == SalesFigures(amounts: ["GBP": 1250, "JPY": 1500], orders: 2))
        #expect(page.next == nil)
        #expect(throws: WebProblem.message("Access denied for orders field.")) {
            try SalesAPI.parse(.shopify, data: Data(#"{"errors":[{"message":"Access denied for orders field."}]}"#.utf8), since: Self.since)
        }
    }

    @Test func lemonSqueezyStopsOnceItReachesYesterday() throws {
        let json = """
        {"meta":{"page":{"currentPage":1,"lastPage":4}},"data":[
          {"attributes":{"status":"paid","currency":"USD","total":1999,"created_at":"2026-10-01T10:00:00.000000Z","test_mode":false}},
          {"attributes":{"status":"partial_refund","currency":"USD","total":1000,"refunded_amount":400,"created_at":"2026-10-01T09:00:00.000000Z","test_mode":false}},
          {"attributes":{"status":"paid","currency":"USD","total":500,"created_at":"2026-10-01T08:00:00.000000Z","test_mode":true}},
          {"attributes":{"status":"refunded","currency":"USD","total":800,"created_at":"2026-10-01T07:00:00.000000Z","test_mode":false}},
          {"attributes":{"status":"paid","currency":"USD","total":700,"created_at":"2026-09-30T10:00:00.000000Z","test_mode":false}}]}
        """
        let page = try SalesAPI.parse(.lemonSqueezy, data: Data(json.utf8), since: Self.since, page: 1)
        #expect(page.figures == SalesFigures(amounts: ["USD": 2599], orders: 2))
        #expect(page.next == nil)
        let today = """
        {"meta":{"page":{"currentPage":1,"lastPage":2}},"data":[
          {"attributes":{"status":"paid","currency":"EUR","total":100,"created_at":"2026-10-01T10:00:00Z","test_mode":false}}]}
        """
        #expect(try SalesAPI.parse(.lemonSqueezy, data: Data(today.utf8), since: Self.since, page: 1).next == .page(2))
    }

    @Test func gumroadLeavesOutRefundsAndEarlierSales() throws {
        let json = """
        {"success":true,"next_page_key":"k2","sales":[
          {"created_at":"2026-10-01T10:00:00Z","price":1500,"currency_symbol":"$","refunded":false,"chargedback":false},
          {"created_at":"2026-10-01T11:00:00Z","price":900,"currency_symbol":"€","refunded":false},
          {"created_at":"2026-10-01T12:00:00Z","price":700,"currency_symbol":"$","refunded":true},
          {"created_at":"2026-09-30T12:00:00Z","price":3000,"currency_symbol":"$","refunded":false}]}
        """
        let page = try SalesAPI.parse(.gumroad, data: Data(json.utf8), since: Self.since)
        #expect(page.figures == SalesFigures(amounts: ["USD": 1500, "EUR": 900], orders: 2))
        #expect(page.next == .after("k2"))
        #expect(throws: WebProblem.message("Invalid token")) {
            try SalesAPI.parse(.gumroad, data: Data(#"{"success":false,"message":"Invalid token"}"#.utf8), since: Self.since)
        }
    }

    @Test func dodoPolarAndPaddle() throws {
        let dodo = """
        {"items":[{"payment_id":"p1","total_amount":4900,"currency":"USD","status":"succeeded","created_at":"2026-10-01T10:00:00Z"},
                  {"payment_id":"p2","total_amount":1000,"currency":"USD","status":"succeeded","refund_status":"full","created_at":"2026-10-01T10:00:00Z"}]}
        """
        #expect(try SalesAPI.parse(.dodo, data: Data(dodo.utf8), since: Self.since, page: 0)
            == SalesPage(figures: SalesFigures(amounts: ["USD": 4900], orders: 1)))

        let polar = """
        {"items":[{"status":"paid","total_amount":2400,"refunded_amount":0,"currency":"usd","created_at":"2026-10-01T10:00:00Z"},
                  {"status":"partially_refunded","total_amount":2400,"refunded_amount":400,"currency":"usd","created_at":"2026-10-01T11:00:00Z"},
                  {"status":"pending","total_amount":2400,"currency":"usd","created_at":"2026-10-01T11:00:00Z"}],
         "pagination":{"total_count":120,"max_page":2}}
        """
        let p = try SalesAPI.parse(.polar, data: Data(polar.utf8), since: Self.since, page: 1)
        #expect(p.figures == SalesFigures(amounts: ["USD": 4400], orders: 2))
        #expect(p.next == .page(2))

        let paddle = """
        {"data":[{"status":"completed","currency_code":"EUR","created_at":"2026-10-01T10:00:00Z","details":{"totals":{"total":"1190","grand_total":"1190"}}},
                 {"status":"completed","currency_code":"EUR","created_at":"2026-10-01T11:00:00Z","details":{"totals":{"total":"500"}}}],
         "meta":{"pagination":{"per_page":200,"next":"https://api.paddle.com/transactions?after=txn_2","has_more":true}}}
        """
        let pd = try SalesAPI.parse(.paddle, data: Data(paddle.utf8), since: Self.since)
        #expect(pd.figures == SalesFigures(amounts: ["EUR": 1690], orders: 2))
        #expect(pd.next == .url(URL(string: "https://api.paddle.com/transactions?after=txn_2")!))
    }

    @Test func unreadableRepliesSaySo() {
        for store in SalesStore.allCases {
            #expect(throws: WebProblem.self) { try SalesAPI.parse(store, data: Data("not json".utf8), since: Self.since) }
            #expect(throws: WebProblem.self) { try SalesAPI.parse(store, data: Data("{}".utf8), since: Self.since) }
        }
    }

    @Test func currenciesHaveTheirOwnDecimals() {
        #expect(CurrencyDigits.digits("jpy") == 0 && CurrencyDigits.digits("KWD") == 3 && CurrencyDigits.digits("GBP") == 2)
        #expect(CurrencyDigits.minor(fromDecimal: "12.345", currency: "GBP") == 1235)
        #expect(CurrencyDigits.minor(fromDecimal: "1500", currency: "JPY") == 1500)
        #expect(CurrencyDigits.minor(fromDecimal: "1.5", currency: "BHD") == 1500)
        #expect(CurrencyDigits.minor(fromDecimal: "abc", currency: "GBP") == nil)
        let gb = Locale(identifier: "en_GB")
        #expect(Money(minor: 123_450, currency: "GBP").formatted(locale: gb) == "£1,234.50")
        #expect(Money(minor: 1500, currency: "JPY").formatted(locale: gb) == "JP¥1,500")
    }

    @Test func headlineLeadsWithTheUsersCurrency() throws {
        let stores = [
            StoreSales(store: .stripe, figures: SalesFigures(amounts: ["GBP": 10_000, "USD": 50_000], orders: 3)),
            StoreSales(store: .polar, figures: SalesFigures(amounts: ["GBP": 2_500], orders: 1)),
            StoreSales(store: .gumroad, figures: SalesFigures(amounts: ["EUR": 99_999], orders: 9), problem: .rejectedKey),
        ]
        let total = SalesSummary.total(stores)
        #expect(total == SalesFigures(amounts: ["GBP": 12_500, "USD": 50_000], orders: 4))
        let gbp = try #require(SalesSummary.headline(total, preferred: "gbp"))
        #expect(gbp.main == Money(minor: 12_500, currency: "GBP") && gbp.others == [Money(minor: 50_000, currency: "USD")])
        let largest = try #require(SalesSummary.headline(total, preferred: "AUD"))
        #expect(largest.main.currency == "USD")
        #expect(SalesSummary.headline(SalesFigures(), preferred: "GBP") == nil)
    }

    @Test func refreshesEveryQuarterHourOnlyWhileUnlockedAndOn() {
        let now = Self.since.addingTimeInterval(3600)
        #expect(SalesSchedule.nextRefresh(last: nil, enabled: true, hasStores: true, locked: false, lowPower: false, now: now) == now)
        #expect(SalesSchedule.nextRefresh(last: now, enabled: true, hasStores: true, locked: false, lowPower: false, now: now)
            == now.addingTimeInterval(15 * 60))
        #expect(SalesSchedule.nextRefresh(last: now.addingTimeInterval(-3600), enabled: true, hasStores: true, locked: false, lowPower: false, now: now) == now)
        #expect(SalesSchedule.nextRefresh(last: nil, enabled: false, hasStores: true, locked: false, lowPower: false, now: now) == nil)
        #expect(SalesSchedule.nextRefresh(last: nil, enabled: true, hasStores: false, locked: false, lowPower: false, now: now) == nil)
        #expect(SalesSchedule.nextRefresh(last: nil, enabled: true, hasStores: true, locked: true, lowPower: false, now: now) == nil)
        #expect(SalesSchedule.nextRefresh(last: nil, enabled: true, hasStores: true, locked: false, lowPower: true, now: now) == nil)
        #expect(SalesSchedule.isStale(nil, now: now) && SalesSchedule.isStale(now.addingTimeInterval(-61), now: now))
        #expect(!SalesSchedule.isStale(now.addingTimeInterval(-30), now: now))
        var london = Calendar(identifier: .gregorian)
        london.timeZone = TimeZone(identifier: "Europe/London")!
        #expect(SalesSchedule.startOfDay(now, calendar: london) == Self.since)
    }

    @Test func midnightStartsANewDay() {
        var london = Calendar(identifier: .gregorian)
        london.timeZone = TimeZone(identifier: "Europe/London")!
        // Asked at 23:55: the next ask is at midnight, not 00:10, so "Today" turns over then.
        let lateLast = Self.since.addingTimeInterval(-5 * 60)
        #expect(SalesSchedule.nextRefresh(last: lateLast, enabled: true, hasStores: true, locked: false, lowPower: false,
                                          now: lateLast, calendar: london) == Self.since)
        // Earlier in the day the quarter hour comes first.
        let noon = Self.since.addingTimeInterval(12 * 3600)
        #expect(SalesSchedule.nextRefresh(last: noon, enabled: true, hasStores: true, locked: false, lowPower: false,
                                          now: noon, calendar: london) == noon.addingTimeInterval(15 * 60))
        // Locked over midnight: asked as soon as it is unlocked.
        let morning = Self.since.addingTimeInterval(7 * 3600)
        #expect(SalesSchedule.nextRefresh(last: lateLast, enabled: true, hasStores: true, locked: false, lowPower: false,
                                          now: morning, calendar: london) == morning)
    }

    @Test func aStoreConnectedDuringARefreshKeepsItsFigures() {
        let stripe = StoreSales(store: .stripe, figures: SalesFigures(amounts: ["GBP": 100], orders: 1))
        let newStripe = StoreSales(store: .stripe, figures: SalesFigures(amounts: ["GBP": 300], orders: 2))
        let polar = StoreSales(store: .polar, figures: SalesFigures(amounts: ["USD": 50], orders: 1))
        // Polar was connected in Settings while Stripe's refresh was under way.
        let merged = SalesSummary.merged([newStripe], into: [stripe, polar], order: [.stripe, .polar])
        #expect(merged.stores == [newStripe, polar] && !merged.missing)
        // A store added by hand with nothing yet is asked for next; one removed goes.
        let added = SalesSummary.merged([newStripe], into: [polar], order: [.paddle, .stripe])
        #expect(added.stores == [newStripe] && added.missing)
        // Shown in the order they were connected.
        #expect(SalesSummary.merged([newStripe, polar], into: [], order: [.polar, .stripe]).stores.map(\.store) == [.polar, .stripe])
    }

    @Test func problemsReadPlainly() {
        #expect(WebProblem.from(status: 200) == nil)
        #expect(WebProblem.from(status: 401) == .rejectedKey && WebProblem.from(status: 403) == .rejectedKey)
        #expect(WebProblem.from(status: 429) == .rateLimited && WebProblem.from(status: 502) == .server(502))
        #expect(WebProblem.rejectedKey.text("Stripe") == "Stripe turned the key down. Paste a new one in Settings.")
        #expect(WebProblem.missingKey.text("Polar").hasPrefix("Polar needs its key again"))
        for p in [WebProblem.rejectedKey, .notFound, .rateLimited, .server(500), .unreadable, .unreachable, .missingKey, .message("x"), .blocked] {
            #expect(!p.text("Paddle").contains("—"))
            #expect(!p.text("Paddle").contains("'") && !p.shortText.contains("'"))
            #expect(p.shortText.split(separator: " ").count <= 3)
            // A status code is for the log, never the sentence.
            #expect(!p.text("Paddle").contains { $0.isNumber })
        }
        // A store row says what to do beside the warning sign, in the words the page connects it with.
        #expect(WebProblem.rejectedKey.shortText == "Reconnect" && WebProblem.missingKey.shortText == "Reconnect")
        #expect(WebProblem.unreachable.shortText == "Can\u{2019}t connect")
        #expect(WebProblem.server(502).text("Stripe") == "Stripe is having problems right now. Islet tries again later.")
        #expect(WebProblem.server(502).shortText == "Try again later")
        #expect(WebProblem.blocked.text("Stripe") == "Islet couldn\u{2019}t check Stripe.")
    }

    @Test func onlyHTTPSToNamedHostsOrOllamaOnThisMac() {
        #expect(WebRequest(url: URL(string: "https://api.stripe.com/v1/charges")!).isAllowed(hosts: ["api.stripe.com"]))
        #expect(!WebRequest(url: URL(string: "http://api.stripe.com/v1/charges")!).isAllowed(hosts: ["api.stripe.com"]))
        #expect(!WebRequest(url: URL(string: "https://api.stripe.com:8443/v1")!).isAllowed(hosts: ["api.stripe.com"]))
        #expect(!WebRequest(url: URL(string: "https://evil.example/v1")!).isAllowed(hosts: ["api.stripe.com"]))
        #expect(OllamaUsage.request.isAllowed(hosts: [OllamaUsage.host]))
        #expect(!WebRequest(url: URL(string: "http://127.0.0.1:8080/api/ps")!).isAllowed(hosts: [OllamaUsage.host]))
        #expect(!WebRequest(url: URL(string: "http://localhost:11434/api/ps")!).isAllowed(hosts: ["localhost"]))
    }
}
