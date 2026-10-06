import Foundation

/// One request a tool makes on the user's behalf: sales, stocks or AI usage. Built here, sent
/// by `ToolsService` (CasementSystem), which only sends what `isAllowed` passes and never follows
/// a redirect, so a key header can't end up anywhere else.
public struct WebRequest: Equatable, Sendable {
    public var url: URL
    public var method: String
    public var headers: [String: String]
    public var body: Data?

    public init(url: URL, method: String = "GET", headers: [String: String] = [:], body: Data? = nil) {
        self.url = url
        self.method = method
        self.headers = headers
        self.body = body
    }

    /// HTTPS to one of `hosts` on the standard port, or plain HTTP to Ollama on this Mac.
    public func isAllowed(hosts: Set<String>) -> Bool {
        guard let host = url.host?.lowercased() else { return false }
        if url.scheme == "http" { return host == "127.0.0.1" && url.port == OllamaUsage.port && hosts.contains(host) }
        return url.scheme == "https" && url.port == nil && hosts.contains(host)
    }

    /// The URL built from `base` and query items, with brackets and other reserved characters
    /// in names and values percent-encoded.
    static func url(_ base: String, _ query: [(String, String)] = []) -> URL {
        guard !query.isEmpty else { return URL(string: base)! }
        let q = query.map { name, value in "\(encode(name))=\(encode(value))" }.joined(separator: "&")
        return URL(string: base + "?" + q)!
    }

    /// Unreserved ASCII stays; everything else is percent-encoded.
    static let unreserved = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")

    static func encode(_ s: String) -> String { s.addingPercentEncoding(withAllowedCharacters: unreserved) ?? "" }
}

/// What went wrong asking a service, in words for the page that shows it.
public enum WebProblem: Error, Equatable, Sendable {
    /// 401 or 403: the key or token was turned down.
    case rejectedKey
    /// 404: the store or account wasn't found.
    case notFound
    /// 429: asked too often.
    case rateLimited
    /// Any other failing status, kept for the log; the text never shows it.
    case server(Int)
    /// A request Casement won't send (it would go somewhere other than the service).
    case blocked
    /// The reply wasn't what the service documents.
    case unreadable
    /// No connection, a timeout or a refused connection.
    case unreachable
    /// The service said what was wrong.
    case message(String)
    /// The key isn't in the Keychain any more.
    case missingKey

    public static func from(status: Int) -> WebProblem? {
        switch status {
        case 200..<300: return nil
        case 401, 403: return .rejectedKey
        case 404: return .notFound
        case 429: return .rateLimited
        default: return .server(status)
        }
    }

    /// A word or two for a row beside the service's name, with `text` in its help: what to do
    /// when there is something to do, else what went wrong.
    public var shortText: String {
        switch self {
        case .rejectedKey, .missingKey: return "Reconnect"
        case .unreachable: return "Can\u{2019}t connect"
        case .rateLimited, .server: return "Try again later"
        case .notFound: return "Not found"
        case .unreadable, .message: return "Couldn\u{2019}t read"
        case .blocked: return "Couldn\u{2019}t check"
        }
    }

    /// One plain sentence, naming the service.
    public func text(_ service: String) -> String {
        switch self {
        case .rejectedKey: return "\(service) turned the key down. Paste a new one in Settings."
        case .notFound: return "\(service) couldn\u{2019}t find that account."
        case .rateLimited: return "\(service) asked Casement to wait. It tries again later."
        case .server: return "\(service) is having problems right now. Casement tries again later."
        case .blocked: return "Casement couldn\u{2019}t check \(service)."
        case .unreadable: return "\(service) sent something Casement can\u{2019}t read."
        case .unreachable: return "Couldn\u{2019}t reach \(service)."
        case .message(let m): return "\(service): \(m)"
        case .missingKey: return "\(service) needs its key again. Paste it in Settings."
        }
    }
}

/// Lenient JSON reading shared by the tool parsers.
enum ToolJSON {
    static func object(_ data: Data) throws -> [String: Any] {
        guard let o = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { throw WebProblem.unreadable }
        return o
    }

    static func number(_ v: Any?) -> Double? { UsageJSON.number(v) }

    /// A whole number from someone else's API. Clamped, because `Int64(_:)` traps beyond its
    /// range and these figures are whatever the service sent: a field in the wrong unit, a
    /// value in the smallest currency unit of a currency that has none, or plain nonsense.
    static func whole(_ v: Double) -> Int64 {
        guard v.isFinite else { return 0 }
        return Int64(min(max(v, -9e18), 9e18))
    }

    /// `a + b`, pinned to the ends of `Int64` instead of trapping. `whole` keeps one figure in
    /// range, but two of them near its ceiling still overflow when added, and these are summed
    /// per currency and across pages: a service sending one amount in the wrong unit would
    /// otherwise end Casement rather than show a silly total.
    static func sum(_ a: Int64, _ b: Int64) -> Int64 {
        let (total, overflowed) = a.addingReportingOverflow(b)
        guard overflowed else { return total }
        return b > 0 ? .max : .min
    }

    static func date(_ v: Any?) -> Date? {
        if let s = v as? String { return UsageJSON.iso(s) ?? isoWithoutZone(s) }
        return UsageJSON.date(v)
    }

    /// "2026-10-01T09:30:00.123456" and "2026-10-01 09:30:00 UTC" as some services send them.
    static func isoWithoutZone(_ s: String) -> Date? {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        for format in ["yyyy-MM-dd'T'HH:mm:ss.SSSSSS", "yyyy-MM-dd'T'HH:mm:ss", "yyyy-MM-dd HH:mm:ss 'UTC'", "yyyy-MM-dd'T'HH:mm:ss.SSSSSSZZZZZ"] {
            f.dateFormat = format
            if let d = f.date(from: s) { return d }
        }
        return nil
    }

    /// UTC ISO 8601 with a Z, as every service here accepts.
    static func iso(_ date: Date) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        f.timeZone = TimeZone(identifier: "UTC")
        return f.string(from: date)
    }
}
