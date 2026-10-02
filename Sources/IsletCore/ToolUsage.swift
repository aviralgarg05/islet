import Foundation

/// AI tools whose usage Home can show beside Claude's and Codex's, each from a source that
/// never touches another app's sign-in: OpenRouter with the user's own key, Ollama on this
/// Mac, and Copilot with a GitHub token the user makes for Islet. (Cursor offers usage only
/// to team admins, so it isn't here.)
public enum ToolUsageSource: String, Codable, CaseIterable, Sendable, Identifiable {
    case openRouter, ollama, copilot

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .openRouter: return "OpenRouter"
        case .ollama: return "Ollama"
        case .copilot: return "Copilot"
        }
    }

    public var symbol: String {
        switch self {
        case .openRouter: return "arrow.triangle.branch"
        case .ollama: return "cpu"
        case .copilot: return "chevron.left.forwardslash.chevron.right"
        }
    }

    public var tint: String {
        switch self {
        case .openRouter: return "#6467F2"
        case .ollama: return "#B8B8B8"
        case .copilot: return "#8957E5"
        }
    }

    /// The Keychain account for its key or token; Ollama needs none.
    public var keyAccount: String? {
        switch self {
        case .openRouter: return "openrouter"
        case .ollama: return nil
        case .copilot: return "github-copilot"
        }
    }

    /// How long figures stay current before opening the island asks again.
    public var freshFor: TimeInterval {
        switch self {
        case .openRouter: return 5 * 60
        case .ollama: return 15
        case .copilot: return 15 * 60
        }
    }

    public func isOn(_ s: IsletSettings) -> Bool {
        switch self {
        case .openRouter: return s.openRouterUsageEnabled
        case .ollama: return s.ollamaUsageEnabled
        case .copilot: return s.copilotUsageEnabled
        }
    }
}

/// One line on Home: the tool, its main figure, a second line and an optional bar (0–1).
public struct ToolUsageCard: Equatable, Sendable, Identifiable {
    public var source: ToolUsageSource
    public var headline: String
    public var detail: String?
    public var fraction: Double?
    public var updatedAt: Date

    public var id: String { source.rawValue }

    public init(source: ToolUsageSource, headline: String, detail: String? = nil, fraction: Double? = nil, updatedAt: Date) {
        self.source = source
        self.headline = headline
        self.detail = detail
        self.fraction = fraction.map { min(1, max(0, $0)) }
        self.updatedAt = updatedAt
    }

    /// Asked for again when the island opens after this.
    public func isStale(now: Date) -> Bool { now.timeIntervalSince(updatedAt) >= source.freshFor }
}

/// OpenRouter's `GET /api/v1/key`: what the key has spent today and this month, and what is
/// left of its limit when it has one.
public enum OpenRouterUsage {
    public static let host = "openrouter.ai"

    public static func request(key: String) -> WebRequest {
        WebRequest(url: URL(string: "https://\(host)/api/v1/key")!, headers: ["Authorization": "Bearer \(key)", "Accept": "application/json"])
    }

    public static func looksLikeKey(_ key: String) -> Bool {
        key.hasPrefix("sk-or-") && SalesAPI.looksLikeKey(key)
    }

    public static func parse(_ data: Data, now: Date) throws -> ToolUsageCard {
        let o = try ToolJSON.object(data)
        guard let d = o["data"] as? [String: Any] else {
            if let error = o["error"] as? [String: Any], let m = error["message"] as? String { throw WebProblem.message(m) }
            throw WebProblem.unreadable
        }
        let today = ToolJSON.number(d["usage_daily"]) ?? 0
        let month = ToolJSON.number(d["usage_monthly"])
        if let limit = ToolJSON.number(d["limit"]), limit > 0 {
            let left = ToolJSON.number(d["limit_remaining"]) ?? max(0, limit - (ToolJSON.number(d["usage"]) ?? 0))
            return ToolUsageCard(source: .openRouter, headline: "\(dollars(left)) left", detail: "\(dollars(today)) today",
                                 fraction: (limit - left) / limit, updatedAt: now)
        }
        if d["is_free_tier"] as? Bool == true, let free = d["free_model_daily_requests"] as? [String: Any],
           let used = UsageJSON.int(free["used"]), let cap = UsageJSON.int(free["limit"]), cap > 0 {
            return ToolUsageCard(source: .openRouter, headline: "\(used) of \(cap) free requests", detail: "today",
                                 fraction: Double(used) / Double(cap), updatedAt: now)
        }
        return ToolUsageCard(source: .openRouter, headline: "\(dollars(today)) today",
                             detail: month.map { "\(dollars($0)) this month" }, updatedAt: now)
    }

    /// OpenRouter counts in US dollars: "$4.20", or "$0.004" below a cent.
    static func dollars(_ v: Double) -> String {
        if v > 0 && v < 0.01 { return String(format: "$%.3f", v) }
        return String(format: "$%.2f", v)
    }
}

