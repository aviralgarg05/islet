import Foundation

/// A shop or payment service whose takings Islet can add up, with a key the user pastes.
public enum SalesStore: String, Codable, CaseIterable, Sendable, Identifiable {
    case stripe, shopify, lemonSqueezy, gumroad, dodo, polar, paddle

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .stripe: return "Stripe"
        case .shopify: return "Shopify"
        case .lemonSqueezy: return "Lemon Squeezy"
        case .gumroad: return "Gumroad"
        case .dodo: return "Dodo Payments"
        case .polar: return "Polar"
        case .paddle: return "Paddle"
        }
    }

    /// The store's own colour, for its dot.
    public var tint: String {
        switch self {
        case .stripe: return "#635BFF"
        case .shopify: return "#95BF47"
        case .lemonSqueezy: return "#FFC233"
        case .gumroad: return "#FF90E8"
        case .dodo: return "#2FB67C"
        case .polar: return "#3D8BFF"
        case .paddle: return "#FDDD35"
        }
    }

    /// The Keychain account its key is kept under.
    public var keyAccount: String { "sales.\(rawValue)" }

    /// Where to make the key, in plain words.
    public var keyHelp: String {
        switch self {
        case .stripe: return "In Stripe, Developers → API keys → Create restricted key, with Read on Charges."
        case .shopify: return "In Shopify, Settings → Apps → Develop apps: a custom app with read access to orders, then its Admin API access token."
        case .lemonSqueezy: return "In Lemon Squeezy, Settings → API. Its keys can't be limited to reading; Islet only reads."
        case .gumroad: return "In Gumroad, Settings → Advanced → Applications: create an application, then an access token."
        case .dodo: return "In Dodo Payments, Developer → API keys."
        case .polar: return "In Polar, Settings → Developers: an organisation token that can read orders."
        case .paddle: return "In Paddle, Developer tools → Authentication: an API key that can read transactions."
        }
    }

    /// Whether the key can be made read-only, so Settings can say so.
    public var hasReadOnlyKeys: Bool { self != .lemonSqueezy }
}

/// Takings in one or more currencies, in each currency's smallest unit (cents, pence, yen).
public struct SalesFigures: Equatable, Sendable {
    public var amounts: [String: Int64]
    /// Orders or payments counted.
    public var orders: Int

    public init(amounts: [String: Int64] = [:], orders: Int = 0) {
        self.amounts = amounts
        self.orders = orders
    }

    public mutating func add(_ minor: Int64, currency: String) {
        let code = currency.uppercased()
        guard minor != 0, code.count == 3 else { return }
        amounts[code] = ToolJSON.sum(amounts[code] ?? 0, minor)
    }

    public mutating func add(_ other: SalesFigures) {
        for (code, minor) in other.amounts { add(minor, currency: code) }
        orders += other.orders
    }

    public var isEmpty: Bool { amounts.values.allSatisfy { $0 == 0 } }
}

/// An amount of money in a currency's smallest unit.
public struct Money: Equatable, Sendable {
    public var minor: Int64
    public var currency: String

    public init(minor: Int64, currency: String) {
        self.minor = minor
        self.currency = currency.uppercased()
    }

    public var major: Double { Double(minor) / pow(10, Double(CurrencyDigits.digits(currency))) }

    /// "£1,234.50", in the user's locale.
    public func formatted(locale: Locale = .current) -> String {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.locale = locale
        f.currencyCode = currency
        let digits = CurrencyDigits.digits(currency)
        f.minimumFractionDigits = digits
        f.maximumFractionDigits = digits
        return f.string(from: NSNumber(value: major)) ?? "\(currency) \(major)"
    }
}

/// Decimal places each currency's smallest unit has, as the payment services count them.
public enum CurrencyDigits {
    static let zero: Set<String> = ["BIF", "CLP", "DJF", "GNF", "JPY", "KMF", "KRW", "MGA", "PYG", "RWF", "UGX", "VND", "VUV", "XAF", "XOF", "XPF"]
    static let three: Set<String> = ["BHD", "IQD", "JOD", "KWD", "LYD", "OMR", "TND"]

    public static func digits(_ code: String) -> Int {
        let c = code.uppercased()
        if zero.contains(c) { return 0 }
        if three.contains(c) { return 3 }
        return 2
    }

