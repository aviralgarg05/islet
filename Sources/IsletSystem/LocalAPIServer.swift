import Foundation
import IsletCore
import Network

/// HTTP server for the local API, bound to the loopback interface only.
public final class LocalAPIServer {
    public enum ServerError: Error { case invalidPort }

    private var listener: NWListener?
    private let queue = DispatchQueue(label: "islet.api")
    /// Read on `queue`; `update(router:)` swaps it there.
    private var router: APIRouter
    /// Connections that have not delivered a full request by then are dropped. Once the request
    /// has arrived, the connection stays open until the response is sent (long-polls).
    public var requestTimeout: TimeInterval = 5
    /// Most long-polls (requests with `?wait=`) held open at once; more get 503.
    public var maxHeldRequests = 16
    /// Set for the local-network listener: limits requests per client address.
    public var rateLimiter: RateLimiter?
    /// Longest body accepted; a longer `Content-Length` gets 413 before the body is read.
    public var maxBodyBytes = HTTPParser.maxBodyBytes
    /// Most connections open at once (nil: no limit); more get 503.
    public var maxConnections: Int?
    private var openConnections = 0
    private let held = HeldCount()

    /// One connection and whether its request has fully arrived.
    private final class Exchange {
        let conn: NWConnection
        var received = false
        /// Set once the headers have arrived and passed the router's preflight.
        var head: HTTPHead?
        init(_ conn: NWConnection) { self.conn = conn }
    }

    public private(set) var port: UInt16 = 0

    public init(router: APIRouter) {
        self.router = router
    }

    /// Start listening. Pass 0 for an ephemeral port (tests). The completion runs on the
    /// server queue with the bound port or the error.
    /// - Parameters:
    ///   - onAllInterfaces: listen on the local network too (the LAN bridge); loopback otherwise.
    ///   - bonjourName: advertise as `_islet._tcp` so iPhone Shortcuts can find `<mac>.local`.
    public func start(port: UInt16, onAllInterfaces: Bool = false, bonjourName: String? = nil,
                      completion: @escaping (Result<UInt16, Error>) -> Void) {
        let params = NWParameters.tcp
        params.allowLocalEndpointReuse = true
        guard let nwPort = NWEndpoint.Port(rawValue: port) else {
            completion(.failure(ServerError.invalidPort))
            return
        }
        let listener: NWListener
        do {
            if onAllInterfaces {
                listener = try NWListener(using: params, on: nwPort)
                if let bonjourName { listener.service = NWListener.Service(name: bonjourName, type: "_islet._tcp") }
            } else {
                params.requiredLocalEndpoint = NWEndpoint.hostPort(host: .ipv4(.loopback), port: nwPort)
                listener = try NWListener(using: params)
            }
        } catch {
            completion(.failure(error))
            return
        }
        var reported = false
        listener.stateUpdateHandler = { [weak self, weak listener] state in
            switch state {
            case .ready:
                let p = listener?.port?.rawValue ?? 0
                self?.port = p
                if !reported { reported = true; completion(.success(p)) }
            case .failed(let error):
                if !reported { reported = true; completion(.failure(error)) }
                listener?.cancel()
            default:
                break
            }
        }
        listener.newConnectionHandler = { [weak self] conn in self?.accept(conn) }
        self.listener = listener
        listener.start(queue: queue)
    }

    public func stop() {
        listener?.cancel()
        listener = nil
    }

    /// Serve later requests with `router` (a new token, say) without closing the listener.
    public func update(router: APIRouter) {
        queue.async { self.router = router }
    }

    private func accept(_ conn: NWConnection) {
        if let maxConnections {
            guard openConnections < maxConnections else {
                conn.start(queue: queue)
                return respond(conn, .error(503, "too many connections; try again later"))
            }
            openConnections += 1
            var open = true
            conn.stateUpdateHandler = { [weak self] state in
                switch state {
                case .cancelled, .failed:
                    guard open else { return }
                    open = false
                    self?.openConnections -= 1
                default:
                    break
                }
            }
        }
        conn.start(queue: queue)
        if rateLimiter != nil {
            if rateLimiter?.allow(Self.clientKey(conn.endpoint), now: Date()) == false {
                respond(conn, .error(429, "too many requests; slow down"))
                return
            }
        }
        let exchange = Exchange(conn)
        queue.asyncAfter(deadline: .now() + requestTimeout) { [weak exchange] in
            guard let exchange, !exchange.received, exchange.conn.state != .cancelled else { return }
            exchange.conn.cancel()
        }
        receive(exchange, buffer: Data())
    }

