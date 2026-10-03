import Foundation
import IsletCore

/// Sends the requests the tools make (sales, stocks, AI usage) and reads the replies with the
/// parsers in IsletCore.
///
/// An ephemeral `URLSession` with no cache, cookies or credential store, made on first use, so
/// an Islet with every tool off never makes one. Each request must be HTTPS to the hosts its
/// tool names (or HTTP to Ollama on 127.0.0.1), and redirects are refused, so a key header
/// can't follow a redirect anywhere else. Nothing is logged.
/// Refuses every redirect, for a session that isn't its own delegate. The reply to the request
/// Islet made is what counts: a redirect could carry what the request says, a song's title or a
/// place's name, to a host the user never agreed to.
final class NoRedirects: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

public final class ToolsService: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    public struct Reply: Sendable {
        public var status: Int
        public var data: Data
    }

    /// Replies larger than this are refused while they arrive, so a runaway reply is never
    /// held in full (a page of a few hundred orders is well under it).
    public static let maxReply = 8 * 1024 * 1024

    private let protocolClasses: [AnyClass]
    private let timeout: TimeInterval
    private let maxReply: Int
    private let lock = NSLock()
    private var made: URLSession?

    /// `protocolClasses` lets tests answer requests without the network.
    public init(protocolClasses: [AnyClass] = [], timeout: TimeInterval = 20, maxReply: Int = ToolsService.maxReply) {
        self.protocolClasses = protocolClasses
        self.timeout = timeout
        self.maxReply = maxReply
    }

    private var session: URLSession {
        lock.withLock {
            if let s = made { return s }
            let c = URLSessionConfiguration.ephemeral
            c.urlCache = nil
            c.httpCookieStorage = nil
            c.httpShouldSetCookies = false
            c.urlCredentialStorage = nil
            c.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
            c.timeoutIntervalForRequest = timeout
            c.timeoutIntervalForResource = timeout * 2
            c.waitsForConnectivity = false
            if !protocolClasses.isEmpty { c.protocolClasses = protocolClasses + (c.protocolClasses ?? []) }
            let s = URLSession(configuration: c, delegate: self, delegateQueue: nil)
            made = s
            return s
        }
    }

    /// Never follow a redirect: the reply to the original request is what counts.
    public func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                           newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }

    /// Sends `r` if it goes to one of `hosts`. Throws `WebProblem.unreachable` when there is no
    /// connection; a reply of any status is returned.
    public func send(_ r: WebRequest, hosts: Set<String>) async throws -> Reply {
        guard r.isAllowed(hosts: hosts) else { throw WebProblem.blocked }
        var request = URLRequest(url: r.url, cachePolicy: .reloadIgnoringLocalAndRemoteCacheData, timeoutInterval: timeout)
        request.httpMethod = r.method
        request.httpShouldHandleCookies = false
        for (name, value) in r.headers { request.setValue(value, forHTTPHeaderField: name) }
        request.httpBody = r.body
        do {
            let (bytes, response) = try await session.bytes(for: request)
            // Too long by its own account, or once it grows past the cap: stop reading.
            guard response.expectedContentLength <= Int64(maxReply) else {
                bytes.task.cancel()
                throw WebProblem.unreadable
            }
            var data = Data()
            if response.expectedContentLength > 0 { data.reserveCapacity(Int(response.expectedContentLength)) }
            for try await byte in bytes {
                data.append(byte)
                if data.count > maxReply {
                    bytes.task.cancel()
                    throw WebProblem.unreadable
                }
            }
            return Reply(status: (response as? HTTPURLResponse)?.statusCode ?? 0, data: data)
        } catch let e as WebProblem {
            throw e
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw WebProblem.unreachable
        }
    }

    /// Sends and checks the status; the body of a successful reply.
    private func fetch(_ r: WebRequest, hosts: Set<String>) async throws -> Data {
        let reply = try await send(r, hosts: hosts)
        if let problem = WebProblem.from(status: reply.status) { throw problem }
        return reply.data
    }

    // MARK: Sales

    /// Today's takings for one store: every page since `since`, up to `SalesAPI.maxPages`.
    public func sales(_ store: SalesStore, key: String, shop: String?, since: Date, now: Date) async -> StoreSales {
        var total = SalesFigures()
        var cursor: SalesCursor?
        var page: Int? = Self.firstPage(store)
        let hosts = SalesAPI.hosts(store, shop: shop)
        do {
            for _ in 0..<SalesAPI.maxPages {
                let request = try SalesAPI.request(store, key: key, shop: shop, since: since, cursor: cursor)
                let data = try await fetch(request, hosts: hosts)
                let result = try SalesAPI.parse(store, data: data, since: since, page: page)
                total.add(result.figures)
                guard let next = result.next else { break }
                cursor = next
                if case .page(let n) = next { page = n }
            }
            return StoreSales(store: store, figures: total, updatedAt: now)
        } catch let p as WebProblem {
            return StoreSales(store: store, problem: p, updatedAt: now)
        } catch {
            return StoreSales(store: store, problem: .unreachable, updatedAt: now)
        }
    }

    static func firstPage(_ store: SalesStore) -> Int? {
        switch store {
        case .lemonSqueezy, .polar: return 1
        case .dodo: return 0
        default: return nil
        }
    }

    // MARK: Stocks

    /// One quote. An unknown symbol says so in the source's words.
    public func quote(_ symbol: String) async -> Result<StockQuote, WebProblem> {
        guard let request = StocksAPI.request(symbol: symbol) else { return .failure(.notFound) }
        do {
            let reply = try await send(request, hosts: [StocksAPI.host])
            // A 404 still carries the reason ("No data found, symbol may be delisted").
            if reply.status == 404 {
                do { _ = try StocksAPI.parse(reply.data) } catch let p as WebProblem where p != .unreadable { return .failure(p) } catch {}
                return .failure(.notFound)
            }
            if let problem = WebProblem.from(status: reply.status) { return .failure(problem) }
            return .success(try StocksAPI.parse(reply.data))
        } catch {
            return .failure(error as? WebProblem ?? .unreachable)
        }
    }

    /// Quotes for every symbol at once, by symbol.
    public func quotes(_ symbols: [String]) async -> [String: Result<StockQuote, WebProblem>] {
        await withTaskGroup(of: (String, Result<StockQuote, WebProblem>).self) { group in
            for s in symbols { group.addTask { (s, await self.quote(s)) } }
            var out: [String: Result<StockQuote, WebProblem>] = [:]
            for await (s, r) in group { out[s] = r }
            return out
        }
    }

    // MARK: AI usage

    public func openRouter(key: String, now: Date) async -> Result<ToolUsageCard, WebProblem> {
        await result { try OpenRouterUsage.parse(try await self.fetch(OpenRouterUsage.request(key: key), hosts: [OpenRouterUsage.host]), now: now) }
    }

    /// Ollama on this Mac. Nil when it is running with nothing loaded; `.unreachable` when it
    /// isn't running.
    public func ollama(now: Date) async -> Result<ToolUsageCard?, WebProblem> {
        await result { OllamaUsage.card(try OllamaUsage.parse(try await self.fetch(OllamaUsage.request, hosts: [OllamaUsage.host])), now: now) }
    }

    public func copilotLogin(token: String) async -> Result<String, WebProblem> {
        await result { try CopilotUsage.login(from: try await self.fetch(CopilotUsage.userRequest(token: token), hosts: [CopilotUsage.host])) }
    }

    /// Premium requests used this month.
    public func copilot(token: String, login: String, now: Date) async -> Result<Double, WebProblem> {
        await result {
            guard let request = CopilotUsage.usageRequest(login: login, token: token, now: now) else { throw WebProblem.notFound }
            return try CopilotUsage.requestsUsed(try await self.fetch(request, hosts: [CopilotUsage.host]))
        }
    }

    private func result<T>(_ work: () async throws -> T) async -> Result<T, WebProblem> {
        do {
            return .success(try await work())
        } catch {
            return .failure(error as? WebProblem ?? .unreachable)
        }
    }

    /// Stop using the network session (tests).
    public func invalidate() { lock.withLock { made?.invalidateAndCancel(); made = nil } }
}