    /// "12.50" in `code` as smallest units (1250), rounded; nil if it isn't a number.
    public static func minor(fromDecimal text: String, currency code: String) -> Int64? {
        guard let d = Decimal(string: text.trimmingCharacters(in: .whitespaces), locale: Locale(identifier: "en_US_POSIX")) else { return nil }
        var scaled = d * pow(Decimal(10), digits(code))
        var rounded = Decimal()
        NSDecimalRound(&rounded, &scaled, 0, .plain)
        let n = NSDecimalNumber(decimal: rounded)
        guard n != .notANumber, abs(n.doubleValue) < 9e15 else { return nil }
        return n.int64Value
    }
}

/// How to ask for the next page of a list.
public enum SalesCursor: Equatable, Sendable {
    /// The last item's id or the service's own page key.
    case after(String)
    case page(Int)
    /// A full URL the service gave for the next page (checked against the store's host).
    case url(URL)
}

/// One page of a store's list, added up.
public struct SalesPage: Equatable, Sendable {
    public var figures: SalesFigures
    public var next: SalesCursor?

    public init(figures: SalesFigures, next: SalesCursor? = nil) {
        self.figures = figures
        self.next = next
    }
}

/// A store's takings today, or why they couldn't be read.
public struct StoreSales: Equatable, Sendable, Identifiable {
    public var store: SalesStore
    public var figures: SalesFigures
    public var problem: WebProblem?
    public var updatedAt: Date?

    public var id: String { store.rawValue }

    public init(store: SalesStore, figures: SalesFigures = SalesFigures(), problem: WebProblem? = nil, updatedAt: Date? = nil) {
        self.store = store
        self.figures = figures
        self.problem = problem
        self.updatedAt = updatedAt
    }
}

/// The requests for today's sales and the reading of the replies, for each store. Each reads
/// only: paid orders or payments created since the start of today, less refunds, with test
/// orders left out.
public enum SalesAPI {
    /// Pages read at most per store and refresh (a few thousand orders; Paddle's pages are
    /// smaller).
    public static let maxPages = 10
    /// Paddle's largest page for transactions: a bigger `per_page` is refused.
    static let paddlePageSize = 30
    static let shopifyVersion = "2025-07"

    /// The hosts a store's requests may go to.
    public static func hosts(_ store: SalesStore, shop: String?) -> Set<String> {
        switch store {
        case .stripe: return ["api.stripe.com"]
        case .shopify: return shopifyHost(shop ?? "").map { [$0] } ?? []
        case .lemonSqueezy: return ["api.lemonsqueezy.com"]
        case .gumroad: return ["api.gumroad.com"]
        case .dodo: return ["live.dodopayments.com"]
        case .polar: return ["api.polar.sh"]
        case .paddle: return ["api.paddle.com", "sandbox-api.paddle.com"]
        }
    }

    /// "example", "example.myshopify.com" or its admin URL → "example.myshopify.com". Nil for
    /// anything else, so the token only ever goes to a Shopify store.
    public static func shopifyHost(_ input: String) -> String? {
        var s = input.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        for prefix in ["https://", "http://"] where s.hasPrefix(prefix) { s.removeFirst(prefix.count) }
        if let slash = s.firstIndex(of: "/") { s = String(s[..<slash]) }
        if !s.contains(".") { s += ".myshopify.com" }
        guard s.hasSuffix(".myshopify.com") else { return nil }
        let name = s.dropLast(".myshopify.com".count)
        guard (1...60).contains(name.count), name.first != "-",
              name.unicodeScalars.allSatisfy({ ("a"..."z").contains($0) || ("0"..."9").contains($0) || $0 == "-" }) else { return nil }
        return s
    }

    /// A quick shape check before a key is sent anywhere: a sane length and no spaces.
    public static func looksLikeKey(_ key: String) -> Bool {
        (8...4096).contains(key.count) && key.unicodeScalars.allSatisfy { $0.isASCII && $0.value > 0x20 && $0.value < 0x7F }
    }