/// Ollama's `GET /api/ps` on this Mac: the models it has loaded and how much memory they take.
public enum OllamaUsage {
    public static let host = "127.0.0.1"
    public static let port = 11434

    public struct Model: Equatable, Sendable {
        public var name: String
        public var bytes: Int64
        public var unloadsAt: Date?

        public init(name: String, bytes: Int64, unloadsAt: Date? = nil) {
            self.name = name
            self.bytes = bytes
            self.unloadsAt = unloadsAt
        }
    }

    public static var request: WebRequest {
        WebRequest(url: URL(string: "http://\(host):\(port)/api/ps")!, headers: ["Accept": "application/json"])
    }

    public static func parse(_ data: Data) throws -> [Model] {
        let o = try ToolJSON.object(data)
        guard let models = o["models"] as? [[String: Any]] else { throw WebProblem.unreadable }
        return models.compactMap { m in
            guard let name = (m["name"] as? String) ?? (m["model"] as? String) else { return nil }
            let bytes = ToolJSON.number(m["size_vram"]).flatMap { $0 > 0 ? $0 : nil } ?? ToolJSON.number(m["size"]) ?? 0
            return Model(name: name, bytes: Int64(bytes), unloadsAt: ToolJSON.date(m["expires_at"]))
        }
    }

    /// "llama3.2 · 3.1 GB" and when it unloads; nil with nothing loaded, so Home stays quiet.
    public static func card(_ models: [Model], now: Date) -> ToolUsageCard? {
        guard let first = models.max(by: { $0.bytes < $1.bytes }) else { return nil }
        let name = first.name.hasSuffix(":latest") ? String(first.name.dropLast(":latest".count)) : first.name
        let total = models.reduce(Int64(0)) { $0 + $1.bytes }
        var detail: String?
        if models.count > 1 {
            detail = "\(models.count) models, \(Format.bytes(total))"
        } else if let at = first.unloadsAt, at > now {
            detail = "Unloads in \(UsageFormat.remaining(until: at, now: now))"
        }
        return ToolUsageCard(source: .ollama, headline: "\(name) · \(Format.bytes(first.bytes))", detail: detail, updatedAt: now)
    }
}

/// GitHub's premium request usage for the signed-in user this month
/// (`GET /users/{login}/settings/billing/premium_request/usage`), with a fine-grained token
/// that has read access to Plan. The login comes from `GET /user` with the same token.
public enum CopilotUsage {
    public static let host = "api.github.com"

    static func headers(_ token: String) -> [String: String] {
        ["Authorization": "Bearer \(token)", "Accept": "application/vnd.github+json", "X-GitHub-Api-Version": "2022-11-28"]
    }

    public static func userRequest(token: String) -> WebRequest {
        WebRequest(url: URL(string: "https://\(host)/user")!, headers: headers(token))
    }

    public static func login(from data: Data) throws -> String {
        let o = try ToolJSON.object(data)
        guard let login = o["login"] as? String, isLogin(login) else { throw WebProblem.unreadable }
        return login
    }

    /// GitHub logins: letters, digits and single hyphens, up to 39 characters.
    static func isLogin(_ s: String) -> Bool {
        (1...39).contains(s.count) && s.unicodeScalars.allSatisfy { $0.isASCII && (CharacterSet.alphanumerics.contains($0) || $0 == "-") }
    }

    /// GitHub's billing months run in UTC, so this month is UTC's unless a test says otherwise.
    public static let billingCalendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC") ?? TimeZone(secondsFromGMT: 0)!
        return c
    }()

    public static func usageRequest(login: String, token: String, now: Date, calendar: Calendar = billingCalendar) -> WebRequest? {
        guard isLogin(login) else { return nil }
        let c = calendar.dateComponents([.year, .month], from: now)
        let url = WebRequest.url("https://\(host)/users/\(login)/settings/billing/premium_request/usage",
                                 [("year", String(c.year ?? 2026)), ("month", String(c.month ?? 1))])
        return WebRequest(url: url, headers: headers(token))
    }

    /// Premium requests used this month: every Copilot item's gross quantity.
    public static func requestsUsed(_ data: Data) throws -> Double {
        let o = try ToolJSON.object(data)
        guard let items = o["usageItems"] as? [[String: Any]] else { throw WebProblem.unreadable }
        return items.filter { ($0["product"] as? String)?.localizedCaseInsensitiveContains("copilot") ?? true }
            .reduce(0) { $0 + (ToolJSON.number($1["grossQuantity"]) ?? 0) }
    }

    public static func card(used: Double, plan: CopilotPlan, now: Date) -> ToolUsageCard {
        let count = Int(used.rounded())
        return ToolUsageCard(source: .copilot, headline: "\(count) of \(plan.rawValue) requests", detail: "Premium, this month",
                             fraction: used / Double(plan.rawValue), updatedAt: now)
    }
}
