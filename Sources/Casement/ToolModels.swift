import Foundation
import CasementCore
import CasementSystem
import Observation

// The state behind the tools under "More" (sales, stocks, the teleprompter, the mirror) and
// the extra AI usage on Home. None of them keeps a timer of its own: the app's one deadline
// timer (`AppModel.reschedule()`) asks each for its next moment through `onChange`.

// MARK: - Sales

/// Today's takings from the connected stores. Asked for every 15 minutes while the feature is
/// on and the Mac is unlocked (`SalesSchedule`), and when the Sales page opens with figures a
/// minute old. Keys are read from the Keychain only to send a request.
@MainActor
@Observable
final class SalesModel {
    private(set) var stores: [StoreSales] = []
    private(set) var lastRefresh: Date?
    private(set) var refreshing = false
    private(set) var locked = false

    @ObservationIgnored private(set) var settings = SalesSettings()
    @ObservationIgnored let service: ToolsService
    @ObservationIgnored let secrets: SecretStore
    /// The deadline may have moved.
    @ObservationIgnored var onChange: (() -> Void)?
    @ObservationIgnored private let lockMonitor = UnlockMonitor()
    /// Low Power Mode turning off brings the 15-minute rhythm back without waiting for
    /// something else to move the deadline.
    @ObservationIgnored private var powerObserver: NSObjectProtocol?
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored var calendar = Calendar.current

    init(service: ToolsService, secrets: SecretStore) {
        self.service = service
        self.secrets = secrets
    }

    var isOn: Bool { settings.enabled && !settings.stores.isEmpty }

    func apply(_ s: SalesSettings) {
        settings = s
        if isOn {
            lockMonitor.onLock = { [weak self] in self?.setLocked(true) }
            lockMonitor.onUnlock = { [weak self] in self?.setLocked(false) }
            lockMonitor.start()
            if powerObserver == nil {
                powerObserver = NotificationCenter.default.addObserver(forName: .NSProcessInfoPowerStateDidChange, object: nil,
                                                                       queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated { self?.onChange?() }
                }
            }
        } else {
            lockMonitor.stop()
            locked = false
            if let powerObserver { NotificationCenter.default.removeObserver(powerObserver) }
            powerObserver = nil
        }
        if !s.enabled {
            task?.cancel()
            task = nil
            refreshing = false
            stores = []
            lastRefresh = nil
        } else {
            stores = stores.filter { s.stores.contains($0.store) }
            // A store with no figures yet: ask again soon. (Connecting in Settings already
            // brought the new store's figures.) While a refresh is under way, `finish` checks.
            if !refreshing, s.stores.contains(where: { store in !stores.contains { $0.store == store } }) { lastRefresh = nil }
        }
        onChange?()
    }

    private func setLocked(_ value: Bool) {
        locked = value
        onChange?()
    }

    func nextRefresh(now: Date) -> Date? {
        guard !refreshing else { return nil }
        return SalesSchedule.nextRefresh(last: lastRefresh, enabled: settings.enabled, hasStores: !settings.stores.isEmpty,
                                         locked: locked, lowPower: ProcessInfo.processInfo.isLowPowerModeEnabled, now: now,
                                         calendar: calendar)
    }

    func refreshIfDue(now: Date) {
        if let due = nextRefresh(now: now), due <= now { refresh(now: now) }
    }

    func pageOpened(now: Date = Date()) {
        if isOn, SalesSchedule.isStale(lastRefresh, now: now) { refresh(now: now) }
    }

    /// Ask every connected store for today's takings, together.
    func refresh(now: Date = Date()) {
        guard isOn, !refreshing else { return }
        let since = SalesSchedule.startOfDay(now, calendar: calendar)
        let jobs = settings.stores.map { ($0, secrets.read($0.keyAccount)) }
        let shop = settings.shopifyStore
        let service = service
        refreshing = true
        lastRefresh = now
        task = Task { [weak self] in
            let results = await withTaskGroup(of: StoreSales.self) { group in
                for (store, key) in jobs {
                    group.addTask {
                        guard let key else { return StoreSales(store: store, problem: .missingKey, updatedAt: now) }
                        return await service.sales(store, key: key, shop: shop, since: since, now: now)
                    }
                }
                var out: [StoreSales] = []
                for await r in group { out.append(r) }
                return out
            }
            guard !Task.isCancelled else { return }
            self?.finish(results)
        }
        onChange?()
    }