    public static func request(_ store: SalesStore, key: String, shop: String? = nil, since: Date,
                               cursor: SalesCursor? = nil) throws -> WebRequest {
        let bearer = ["Authorization": "Bearer \(key)", "Accept": "application/json"]
        switch store {
        case .stripe:
            var q = [("created[gte]", String(Int(since.timeIntervalSince1970))), ("limit", "100")]
            if case .after(let id)? = cursor { q.append(("starting_after", id)) }
            return WebRequest(url: WebRequest.url("https://api.stripe.com/v1/charges", q), headers: bearer)

        case .shopify:
            guard let host = shopifyHost(shop ?? "") else { throw WebProblem.notFound }
            var variables: [String: Any] = ["q": "created_at:>='\(ToolJSON.iso(since))'"]
            if case .after(let c)? = cursor { variables["after"] = c }
            let query = """
            query Sales($q: String!, $after: String) { orders(first: 100, after: $after, query: $q) { \
            pageInfo { hasNextPage endCursor } \
            nodes { createdAt cancelledAt test currentTotalPriceSet { shopMoney { amount currencyCode } } } } }
            """
            let body = try JSONSerialization.data(withJSONObject: ["query": query, "variables": variables], options: [.sortedKeys])
            return WebRequest(url: URL(string: "https://\(host)/admin/api/\(shopifyVersion)/graphql.json")!, method: "POST",
                              headers: ["X-Shopify-Access-Token": key, "Content-Type": "application/json", "Accept": "application/json"],
                              body: body)

        case .lemonSqueezy:
            var page = 1
            if case .page(let n)? = cursor { page = n }
            return WebRequest(url: WebRequest.url("https://api.lemonsqueezy.com/v1/orders", [("page[size]", "100"), ("page[number]", String(page))]),
                              headers: ["Authorization": "Bearer \(key)", "Accept": "application/vnd.api+json"])

        case .gumroad:
            // `after` takes a date; the day before covers every time zone, and the rest is
            // filtered by time.
            var q = [("after", dayString(since.addingTimeInterval(-86_400)))]
            if case .after(let k)? = cursor { q.append(("page_key", k)) }
            return WebRequest(url: WebRequest.url("https://api.gumroad.com/v2/sales", q), headers: bearer)

        case .dodo:
            var page = 0
            if case .page(let n)? = cursor { page = n }
            return WebRequest(url: WebRequest.url("https://live.dodopayments.com/payments", [
                ("created_at_gte", ToolJSON.iso(since)), ("status", "succeeded"), ("page_size", "100"), ("page_number", String(page)),
            ]), headers: bearer)

        case .polar:
            var page = 1
            if case .page(let n)? = cursor { page = n }
            return WebRequest(url: WebRequest.url("https://api.polar.sh/v1/orders/", [
                ("created_after", ToolJSON.iso(since)), ("limit", "100"), ("page", String(page)), ("sorting", "-created_at"),
            ]), headers: bearer)

        case .paddle:
            if case .url(let next)? = cursor {
                guard WebRequest(url: next).isAllowed(hosts: hosts(.paddle, shop: nil)) else { throw WebProblem.unreadable }
                return WebRequest(url: next, headers: bearer)
            }
            let host = key.contains("_sdbx_") ? "sandbox-api.paddle.com" : "api.paddle.com"
            return WebRequest(url: WebRequest.url("https://\(host)/transactions", [
                ("status", "completed"), ("created_at[GTE]", ToolJSON.iso(since)), ("per_page", String(paddlePageSize)),
                ("order_by", "created_at[DESC]"),
            ]), headers: bearer)
        }
    }

