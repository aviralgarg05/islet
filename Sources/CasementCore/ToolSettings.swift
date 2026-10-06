import Foundation

// Settings for the tools that live under "More" in the page switcher: the camera mirror, the
// teleprompter, sales and stocks. Each starts off. Every one decodes leniently, like the
// settings around it: a value that can't be read falls back to its default alone.

/// The camera in the open island, for a quick look before a call. It runs only while its page
/// is open, so the camera light is on exactly then.
public struct MirrorSettings: Codable, Equatable, Sendable {
    public var enabled = false
    /// Flipped left to right, as a mirror shows you. A call shows others the unflipped picture.
    public var flipped = true

    public init(enabled: Bool = false, flipped: Bool = true) {
        self.enabled = enabled
        self.flipped = flipped
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = MirrorSettings()
        enabled = (try? c.decodeIfPresent(Bool.self, forKey: .enabled)) ?? d.enabled
        flipped = (try? c.decodeIfPresent(Bool.self, forKey: .flipped)) ?? d.flipped
    }
}

/// A script that scrolls just under the camera, so you read it while looking into the lens.
/// The script itself is kept in a text file beside Casement's other files (`TeleprompterScriptFile`).
public struct TeleprompterSettings: Codable, Equatable, Sendable {
    public var enabled = false
    /// Reading pace while it scrolls.
    public var wordsPerMinute: Double = 140
    /// Size of the script's text, in points.
    public var textSize: Double = 20
    /// The open island turns to clear glass while the page shows, so what's behind shows through.
    public var seeThrough = false

    public static let wordsPerMinuteRange: ClosedRange<Double> = 60...300
    public static let wordsPerMinuteStep: Double = 10
    public static let textSizeRange: ClosedRange<Double> = 14...40

    public init() {}

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = TeleprompterSettings()
        enabled = (try? c.decodeIfPresent(Bool.self, forKey: .enabled)) ?? d.enabled
        wordsPerMinute = (try? c.decodeIfPresent(Double.self, forKey: .wordsPerMinute)) ?? d.wordsPerMinute
        textSize = (try? c.decodeIfPresent(Double.self, forKey: .textSize)) ?? d.textSize
        seeThrough = (try? c.decodeIfPresent(Bool.self, forKey: .seeThrough)) ?? d.seeThrough
        self = sanitized()
    }

    public func sanitized() -> TeleprompterSettings {
        var s = self
        let d = TeleprompterSettings()
        s.wordsPerMinute = wordsPerMinute.isFinite
            ? min(Self.wordsPerMinuteRange.upperBound, max(Self.wordsPerMinuteRange.lowerBound, wordsPerMinute.rounded()))
            : d.wordsPerMinute
        s.textSize = textSize.isFinite
            ? min(Self.textSizeRange.upperBound, max(Self.textSizeRange.lowerBound, textSize.rounded()))
            : d.textSize
        return s
    }
}

/// Today's takings from the stores the user connects, each with a read-only key they paste.
public struct SalesSettings: Codable, Equatable, Sendable {
    public var enabled = false
    /// Stores whose key is in the Keychain, in the order they were added. The keys themselves
    /// never appear here.
    public var stores: [SalesStore] = []
    /// Shopify's store address: "example" or "example.myshopify.com".
    public var shopifyStore = ""

    public init(enabled: Bool = false, stores: [SalesStore] = [], shopifyStore: String = "") {
        self.enabled = enabled
        self.stores = stores
        self.shopifyStore = shopifyStore
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = SalesSettings()
        enabled = (try? c.decodeIfPresent(Bool.self, forKey: .enabled)) ?? d.enabled
        // A store this build doesn't know is skipped, not the whole list.
        let names = (try? c.decodeIfPresent([String].self, forKey: .stores)) ?? []
        stores = names.compactMap(SalesStore.init(rawValue:))
        shopifyStore = (try? c.decodeIfPresent(String.self, forKey: .shopifyStore)) ?? d.shopifyStore
        self = sanitized()
    }

    public func sanitized() -> SalesSettings {
        var s = self
        var seen: Set<SalesStore> = []
        s.stores = stores.filter { seen.insert($0).inserted }
        s.shopifyStore = shopifyStore.trimmingCharacters(in: .whitespacesAndNewlines)
        return s
    }
}

/// A watchlist of shares and indices with the day's change and a sparkline.
public struct StocksSettings: Codable, Equatable, Sendable {
    public var enabled = false
    public var symbols: [String] = ["AAPL", "MSFT", "^GSPC"]

    /// The longest watchlist: enough for a glance, few enough to fetch quickly.
    public static let maxSymbols = 12

    public init(enabled: Bool = false, symbols: [String] = ["AAPL", "MSFT", "^GSPC"]) {
        self.enabled = enabled
        self.symbols = symbols
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = StocksSettings()
        enabled = (try? c.decodeIfPresent(Bool.self, forKey: .enabled)) ?? d.enabled
        symbols = (try? c.decodeIfPresent([String].self, forKey: .symbols)) ?? d.symbols
        self = sanitized()
    }

    /// Symbols in capitals, without repeats or anything that isn't a ticker, at most `maxSymbols`.
    public func sanitized() -> StocksSettings {
        var s = self
        var seen: Set<String> = []
        s.symbols = Array(symbols.compactMap(StocksAPI.normalisedSymbol).filter { seen.insert($0).inserted }.prefix(Self.maxSymbols))
        return s
    }
}

/// Premium requests a month in each Copilot plan, for the bar on Home.
public enum CopilotPlan: Int, Codable, CaseIterable, Sendable {
    case free = 50
    case pro = 300
    case enterprise = 1000
    case proPlus = 1500

    public var title: String {
        switch self {
        case .free: return "Free"
        case .pro: return "Pro or Business"
        case .enterprise: return "Enterprise"
        case .proPlus: return "Pro+"
        }
    }
}