    private func finish(_ results: [StoreSales]) {
        refreshing = false
        let merged = SalesSummary.merged(results, into: stores, order: settings.stores)
        stores = merged.stores
        // A store added while this refresh was under way is asked for next.
        if merged.missing { lastRefresh = nil }
        onChange?()
    }

    var total: SalesFigures { SalesSummary.total(stores) }

    func hasKey(_ store: SalesStore) -> Bool { secrets.contains(store.keyAccount) }

    /// Checks the key by asking for today's takings, then keeps it in the Keychain.
    func connect(_ store: SalesStore, key raw: String, shop: String, now: Date = Date()) async throws -> StoreSales {
        let key = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard SalesAPI.looksLikeKey(key) else { throw WebProblem.message("that doesn’t look like a key.") }
        if store == .shopify, SalesAPI.shopifyHost(shop) == nil { throw WebProblem.message("type the store’s address, such as example.myshopify.com.") }
        let result = await service.sales(store, key: key, shop: shop, since: SalesSchedule.startOfDay(now, calendar: calendar), now: now)
        if let problem = result.problem { throw problem }
        try secrets.save(key, account: store.keyAccount)
        stores.removeAll { $0.store == store }
        stores.append(result)
        return result
    }

    func disconnect(_ store: SalesStore) {
        try? secrets.delete(store.keyAccount)
        stores.removeAll { $0.store == store }
    }

    /// Fixed figures for offline snapshots.
    func showDemo(now: Date, stores connected: [SalesStore] = [.stripe, .shopify, .gumroad]) {
        settings = SalesSettings(enabled: true, stores: connected, shopifyStore: "example")
        stores = [
            StoreSales(store: .stripe, figures: SalesFigures(amounts: ["GBP": 128_450], orders: 23), updatedAt: now),
            StoreSales(store: .shopify, figures: SalesFigures(amounts: ["GBP": 46_200, "EUR": 8_900], orders: 7), updatedAt: now),
            StoreSales(store: .gumroad, problem: .rejectedKey, updatedAt: now),
        ]
        lastRefresh = now.addingTimeInterval(-4 * 60)
    }
}

// MARK: - Stocks

/// The watchlist's prices, asked for only while the Stocks page is open.
@MainActor
@Observable
final class StocksModel {
    private(set) var quotes: [String: StockQuote] = [:]
    private(set) var problems: [String: WebProblem] = [:]
    private(set) var lastRefresh: Date?
    private(set) var refreshing = false
    private(set) var symbols: [String] = []

    @ObservationIgnored let service: ToolsService
    @ObservationIgnored var onChange: (() -> Void)?
    @ObservationIgnored private(set) var pageOpen = false
    @ObservationIgnored private var enabled = false
    @ObservationIgnored private var task: Task<Void, Never>?

    init(service: ToolsService) { self.service = service }

    func apply(_ s: StocksSettings) {
        enabled = s.enabled
        let added = !Set(s.symbols).isSubset(of: Set(symbols))
        symbols = s.enabled ? s.symbols : []
        quotes = quotes.filter { symbols.contains($0.key) }
        problems = problems.filter { symbols.contains($0.key) }
        if !s.enabled {
            task?.cancel()
            refreshing = false
            lastRefresh = nil
        } else if added, pageOpen {
            refresh()
        }
        onChange?()
    }

    func nextRefresh(now: Date) -> Date? {
        guard enabled, !refreshing else { return nil }
        return StocksSchedule.nextRefresh(last: lastRefresh, pageOpen: pageOpen, hasSymbols: !symbols.isEmpty, now: now)
    }

    func refreshIfDue(now: Date) {
        if let due = nextRefresh(now: now), due <= now { refresh(now: now) }
    }

    func setPageOpen(_ open: Bool, now: Date = Date()) {
        guard open != pageOpen else { return }
        pageOpen = open
        if open, enabled, StocksSchedule.isStale(lastRefresh, now: now) { refresh(now: now) }
        onChange?()
    }

    func refresh(now: Date = Date()) {
        guard enabled, !refreshing, !symbols.isEmpty else { return }
        let list = symbols
        let service = service
        refreshing = true
        lastRefresh = now
        task = Task { [weak self] in
            let results = await service.quotes(list)
            guard !Task.isCancelled else { return }
            self?.finish(results)
        }
        onChange?()
    }