    /// Reads one page of a store's reply. `page` is the page asked for, for numbered lists.
    public static func parse(_ store: SalesStore, data: Data, since: Date, page: Int? = nil) throws -> SalesPage {
        let o = try ToolJSON.object(data)
        var figures = SalesFigures()
        switch store {
        case .stripe:
            guard let items = o["data"] as? [[String: Any]] else { throw WebProblem.unreadable }
            for c in items {
                guard c["paid"] as? Bool == true, c["status"] as? String == "succeeded", let currency = c["currency"] as? String else { continue }
                let captured = ToolJSON.number(c["amount_captured"]) ?? ToolJSON.number(c["amount"]) ?? 0
                let net = ToolJSON.whole(captured - (ToolJSON.number(c["amount_refunded"]) ?? 0))
                guard net > 0 else { continue }
                figures.add(net, currency: currency)
                figures.orders += 1
            }
            let more = o["has_more"] as? Bool == true
            let last = items.last?["id"] as? String
            return SalesPage(figures: figures, next: more ? last.map(SalesCursor.after) : nil)

        case .shopify:
            if let errors = o["errors"] as? [[String: Any]], let first = errors.first?["message"] as? String { throw WebProblem.message(first) }
            if let error = o["errors"] as? String { throw WebProblem.message(error) }
            guard let orders = (o["data"] as? [String: Any])?["orders"] as? [String: Any],
                  let nodes = orders["nodes"] as? [[String: Any]] else { throw WebProblem.unreadable }
            for n in nodes {
                guard n["cancelledAt"] is NSNull || n["cancelledAt"] == nil, n["test"] as? Bool != true,
                      let money = ((n["currentTotalPriceSet"] as? [String: Any])?["shopMoney"]) as? [String: Any],
                      let currency = money["currencyCode"] as? String else { continue }
                let amount = (money["amount"] as? String) ?? ToolJSON.number(money["amount"]).map { String($0) }
                guard let amount, let minor = CurrencyDigits.minor(fromDecimal: amount, currency: currency), minor > 0 else { continue }
                figures.add(minor, currency: currency)
                figures.orders += 1
            }
            let info = orders["pageInfo"] as? [String: Any]
            let next = info?["hasNextPage"] as? Bool == true ? (info?["endCursor"] as? String).map(SalesCursor.after) : nil
            return SalesPage(figures: figures, next: next)

        case .lemonSqueezy:
            guard let items = o["data"] as? [[String: Any]] else { throw WebProblem.unreadable }
            // Newest first: a page that reaches back past today is the last one needed.
            var reachedEarlier = false
            for item in items {
                let a = item["attributes"] as? [String: Any] ?? [:]
                guard let created = ToolJSON.date(a["created_at"]) else { continue }
                if created < since { reachedEarlier = true; continue }
                guard a["test_mode"] as? Bool != true, let status = a["status"] as? String,
                      status == "paid" || status == "partial_refund", let currency = a["currency"] as? String else { continue }
                let net = ToolJSON.whole((ToolJSON.number(a["total"]) ?? 0) - (ToolJSON.number(a["refunded_amount"]) ?? 0))
                guard net > 0 else { continue }
                figures.add(net, currency: currency)
                figures.orders += 1
            }
            let meta = (o["meta"] as? [String: Any])?["page"] as? [String: Any]
            let current = UsageJSON.int(meta?["currentPage"]) ?? page ?? 1
            let last = UsageJSON.int(meta?["lastPage"]) ?? current
            return SalesPage(figures: figures, next: !reachedEarlier && current < last ? .page(current + 1) : nil)

        case .gumroad:
            if o["success"] as? Bool == false { throw WebProblem.message((o["message"] as? String) ?? "the request failed") }
            guard let sales = o["sales"] as? [[String: Any]] else { throw WebProblem.unreadable }
            for s in sales {
                guard let created = ToolJSON.date(s["created_at"]), created >= since else { continue }
                if s["refunded"] as? Bool == true || s["chargedback"] as? Bool == true || s["disputed"] as? Bool == true { continue }
                guard let price = ToolJSON.number(s["price"]), price > 0 else { continue }
                let currency = (s["currency"] as? String) ?? currency(symbol: s["currency_symbol"] as? String)
                figures.add(ToolJSON.whole(price), currency: currency)
                figures.orders += 1
            }
            return SalesPage(figures: figures, next: (o["next_page_key"] as? String).flatMap { $0.isEmpty ? nil : .after($0) })

        case .dodo:
            guard let items = (o["items"] as? [[String: Any]]) ?? (o["data"] as? [[String: Any]]) else { throw WebProblem.unreadable }
            for p in items {
                guard (p["status"] as? String).map({ $0 == "succeeded" }) ?? true, p["refund_status"] as? String != "full",
                      let currency = p["currency"] as? String, let total = ToolJSON.number(p["total_amount"]), total > 0 else { continue }
                if let created = ToolJSON.date(p["created_at"]), created < since { continue }
                figures.add(ToolJSON.whole(total), currency: currency)
                figures.orders += 1
            }
            let current = page ?? 0
            return SalesPage(figures: figures, next: items.count >= 100 ? .page(current + 1) : nil)

        case .polar:
            guard let items = o["items"] as? [[String: Any]] else { throw WebProblem.unreadable }
            for order in items {
                guard let status = order["status"] as? String, status == "paid" || status == "partially_refunded",
                      let currency = order["currency"] as? String else { continue }
                if let created = ToolJSON.date(order["created_at"]), created < since { continue }
                let total = ToolJSON.number(order["total_amount"]) ?? ToolJSON.number(order["amount"]) ?? 0
                let net = ToolJSON.whole(total - (ToolJSON.number(order["refunded_amount"]) ?? 0))
                guard net > 0 else { continue }
                figures.add(net, currency: currency)
                figures.orders += 1
            }
            let current = page ?? 1
            let maxPage = UsageJSON.int((o["pagination"] as? [String: Any])?["max_page"]) ?? current
            return SalesPage(figures: figures, next: current < maxPage ? .page(current + 1) : nil)

        case .paddle:
            if let error = o["error"] as? [String: Any], let detail = error["detail"] as? String { throw WebProblem.message(detail) }
            guard let items = o["data"] as? [[String: Any]] else { throw WebProblem.unreadable }
            for t in items {
                let totals = (t["details"] as? [String: Any])?["totals"] as? [String: Any] ?? [:]
                guard let currency = (t["currency_code"] as? String) ?? (totals["currency_code"] as? String) else { continue }
                if let created = ToolJSON.date(t["created_at"]), created < since { continue }
                let raw = totals["grand_total"] ?? totals["total"]
                let minor = (raw as? String).flatMap { Int64($0) } ?? ToolJSON.number(raw).map(ToolJSON.whole) ?? 0
                guard minor > 0 else { continue }
                figures.add(minor, currency: currency)
                figures.orders += 1
            }
            let pagination = (o["meta"] as? [String: Any])?["pagination"] as? [String: Any]
            let next = pagination?["has_more"] as? Bool == true ? (pagination?["next"] as? String).flatMap(URL.init(string:)) : nil
            return SalesPage(figures: figures, next: next.map(SalesCursor.url))
        }
    }

