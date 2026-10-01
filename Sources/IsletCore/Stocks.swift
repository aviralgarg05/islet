import Foundation

/// A share or index on the watchlist: its price, the day's change and the day's prices for a
/// sparkline.
public struct StockQuote: Equatable, Sendable, Identifiable {
    public var symbol: String
    public var name: String?
    public var price: Double
    public var previousClose: Double?
    public var currency: String?
    /// The day's prices, oldest first, for the sparkline.
    public var closes: [Double]
    /// When the price was last traded.
    public var time: Date?

    public var id: String { symbol }

    public init(symbol: String, name: String? = nil, price: Double, previousClose: Double? = nil, currency: String? = nil,
                closes: [Double] = [], time: Date? = nil) {
        self.symbol = symbol
        self.name = name
        self.price = price
        self.previousClose = previousClose
        self.currency = currency
        self.closes = closes
        self.time = time
    }

    public var change: Double? { previousClose.map { price - $0 } }

    public var changePercent: Double? {
        guard let p = previousClose, p != 0 else { return nil }
        return (price - p) / p * 100
    }

    /// "+1.24%" or "−0.80%", with a real minus sign.
    public var changeText: String? {
        guard let pct = changePercent else { return nil }
        let text = String(format: "%.2f%%", abs(pct))
        if abs(pct) < 0.005 { return "0.00%" }
        return (pct > 0 ? "+" : "\u{2212}") + text
    }

    /// "329.06" with the decimals the price needs (more for prices under one).
    public var priceText: String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.locale = Locale.current
        let digits = price < 1 ? 4 : 2
        f.minimumFractionDigits = digits
        f.maximumFractionDigits = digits
        return f.string(from: NSNumber(value: price)) ?? String(price)
    }

    /// The name to show: the short name the source gives, or the symbol.
    public var displayName: String { (name?.isEmpty == false ? name : nil) ?? symbol }
}

/// Prices from Yahoo Finance's public chart endpoint, which needs no key or account. One
/// request a symbol, only while the Stocks page is open.
public enum StocksAPI {
    public static let host = "query1.finance.yahoo.com"

    /// "aapl" → "AAPL"; letters, digits and . - ^ = only, up to 15 characters. Nil otherwise.
    public static func normalisedSymbol(_ raw: String) -> String? {
        let s = raw.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard (1...15).contains(s.count),
              s.unicodeScalars.allSatisfy({ ("A"..."Z").contains($0) || ("0"..."9").contains($0) || ".-^=".unicodeScalars.contains($0) })
        else { return nil }
        return s
    }

    public static func request(symbol: String) -> WebRequest? {
        guard let s = normalisedSymbol(symbol) else { return nil }
        let url = WebRequest.url("https://\(host)/v8/finance/chart/\(WebRequest.encode(s))", [("range", "1d"), ("interval", "5m")])
        return WebRequest(url: url, headers: ["Accept": "application/json"])
    }

    public static func parse(_ data: Data) throws -> StockQuote {
        let o = try ToolJSON.object(data)
        let chart = o["chart"] as? [String: Any]
        if let error = chart?["error"] as? [String: Any], let text = error["description"] as? String { throw WebProblem.message(text) }
        guard let result = (chart?["result"] as? [[String: Any]])?.first, let meta = result["meta"] as? [String: Any],
              let symbol = meta["symbol"] as? String else { throw WebProblem.unreadable }
        let quote = ((result["indicators"] as? [String: Any])?["quote"] as? [[String: Any]])?.first
        let closes = (quote?["close"] as? [Any] ?? []).compactMap { ToolJSON.number($0) }
        guard let price = ToolJSON.number(meta["regularMarketPrice"]) ?? closes.last else { throw WebProblem.unreadable }
        let previous = ToolJSON.number(meta["chartPreviousClose"]) ?? ToolJSON.number(meta["previousClose"])
        return StockQuote(symbol: symbol, name: (meta["shortName"] as? String) ?? (meta["longName"] as? String), price: price,
                          previousClose: previous, currency: meta["currency"] as? String, closes: closes,
                          time: ToolJSON.number(meta["regularMarketTime"]).map { Date(timeIntervalSince1970: $0) })
    }
}

/// Points for a sparkline in a `width` × `height` box, y down. At most `limit` points, evenly
/// picked, and flat across the middle when the prices don't move. `including` widens the scale
/// to take in another price (the previous close), so its line can be drawn on the same scale.
public enum Sparkline {
    public static func points(_ values: [Double], width: Double, height: Double, including extra: Double? = nil,
                              limit: Int = 60) -> [CGPoint] {
        let finite = values.filter(\.isFinite)
        guard finite.count >= 2, width > 0, height > 0 else { return [] }
        let picked: [Double]
        if finite.count > limit, limit >= 2 {
            picked = (0..<limit).map { finite[Int((Double($0) * Double(finite.count - 1) / Double(limit - 1)).rounded())] }
        } else {
            picked = finite
        }
        let range = scale(finite, including: extra)
        return picked.enumerated().map { i, v in
            CGPoint(x: Double(i) / Double(picked.count - 1) * width, y: y(v, range: range, height: height))
        }
    }

    /// Where `value` sits on the scale of `values` (and `including`), y down.
    public static func y(of value: Double, in values: [Double], including extra: Double? = nil, height: Double) -> Double? {
        let finite = values.filter(\.isFinite)
        guard finite.count >= 2, value.isFinite else { return nil }
        return y(value, range: scale(finite, including: extra), height: height)
    }

    static func scale(_ values: [Double], including extra: Double?) -> ClosedRange<Double> {
        let all = values + (extra.flatMap { $0.isFinite ? [$0] : nil } ?? [])
        return all.min()!...all.max()!
    }

    static func y(_ v: Double, range: ClosedRange<Double>, height: Double) -> Double {
        let span = range.upperBound - range.lowerBound
        return span > 0 ? (1 - (v - range.lowerBound) / span) * height : height / 2
    }
}

/// When the watchlist is asked for again: on opening the page once the prices are a minute
/// old, then every two minutes while it stays open, and never while it is closed.
public enum StocksSchedule {
    public static let interval: TimeInterval = 120
    public static let staleAfter: TimeInterval = 60

    public static func isStale(_ last: Date?, now: Date) -> Bool {
        guard let last else { return true }
        return now.timeIntervalSince(last) >= staleAfter
    }

    public static func nextRefresh(last: Date?, pageOpen: Bool, hasSymbols: Bool, now: Date) -> Date? {
        guard pageOpen, hasSymbols else { return nil }
        guard let last else { return now }
        return max(now, last.addingTimeInterval(interval))
    }
}
