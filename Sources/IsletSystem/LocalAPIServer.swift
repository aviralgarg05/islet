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
    /// Connections whose request line and headers have not all arrived by then are dropped
    /// (nil: only `requestTimeout` applies). Set for the local-network listener.
    public var headerTimeout: TimeInterval?
    /// Most long-polls (requests with `?wait=`) held open at once; more get 503.
    public var maxHeldRequests = 16
    /// Set for the local-network listener: limits requests per client address.
    public var rateLimiter: RateLimiter?
    /// Longest body accepted; a longer `Content-Length` gets 413 before the body is read.
    public var maxBodyBytes = HTTPParser.maxBodyBytes
    /// Most connections open at once (nil: no limit); more get 503.
    public var maxConnections: Int?
    /// Most connections open at once from one client, keyed as for the rate limit (nil: no
    /// limit); more get 429.
    public var maxConnectionsPerClient: Int?
    /// After refusing a request from its headers, how long at most to keep reading and dropping
    /// the body the client is still sending before closing (see `refuse`).
    public var lingerTimeout: TimeInterval = 5
    /// Most refused connections draining their bodies at once; past that they close at once.
    static let maxLingering = 16
    /// How much body to read and drop after a head that didn't parse. Its length is unknown, so
    /// this is only enough for a client still uploading to read the answer that explains it.
    static let invalidDrainBytes = 16 * 1024
    /// How long such a refusal waits before closing. A head that didn't parse says nothing about
    /// whether more is coming, and a peer that wrote nonsense and left the socket open looks
    /// exactly like one still uploading, so this is long enough to read the answer and no longer:
    /// a few such sockets would otherwise hold the bridge's connection slots for `lingerTimeout`.
    static let invalidLinger: TimeInterval = 0.5
    /// Read and changed on `queue`.
    private var connections = ConnectionTally()
    private var lingering = 0
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

    /// Connections open at once on loopback. Generous: `maxHeldRequests` long-polls, the
    /// refusals draining their bodies and a few clients at work all fit, but a local process
    /// can't hold sockets open until Islet runs out of descriptors.
    public static let loopbackConnectionLimit = 128
    /// A client sends its headers as soon as it connects, so one that hasn't is idling on a
    /// slot. Longer than the bridge's, since nothing here comes over a network.
    public static let loopbackHeaderTimeout: TimeInterval = 4

    /// The loopback listener: every route, with the limits above, as `localNetwork` does for
    /// the bridge. Connections are admitted before the token is checked, so they are counted.
    ///
    /// No per-client cap here, unlike the bridge. Every connection arrives from 127.0.0.1, so
    /// one key would cover all of them: `isletctl`, the MCP server, the status line, agent hooks
    /// and the held approvals would share a single bucket with any runaway process, be refused
    /// together, and be told "too many connections from this device". The whole limit does the
    /// work instead.
    public static func loopback(router: APIRouter) -> LocalAPIServer {
        let server = LocalAPIServer(router: router)
        server.maxConnections = loopbackConnectionLimit
        server.headerTimeout = loopbackHeaderTimeout
        return server
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
        let client = Self.clientKey(conn.endpoint)
        switch connections.admit(client, limit: maxConnections, perClient: maxConnectionsPerClient) {
        case .admitted:
            break
        case .full:
            conn.start(queue: queue)
            return respond(conn, .error(503, "too many connections; try again later"))
        case .clientFull:
            conn.start(queue: queue)
            return respond(conn, .error(429, "too many connections from this device; try again when one has finished"))
        }
        // Counted until it closes, including while it lingers after a refusal.
        var open = true
        conn.stateUpdateHandler = { [weak self] state in
            switch state {
            case .cancelled, .failed:
                guard open else { return }
                open = false
                self?.connections.release(client)
            default:
                break
            }
        }
        conn.start(queue: queue)
        if rateLimiter?.allow(client, now: Date()) == false {
            return respond(conn, .error(429, "too many requests; slow down"))
        }
        let exchange = Exchange(conn)
        queue.asyncAfter(deadline: .now() + requestTimeout) { [weak exchange] in
            guard let exchange, !exchange.received, exchange.conn.state != .cancelled else { return }
            exchange.conn.cancel()
        }
        if let headerTimeout, headerTimeout < requestTimeout {
            queue.asyncAfter(deadline: .now() + headerTimeout) { [weak exchange] in
                guard let exchange, exchange.head == nil, !exchange.received, exchange.conn.state != .cancelled else { return }
                exchange.conn.cancel()
            }
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
                    // Through `refuse` like the two refusals below, for the reason its comment
                    // gives: a chunked upload is still sending when it gets its 411, and
                    // closing with data unread resets the connection, so the client sees
                    // "connection reset" instead of the answer that explains the problem. The
                    // head didn't parse, so how much is still coming is unknown: a client that
                    // has already finished sending gets no linger at all, and one still sending
                    // gets enough of a drain to read the answer. Without the first of those, a
                    // malformed request line would hold a connection slot for `lingerTimeout`,
                    // and a few sockets on the Wi-Fi could keep the bridge's slots occupied.
                    return self.refuse(conn, .error(status, reason),
                                       unread: isComplete ? 0 : min(self.maxBodyBytes, Self.invalidDrainBytes),
                                       linger: Self.invalidLinger)
                case .head(let head):
                    // A wrong token, a refused route or an oversized body is answered now,
                    // without waiting for the body; what is still coming of it is dropped.
                    let unread = head.bodyLength - (buffer.count - head.bodyOffset)
                    if let refusal = self.router.preflight(head.request) {
                        exchange.received = true
                        return self.refuse(conn, refusal, unread: unread)
                    }
                    if head.bodyLength > self.maxBodyBytes {
                        exchange.received = true
                        return self.refuse(conn, .error(413, "body too large; the limit is \(self.maxBodyBytes / 1024) KB"), unread: unread)
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

    /// Answers a request refused from its headers, then reads and drops the `unread` bytes of
    /// body the client may still be sending, and only then closes. Closing with data unread
    /// resets the connection, and a client that is still uploading (URLSession) loses the
    /// answer. It closes sooner when the client hangs up, and after `lingerTimeout` at most.
    /// Nothing is kept, and the connection counts against the connection limits until it closes.
    private func refuse(_ conn: NWConnection, _ response: HTTPResponse, unread: Int, linger timeout: TimeInterval? = nil) {
        guard unread > 0, lingering < Self.maxLingering else { return respond(conn, response) }
        lingering += 1
        let linger = Linger(conn) { [weak self] in self?.lingering -= 1 }
        conn.send(content: response.serialized(), completion: .contentProcessed { error in
            linger.sent = true
            if linger.drained || error != nil { linger.close() }
        })
        drain(conn, unread) {
            linger.drained = true
            if linger.sent { linger.close() }
        }
        queue.asyncAfter(deadline: .now() + min(timeout ?? lingerTimeout, lingerTimeout)) { [weak linger] in linger?.close() }
    }

    /// Reads and drops up to `remaining` bytes, a chunk at a time, then calls `done`; sooner if
    /// the client hangs up or the connection fails.
    private func drain(_ conn: NWConnection, _ remaining: Int, then done: @escaping () -> Void) {
        conn.receive(minimumIncompleteLength: 1, maximumLength: min(remaining, 64 * 1024)) { [weak self] data, _, isComplete, error in
            let left = remaining - (data?.count ?? 0)
            guard let self, left > 0, !isComplete, error == nil else { return done() }
            self.drain(conn, left, then: done)
        }
    }
}

/// A refused connection draining its body: it closes once the answer is sent and the body is
/// read, or at the deadline, whichever comes first. Used on the server's queue only.
private final class Linger {
    let conn: NWConnection
    let onClose: () -> Void
    var sent = false
    var drained = false
    private var closed = false

    init(_ conn: NWConnection, onClose: @escaping () -> Void) {
        self.conn = conn
        self.onClose = onClose
    }

    func close() {
        guard !closed else { return }
        closed = true
        onClose()
        conn.cancel()
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

/// Writes a file that holds a token (`api.json`, `lan.json`) safely: a fresh sibling created at
/// `0600`, written, then renamed into place. Creating, chmod-ing or writing the path itself all
/// follow a symlink already sitting there, which would hand the token to whoever made it and set
/// the mode on their file; `rename` replaces the link instead. Same pattern as
/// `AgentConfigFile.write`.
enum TokenFileWriter {
    static func write(_ data: Data, to url: URL) throws {
        let fm = FileManager.default
        let folder = url.deletingLastPathComponent()
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        let temp = folder.appendingPathComponent(".\(url.lastPathComponent).\(UUID().uuidString)")
        guard fm.createFile(atPath: temp.path, contents: nil, attributes: [.posixPermissions: 0o600]) else {
            throw CocoaError(.fileWriteNoPermission, userInfo: [NSFilePathErrorKey: temp.path])
        }
        do {
            try data.write(to: temp)
            guard rename(temp.path, url.path) == 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        } catch {
            try? fm.removeItem(at: temp)
            throw error
        }
    }
}

/// Writes the discovery file that `isletctl` and other clients read.
public enum APIDiscoveryStore {
    public static func write(_ discovery: APIDiscovery, to url: URL = IsletPaths.apiDiscoveryFile) throws {
        try TokenFileWriter.write(try JSONEncoder().encode(discovery), to: url)
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