    /// Gumroad gives a symbol, not a code.
    static func currency(symbol: String?) -> String {
        switch symbol?.trimmingCharacters(in: .whitespaces) {
        case "€": return "EUR"
        case "£": return "GBP"
        case "¥": return "JPY"
        case "₹": return "INR"
        case "A$": return "AUD"
        case "CA$", "C$": return "CAD"
        case "R$": return "BRL"
        case "CHF": return "CHF"
        case "₩": return "KRW"
        case "zł": return "PLN"
        default: return "USD"
        }
    }

    /// yyyy-MM-dd in UTC.
    static func dayString(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }
}

/// What the Sales page leads with: today's total in one currency, then any others.
public enum SalesSummary {
    public static func total(_ stores: [StoreSales]) -> SalesFigures {
        var all = SalesFigures()
        for s in stores where s.problem == nil { all.add(s.figures) }
        return all
    }

    /// The stores to show after a refresh, in the order they were connected: each one's new
    /// result, or else the one it already had (a store connected in Settings while the refresh
    /// was under way keeps the figures it was checked with). `missing` says a connected store
    /// has nothing to show yet, so it is asked for straight away.
    public static func merged(_ results: [StoreSales], into previous: [StoreSales],
                              order: [SalesStore]) -> (stores: [StoreSales], missing: Bool) {
        let shown = order.compactMap { store in
            results.first { $0.store == store } ?? previous.first { $0.store == store }
        }
        return (shown, shown.count < order.count)
    }

    /// The headline amount (the user's own currency when there are takings in it, else the
    /// largest) and the rest, largest first. Nil with nothing taken yet.
    public static func headline(_ figures: SalesFigures, preferred: String?) -> (main: Money, others: [Money])? {
        let all = figures.amounts.filter { $0.value != 0 }.map { Money(minor: $0.value, currency: $0.key) }
            .sorted { $0.major != $1.major ? $0.major > $1.major : $0.currency < $1.currency }
        guard !all.isEmpty else { return nil }
        let main = all.first { $0.currency == preferred?.uppercased() } ?? all[0]
        return (main, all.filter { $0 != main })
    }
}

/// When sales are asked for again: every 15 minutes while the feature is on, a store is
/// connected and the Mac is unlocked, and not in Low Power Mode (opening the page still does).
/// Midnight also counts, so "Today" never shows yesterday's takings for long.
public enum SalesSchedule {
    public static let interval: TimeInterval = 15 * 60

    public static func nextRefresh(last: Date?, enabled: Bool, hasStores: Bool, locked: Bool, lowPower: Bool, now: Date,
                                   calendar: Calendar = .current) -> Date? {
        guard enabled, hasStores, !locked, !lowPower else { return nil }
        guard let last else { return now }
        return max(now, min(last.addingTimeInterval(interval), nextDay(after: last, calendar: calendar)))
    }

    /// The midnight after `date` in `calendar`'s time zone.
    static func nextDay(after date: Date, calendar: Calendar) -> Date {
        calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: date)) ?? date.addingTimeInterval(86_400)
    }

    /// Opening the page asks again once the figures are a minute old.
    public static func isStale(_ last: Date?, now: Date) -> Bool {
        guard let last else { return true }
        return now.timeIntervalSince(last) >= 60
    }

    /// Midnight today in `calendar`'s time zone.
    public static func startOfDay(_ now: Date, calendar: Calendar = .current) -> Date {
        calendar.startOfDay(for: now)
    }
}