    private func finish(_ results: [String: Result<StockQuote, WebProblem>]) {
        refreshing = false
        for (symbol, r) in results where symbols.contains(symbol) {
            switch r {
            case .success(let q):
                quotes[symbol] = q
                problems[symbol] = nil
            case .failure(let p):
                problems[symbol] = p
            }
        }
        onChange?()
    }

    /// Fixed prices for offline snapshots.
    func showDemo(now: Date) {
        enabled = true
        symbols = ["AAPL", "MSFT", "^GSPC", "NVDA"]
        func wave(_ start: Double, _ end: Double, _ wobble: Double) -> [Double] {
            (0..<48).map { i in
                let t = Double(i) / 47
                return start + (end - start) * t + sin(t * 9) * wobble + sin(t * 23) * wobble * 0.4
            }
        }
        quotes = [
            "AAPL": StockQuote(symbol: "AAPL", name: "Apple Inc.", price: 229.06, previousClose: 226.40, currency: "USD", closes: wave(226.8, 229.06, 0.9)),
            "MSFT": StockQuote(symbol: "MSFT", name: "Microsoft Corporation", price: 507.12, previousClose: 511.30, currency: "USD", closes: wave(511, 507.12, 1.6)),
            "^GSPC": StockQuote(symbol: "^GSPC", name: "S&P 500", price: 6_688.46, previousClose: 6_661.21, currency: "USD", closes: wave(6_664, 6_688.46, 9)),
            "NVDA": StockQuote(symbol: "NVDA", name: "NVIDIA Corporation", price: 186.58, previousClose: 181.85, currency: "USD", closes: wave(182, 186.58, 1.2)),
        ]
        problems = [:]
        lastRefresh = now.addingTimeInterval(-40)
    }

    /// Snapshots: these symbols couldn't be read; those in `stale` keep the price from before.
    func showDemoProblems(_ list: [String: WebProblem], stale: Set<String>) {
        for (symbol, problem) in list {
            if !symbols.contains(symbol) { symbols.append(symbol) }
            problems[symbol] = problem
            if !stale.contains(symbol) { quotes[symbol] = nil }
        }
    }
}

// MARK: - AI usage

/// OpenRouter, Ollama and Copilot on Home, asked for when the island opens and the figures
/// are older than the source allows (`ToolUsageSource.freshFor`). Nothing runs while it is closed.
@MainActor
@Observable
final class ToolUsageModel {
    private(set) var cards: [ToolUsageSource: ToolUsageCard] = [:]
    /// The last problem per source, for Settings.
    private(set) var problems: [ToolUsageSource: WebProblem] = [:]

    @ObservationIgnored let service: ToolsService
    @ObservationIgnored let secrets: SecretStore
    @ObservationIgnored private var settings = CasementSettings()
    @ObservationIgnored private var attempted: [ToolUsageSource: Date] = [:]
    @ObservationIgnored private var inFlight: Set<ToolUsageSource> = []
    @ObservationIgnored private var copilotLogin: String?
    /// Copilot's count, kept so a different plan redraws the bar without asking again.
    @ObservationIgnored private var copilotUsed: (count: Double, at: Date)?

    init(service: ToolsService, secrets: SecretStore) {
        self.service = service
        self.secrets = secrets
    }

    func apply(_ s: CasementSettings) {
        let was = settings
        settings = s
        for source in ToolUsageSource.allCases where !source.isOn(s) {
            cards[source] = nil
            problems[source] = nil
            attempted[source] = nil
        }
        if !s.copilotUsageEnabled { copilotUsed = nil }
        // A different plan redraws Copilot's bar straight away.
        if was.copilotPlan != s.copilotPlan, let used = copilotUsed, cards[.copilot] != nil {
            cards[.copilot] = CopilotUsage.card(used: used.count, plan: s.copilotPlan, now: used.at)
        }
    }

    /// Cards for Home, in a steady order.
    var visible: [ToolUsageCard] {
        [ToolUsageSource.openRouter, .copilot, .ollama].compactMap { cards[$0] }
    }