    private func receive(_ exchange: Exchange, buffer: Data) {
        let conn = exchange.conn
        conn.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, isComplete, error in
            guard let self else { return conn.cancel() }
            var buffer = buffer
            if let data { buffer.append(data) }
            if exchange.head == nil {
                switch HTTPParser.parseHead(buffer) {
                case .incomplete:
                    break
                case .invalid(let status, let reason):
                    exchange.received = true
                    return self.respond(conn, .error(status, reason))
                case .head(let head):
                    // A wrong token, a refused route or an oversized body is answered now,
                    // without waiting for the body.
                    if let refusal = self.router.preflight(head.request) {
                        exchange.received = true
                        return self.respond(conn, refusal)
                    }
                    if head.bodyLength > self.maxBodyBytes {
                        exchange.received = true
                        return self.respond(conn, .error(413, "body too large; the limit is \(self.maxBodyBytes / 1024) KB"))
                    }
                    exchange.head = head
                }
            }
            if let request = exchange.head?.request(from: buffer) {
                exchange.received = true
                self.handle(request, on: conn)
            } else if isComplete || error != nil {
                conn.cancel()
            } else {
                self.receive(exchange, buffer: buffer)
            }
        }
    }

    private func handle(_ request: HTTPRequest, on conn: NWConnection) {
        let waits = request.query["wait"] != nil
        if waits, !held.acquire(max: maxHeldRequests) {
            return respond(conn, .error(503, "too many requests are waiting; try again later"))
        }
        let router = self.router
        let held = self.held
        let task = Task {
            let response = await router.handle(request)
            if waits { held.release() }
            self.respond(conn, response)
        }
        // A long-poll whose client goes away (hook killed, agent interrupted) stops waiting.
        if waits { watchForHangUp(conn) { task.cancel() } }
    }

    private func watchForHangUp(_ conn: NWConnection, then cancel: @escaping () -> Void) {
        conn.receive(minimumIncompleteLength: 1, maximumLength: 1024) { [weak self] data, _, isComplete, error in
            if isComplete || error != nil {
                cancel()
            } else if data != nil {
                self?.watchForHangUp(conn, then: cancel)
            }
        }
    }

    private func respond(_ conn: NWConnection, _ response: HTTPResponse) {
        conn.send(content: response.serialized(), completion: .contentProcessed { _ in conn.cancel() })
    }
}

/// Number of long-polls held open.
private final class HeldCount: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    func acquire(max: Int) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard count < max else { return false }
        count += 1
        return true
    }

    func release() {
        lock.lock()
        count -= 1
        lock.unlock()
    }
}

/// Writes the discovery file that `isletctl` and other clients read.
public enum APIDiscoveryStore {
    public static func write(_ discovery: APIDiscovery, to url: URL = IsletPaths.apiDiscoveryFile) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(discovery)
        // Create with 0600 before writing so the token is never world-readable.
        if !fm.fileExists(atPath: url.path) {
            fm.createFile(atPath: url.path, contents: nil, attributes: [.posixPermissions: 0o600])
        }
        try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        try data.write(to: url)
    }

    public static func read(from url: URL = IsletPaths.apiDiscoveryFile) -> APIDiscovery? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(APIDiscovery.self, from: data)
    }

    /// Remove the discovery file, but only if it belongs to `pid` (another instance may own it).
    public static func remove(at url: URL = IsletPaths.apiDiscoveryFile, ownedBy pid: Int32 = ProcessInfo.processInfo.processIdentifier) {
        guard let d = read(from: url), d.pid == nil || d.pid == pid else { return }
        try? FileManager.default.removeItem(at: url)
    }

    /// Reuse the previous token so scripts that cached it keep working across restarts.
    public static func loadOrCreateToken(at url: URL = IsletPaths.apiDiscoveryFile) -> String {
        if let existing = read(from: url)?.token, existing.count >= 32 { return existing }
        return APIDiscovery.generateToken()
    }
}