    /// The island opened: ask again where the figures are old. A failure waits as long as a
    /// success would before trying again.
    func islandOpened(now: Date = Date()) {
        for source in ToolUsageSource.allCases where source.isOn(settings) {
            if let last = attempted[source], now.timeIntervalSince(last) < source.freshFor { continue }
            refresh(source, now: now)
        }
    }

    func refresh(_ source: ToolUsageSource, now: Date = Date()) {
        guard source.isOn(settings), !inFlight.contains(source) else { return }
        attempted[source] = now
        let key = source.keyAccount.flatMap { secrets.read($0) }
        if source.keyAccount != nil, key == nil {
            problems[source] = .missingKey
            cards[source] = nil
            return
        }
        inFlight.insert(source)
        let service = service
        let login = copilotLogin
        Task { [weak self] in
            switch source {
            case .openRouter:
                let outcome = await service.openRouter(key: key ?? "", now: now)
                self?.finish(source, outcome.map { Optional($0) })
            case .ollama:
                self?.finish(source, await service.ollama(now: now))
            case .copilot:
                let token = key ?? ""
                var name = login
                if name == nil {
                    switch await service.copilotLogin(token: token) {
                    case .success(let l): name = l
                    case .failure(let p): return self?.finish(source, .failure(p)) ?? ()
                    }
                }
                let outcome = await service.copilot(token: token, login: name ?? "", now: now)
                self?.finishCopilot(outcome, login: name, now: now)
            }
        }
    }

    private func finishCopilot(_ outcome: Result<Double, WebProblem>, login: String?, now: Date) {
        if case .success(let used) = outcome {
            copilotLogin = login
            copilotUsed = (used, now)
        }
        finish(.copilot, outcome.map { CopilotUsage.card(used: $0, plan: settings.copilotPlan, now: now) })
    }

    private func finish(_ source: ToolUsageSource, _ outcome: Result<ToolUsageCard?, WebProblem>) {
        inFlight.remove(source)
        guard source.isOn(settings) else { return }
        switch outcome {
        case .success(let card):
            cards[source] = card
            problems[source] = nil
        case .failure(let p):
            // Ollama not running is normal: no card, no complaint.
            cards[source] = nil
            problems[source] = source == .ollama && p == .unreachable ? nil : p
            if source == .copilot { copilotLogin = nil }
        }
    }

    func maskedKey(_ source: ToolUsageSource) -> String? {
        guard let account = source.keyAccount, let key = secrets.read(account) else { return nil }
        return AskKeys.masked(key)
    }

    /// Checks a pasted key with the service, then keeps it in the Keychain.
    func saveKey(_ raw: String, for source: ToolUsageSource, now: Date = Date()) async throws {
        let key = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let account = source.keyAccount else { return }
        switch source {
        case .openRouter:
            guard OpenRouterUsage.looksLikeKey(key) else { throw WebProblem.message("that doesn’t look like an OpenRouter key. It starts with sk-or-.") }
            let card = try await service.openRouter(key: key, now: now).get()
            try secrets.save(key, account: account)
            cards[.openRouter] = settings.openRouterUsageEnabled ? card : nil
        case .copilot:
            guard SalesAPI.looksLikeKey(key) else { throw WebProblem.message("that doesn’t look like a GitHub key.") }
            let login = try await service.copilotLogin(token: key).get()
            try secrets.save(key, account: account)
            copilotLogin = login
            problems[source] = nil
            refresh(.copilot, now: now)
            return
        case .ollama:
            return
        }
        problems[source] = nil
        attempted[source] = now
    }

    func removeKey(_ source: ToolUsageSource) {
        guard let account = source.keyAccount else { return }
        try? secrets.delete(account)
        cards[source] = nil
        if source == .copilot {
            copilotLogin = nil
            copilotUsed = nil
        }
    }

    /// Fixed figures for offline snapshots.
    func showDemo(now: Date) {
        cards = [
            .openRouter: ToolUsageCard(source: .openRouter, headline: "$8.90 left", detail: "$1.12 today", fraction: 0.82, updatedAt: now),
            .copilot: CopilotUsage.card(used: 142, plan: .pro, now: now),
            .ollama: OllamaUsage.card([OllamaUsage.Model(name: "llama3.2:latest", bytes: 3_100_000_000, unloadsAt: now.addingTimeInterval(240))], now: now)!,
        ]
    }

    func showDemoProblem(_ problem: WebProblem?, for source: ToolUsageSource) { problems[source] = problem }
}
