import Foundation
import IsletCore
import Network
import Testing
@testable import IsletSystem

/// A plain TCP client, so a test can send a request head without its body, or hold a
/// connection open without sending anything.
final class RawSocket {
    let fd: Int32

    /// Connects over IPv4 loopback, or over `::1` with `ipv6`, which the local-network listener
    /// sees as a different client.
    init(port: UInt16, ipv6: Bool = false) throws {
        fd = socket(ipv6 ? AF_INET6 : AF_INET, SOCK_STREAM, 0)
        // A server that closes while a body is still being sent must fail the send, not the test run.
        var one: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &one, socklen_t(MemoryLayout<Int32>.size))
        var sendTimeout = timeval(tv_sec: 10, tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &sendTimeout, socklen_t(MemoryLayout<timeval>.size))
        let ok: Int32
        if ipv6 {
            var addr = sockaddr_in6()
            addr.sin6_family = sa_family_t(AF_INET6)
            addr.sin6_port = port.bigEndian
            addr.sin6_addr = in6addr_loopback
            ok = withUnsafePointer(to: &addr) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(fd, $0, socklen_t(MemoryLayout<sockaddr_in6>.size)) }
            }
        } else {
            var addr = sockaddr_in()
            addr.sin_family = sa_family_t(AF_INET)
            addr.sin_port = port.bigEndian
            addr.sin_addr.s_addr = inet_addr("127.0.0.1")
            ok = withUnsafePointer(to: &addr) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) }
            }
        }
        guard ok == 0 else {
            Darwin.close(fd)
            throw POSIXError(.ECONNREFUSED)
        }
    }

    deinit { Darwin.close(fd) }

    func transmit(_ text: String) {
        _ = text.withCString { Darwin.send(fd, $0, strlen($0), 0) }
    }

    /// Sends all of `text` before returning, as a client uploading a body does; false when the
    /// server closed or reset the connection first.
    @discardableResult
    func transmitAll(_ text: String) -> Bool {
        let bytes = Array(text.utf8)
        var sent = 0
        while sent < bytes.count {
            let n = bytes[sent...].withUnsafeBytes { Darwin.send(fd, $0.baseAddress, $0.count, 0) }
            guard n > 0 else { return false }
            sent += n
        }
        return true
    }

    /// Everything the server sends before it closes, or what arrived within `seconds`.
    func reply(within seconds: Int = 3) -> String {
        read(within: seconds) { _ in false }
    }

    /// The response as soon as all of it has arrived, even if the server keeps the connection
    /// open (as it does while dropping the body of a refused request).
    func response(within seconds: Int = 3) -> String {
        read(within: seconds) { bytes in
            let data = Data(bytes)
            guard let end = data.range(of: Data("\r\n\r\n".utf8)) else { return false }
            let head = String(decoding: data[..<end.lowerBound], as: UTF8.self).lowercased()
            let length = head.components(separatedBy: "\r\n").first { $0.hasPrefix("content-length:") }
                .flatMap { Int($0.dropFirst("content-length:".count).trimmingCharacters(in: .whitespaces)) } ?? 0
            return data.count - end.upperBound >= length
        }
    }

    /// Whether the server closes the connection within `seconds`; anything it sends is dropped.
    func closes(within seconds: Int) -> Bool {
        var tv = timeval(tv_sec: seconds, tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
        var buf = [UInt8](repeating: 0, count: 4096)
        while true {
            let n = recv(fd, &buf, buf.count, 0)
            if n > 0 { continue }
            return n == 0 || (errno != EAGAIN && errno != EWOULDBLOCK)
        }
    }

    private func read(within seconds: Int, until complete: ([UInt8]) -> Bool) -> String {
        var tv = timeval(tv_sec: seconds, tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
        var out = [UInt8]()
        var buf = [UInt8](repeating: 0, count: 4096)
        while !complete(out) {
            let n = recv(fd, &buf, buf.count, 0)
            guard n > 0 else { break }
            out.append(contentsOf: buf[0..<n])
        }
        return String(decoding: out, as: UTF8.self)
    }
}

@Suite(.serialized) struct LANServerTests {
    func head(_ method: String, _ path: String, token: String?, length: Int) -> String {
        requestHead(method, path, token: token, length: length)
    }

    @Test func wrongTokenIsRefusedBeforeTheBody() async throws {
        for lan in [true, false] {
            let (server, port) = try await startServer(lan: lan)
            defer { server.stop() }
            // Only the head is sent. Waiting for the body would end in a timeout with no reply.
            let noToken = try RawSocket(port: port)
            noToken.transmit(head("POST", "/v1/notify", token: nil, length: 1000))
            #expect(noToken.response().hasPrefix("HTTP/1.1 401"), "lan: \(lan)")
            let wrong = try RawSocket(port: port)
            wrong.transmit(head("POST", "/v1/notify", token: "not-" + "it", length: 1000))
            #expect(wrong.response().hasPrefix("HTTP/1.1 401"), "lan: \(lan)")
        }
    }

    @Test func refusedRoutesAnswerBeforeTheBodyToo() async throws {
        let (server, port) = try await startServer(lan: true)
        defer { server.stop() }
        let s = try RawSocket(port: port)
        s.transmit(head("POST", "/v1/media", token: "tok", length: 500))
        #expect(s.response().hasPrefix("HTTP/1.1 403"))
        // The rest of the body is read and dropped, and then the connection closes.
        s.transmit(String(repeating: "a", count: 500))
        #expect(s.closes(within: 2))
        #expect(try await request(port, "GET", "/v1/state").0 == 403)
        #expect(try await request(port, "GET", "/v1/activities").0 == 403)
        #expect(try await request(port, "GET", "/v1/health", token: nil).0 == 200)
    }

    @Test func lanBodiesAreCappedAt16KB() async throws {
        let (server, port) = try await startServer(lan: true)
        defer { server.stop() }
        let big = try RawSocket(port: port)
        big.transmit(head("POST", "/v1/notify", token: "tok", length: LocalAPIServer.lanBodyLimit + 1))
        #expect(big.response().hasPrefix("HTTP/1.1 413"))
        // Up to the limit is fine.
        let subtitle = String(repeating: "a", count: LocalAPIServer.lanBodyLimit - 100)
        let body = #"{"title":"Big","subtitle":"\#(subtitle)"}"#
        #expect(body.utf8.count <= LocalAPIServer.lanBodyLimit)
        #expect(try await request(port, "POST", "/v1/notify", body: body).0 == 201)
        // The loopback API keeps its 1 MB limit.
        let (local, localPort) = try await startServer()
        defer { local.stop() }
        let larger = #"{"title":"Big","subtitle":"\#(String(repeating: "a", count: 64 * 1024))"}"#
        #expect(try await request(localPort, "POST", "/v1/notify", body: larger).0 == 201)
    }

    @Test func connectionsAreCapped() async throws {
        // Every test client is 127.0.0.1, so lift the per-client limit to reach the overall one.
        let (server, port) = try await startServer(lan: true) { $0.maxConnectionsPerClient = nil }
        defer { server.stop() }
        var idle: [RawSocket] = []
        for _ in 0..<LocalAPIServer.lanConnectionLimit { idle.append(try RawSocket(port: port)) }
        try await Task.sleep(nanoseconds: 300_000_000)
        let extra = try RawSocket(port: port)
        extra.transmit("GET /v1/health HTTP/1.1\r\nHost: x\r\n\r\n")
        #expect(extra.reply().hasPrefix("HTTP/1.1 503"))
        // Closed connections free their slots.
        idle.removeAll()
        var status = 0
        for _ in 0..<40 where status != 200 {
            try await Task.sleep(nanoseconds: 50_000_000)
            status = (try? await request(port, "GET", "/v1/health", token: nil).0) ?? 0
        }
        #expect(status == 200)
    }

    @Test func eachClientGetsTwoConnections() async throws {
        let (server, port) = try await startServer(lan: true)
        defer { server.stop() }
        let health = "GET /v1/health HTTP/1.1\r\nHost: x\r\n\r\n"
        var idle = [try RawSocket(port: port), try RawSocket(port: port)]
        try await Task.sleep(nanoseconds: 300_000_000)
        let third = try RawSocket(port: port)
        third.transmit(health)
        #expect(third.reply().hasPrefix("HTTP/1.1 429"))
        // Another client still gets in: over IPv6, ::1 is a different client from 127.0.0.1.
        if let other = try? RawSocket(port: port, ipv6: true) {
            other.transmit(health)
            #expect(other.reply().hasPrefix("HTTP/1.1 200"))
        }
        // Closed connections free their client's slots.
        idle.removeAll()
        var status = 0
        for _ in 0..<20 where status != 200 {
            try await Task.sleep(nanoseconds: 50_000_000)
            status = (try? await request(port, "GET", "/v1/health", token: nil).0) ?? 0
        }
        #expect(status == 200)
        try await Task.sleep(nanoseconds: 300_000_000)
        // A refused request lingering over the rest of its body still holds its slot.
        let lingering = [try RawSocket(port: port), try RawSocket(port: port)]
        for s in lingering { s.transmit(head("POST", "/v1/notify", token: "not-" + "it", length: 1000)) }
        for s in lingering { #expect(s.response().hasPrefix("HTTP/1.1 401")) }
        let refused = try RawSocket(port: port)
        refused.transmit(health)
        #expect(refused.reply().hasPrefix("HTTP/1.1 429"))
    }

    @Test func lanHeadersMustArriveSoonerThanLoopbackOnes() async throws {
        let (lan, lanPort) = try await startServer(lan: true)
        let (local, localPort) = try await startServer()
        defer { lan.stop(); local.stop() }
        let started = Date()
        // Headers unfinished: the bridge drops the connection after its header timeout.
        let slow = try RawSocket(port: lanPort)
        slow.transmit("POST /v1/notify HTTP/1.1\r\nHost: x\r\n")
        // Headers in, body late: the header timeout no longer applies.
        let body = #"{"title":"Late"}"#
        let lateBody = try RawSocket(port: lanPort)
        lateBody.transmit(head("POST", "/v1/notify", token: "tok", length: body.utf8.count))
        // Loopback keeps only its request timeout.
        let slowLocal = try RawSocket(port: localPort)
        slowLocal.transmit("GET /v1/health HTTP/1.1\r\n")
        #expect(slow.closes(within: 4))
        let dropped = Date().timeIntervalSince(started)
        #expect(dropped > LocalAPIServer.lanHeaderTimeout - 0.5 && dropped < LocalAPIServer.lanHeaderTimeout + 1.5)
        try await Task.sleep(nanoseconds: 700_000_000)
        #expect(Date().timeIntervalSince(started) > LocalAPIServer.lanHeaderTimeout + 0.5)
        lateBody.transmit(body)
        #expect(lateBody.reply().hasPrefix("HTTP/1.1 201"))
        slowLocal.transmit("Host: 127.0.0.1\r\n\r\n")
        #expect(slowLocal.reply().hasPrefix("HTTP/1.1 200"))
    }

    @Test func newRouterTakesOverWithoutRestarting() async throws {
        let (server, port) = try await startServer(lan: true)
        defer { server.stop() }
        #expect(try await request(port, "POST", "/v1/notify", body: #"{"title":"x"}"#).0 == 201)
        let fresh = APIDiscovery.generateToken()
        server.update(router: APIRouter(token: fresh, version: "t", backend: MemoryBackend(), scope: .lan))
        #expect(try await request(port, "POST", "/v1/notify", body: #"{"title":"x"}"#).0 == 401)
        #expect(try await request(port, "POST", "/v1/notify", token: fresh, body: #"{"title":"x"}"#).0 == 201)
    }

    @Test func rateLimitKeys() {
        func key(_ host: NWEndpoint.Host) -> String { LocalAPIServer.clientKey(.hostPort(host: host, port: 80)) }
        #expect(key(.ipv4(IPv4Address("192.168.1.20")!)) == "192.168.1.20")
        // One /64 is one client, whichever address in it a device picks.
        let a = key(.ipv6(IPv6Address("2001:db8:1:2:aaaa::1")!))
        #expect(a == key(.ipv6(IPv6Address("2001:db8:1:2:bbbb:cccc:dddd:2")!)))
        #expect(a != key(.ipv6(IPv6Address("2001:db8:1:3::1")!)))
        // IPv4 clients seen through a dual-stack socket keep their own address.
        #expect(key(.ipv6(IPv6Address("::ffff:192.168.1.20")!)) == "192.168.1.20")
        #expect(key(.ipv6(IPv6Address("::ffff:192.168.1.21")!)) != "192.168.1.20")
        // IPv4-compatible addresses are plain IPv6 on the wire: they share ::/64.
        let compatible = key(.ipv6(IPv6Address("::192.168.1.20")!))
        #expect(compatible != "192.168.1.20")
        #expect(compatible == key(.ipv6(IPv6Address("::192.168.1.21")!)))
    }
}

@Suite struct LANTokenStoreTests {
    @Test func tokenIsPrivateStableAndSeparate() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("islet-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("lan.json")
        let apiToken = APIDiscovery.generateToken()
        let first = LANTokenStore.loadOrCreate(at: url, distinctFrom: apiToken)
        #expect(first.count >= 32)
        #expect(first != apiToken)
        let perms = try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? Int
        #expect(perms == 0o600)
        #expect(LANTokenStore.loadOrCreate(at: url, distinctFrom: apiToken) == first)
        // The same token as the local API's is never kept.
        #expect(LANTokenStore.loadOrCreate(at: url, distinctFrom: first) != first)
        let current = try #require(LANTokenStore.read(from: url))
        let rotated = LANTokenStore.rotate(at: url, distinctFrom: apiToken)
        #expect(rotated != current)
        #expect(LANTokenStore.read(from: url) == rotated)
        // The API discovery file is a different file.
        #expect(url.lastPathComponent != IsletPaths.apiDiscoveryFile.lastPathComponent)
        // The app and isletctl agree on where it is and how it reads.
        #expect(LANTokenStore.defaultURL == IsletPaths.lanTokenFile)
        #expect(LANTokenFile.read(from: url) == rotated)
    }
}

/// A request line and headers, with the body left to the caller.
func requestHead(_ method: String, _ path: String, token: String?, length: Int) -> String {
    var s = "\(method) \(path) HTTP/1.1\r\nHost: 127.0.0.1\r\nContent-Type: application/json\r\nContent-Length: \(length)\r\n"
    if let token { s += "Authorization: Bearer \(token)\r\n" }
    return s + "\r\n"
}

/// A request refused from its headers is answered at once, and the server then reads and drops
/// the rest of the body before closing. Closing with the body unread resets the connection, and
/// a client still sending it (URLSession with a large upload) loses the reply.
@Suite(.serialized) struct LingeringCloseTests {
    let megabyte = String(repeating: "a", count: 1024 * 1024)
    let wrongToken = "not-" + "it"

    /// Sends the whole request before reading, as URLSession does. Returns whether all of it
    /// could be sent, and the reply.
    func upload(_ port: UInt16, _ method: String, _ path: String, token: String?, body: String) throws -> (sent: Bool, reply: String) {
        let s = try RawSocket(port: port)
        let sent = s.transmitAll(requestHead(method, path, token: token, length: body.utf8.count) + body)
        return (sent, s.reply())
    }

    @Test func wrongTokenReachesAClientSendingAMegabyte() async throws {
        for lan in [false, true] {
            // Thirteen refusals in a row, and URLSession resends a body it couldn't deliver, so
            // the bridge's 30-per-10-seconds would answer 429 part way through and this would
            // look like a lingering bug. The rate limit has its own test; take it out of this one.
            let (server, port) = try await startServer(lan: lan) { $0.rateLimiter = nil }
            defer { server.stop() }
            for attempt in 1...5 {
                let started = Date()
                let (sent, reply) = try upload(port, "POST", "/v1/notify", token: wrongToken, body: megabyte)
                #expect(sent, "lan: \(lan), attempt \(attempt)")
                #expect(reply.hasPrefix("HTTP/1.1 401"), "lan: \(lan), attempt \(attempt)")
                // Closed once the body is in, not left to the linger deadline.
                #expect(Date().timeIntervalSince(started) < 2, "lan: \(lan), attempt \(attempt)")
            }
            // URLSession gave up on these with -1001 or -1005 when the body went unread.
            for attempt in 1...8 {
                let status = try? await request(port, "POST", "/v1/notify", token: wrongToken, body: megabyte, timeout: 10).0
                #expect(status == 401, "URLSession, lan: \(lan), attempt \(attempt)")
            }
        }
    }

    @Test func refusedRoutesAndOversizedBodiesReachTheClientToo() async throws {
        let (server, port) = try await startServer(lan: true)
        defer { server.stop() }
        for attempt in 1...3 {
            let refused = try upload(port, "POST", "/v1/media", token: "tok", body: megabyte)
            #expect(refused.sent && refused.reply.hasPrefix("HTTP/1.1 403"), "attempt \(attempt)")
            let tooBig = try upload(port, "POST", "/v1/notify", token: "tok", body: megabyte)
            #expect(tooBig.sent && tooBig.reply.hasPrefix("HTTP/1.1 413"), "attempt \(attempt)")
            let status = try? await request(port, "POST", "/v1/notify", body: megabyte, timeout: 10).0
            #expect(status == 413, "URLSession, attempt \(attempt)")
        }
    }

    @Test func lingeringEndsWhenTheClientStopsSending() async throws {
        let (server, port) = try await startServer { $0.lingerTimeout = 0.5 }
        defer { server.stop() }
        let s = try RawSocket(port: port)
        let started = Date()
        s.transmit(requestHead("POST", "/v1/notify", token: wrongToken, length: 1024 * 1024) + "and no more")
        #expect(s.reply(within: 3).hasPrefix("HTTP/1.1 401"))
        #expect(Date().timeIntervalSince(started) < 2)
        // Requests without a body close at once, as before.
        let get = try RawSocket(port: port)
        let getStarted = Date()
        get.transmit("GET /v1/activities HTTP/1.1\r\nHost: 127.0.0.1\r\n\r\n")
        #expect(get.reply(within: 3).hasPrefix("HTTP/1.1 401"))
        #expect(Date().timeIntervalSince(getStarted) < 0.4)
    }

    /// A head Islet can't parse still gets its answer rather than a reset connection, and a
    /// client that has finished sending doesn't hold its connection slot while nothing comes.
    @Test func aHeadThatDoesNotParseIsAnsweredWithoutLingering() async throws {
        for lan in [false, true] {
            let (server, port) = try await startServer(lan: lan) { $0.lingerTimeout = 5 }
            defer { server.stop() }
            // Chunked: Islet needs a length it can check against the body limit, so this is a 411.
            let chunked = try RawSocket(port: port)
            chunked.transmit("POST /v1/notify HTTP/1.1\r\nHost: 127.0.0.1\r\nTransfer-Encoding: chunked\r\n\r\n")
            #expect(chunked.reply(within: 3).hasPrefix("HTTP/1.1 411"), "lan: \(lan)")
            // Nonsense, sent and done with: answered and closed, not held for the linger.
            let junk = try RawSocket(port: port)
            let started = Date()
            #expect(junk.transmitAll("not-a-request\r\n\r\n"), "lan: \(lan)")
            #expect(junk.reply(within: 3).hasPrefix("HTTP/1.1 400"), "lan: \(lan)")
            #expect(Date().timeIntervalSince(started) < 2, "lan: \(lan)")
        }
    }
}

/// `isletctl token --lan`, run from the build folder against a temporary support folder.
@Suite struct LANTokenCLITests {
    /// The `isletctl` built beside these tests, when this build has one.
    var isletctl: URL? {
        let url = Bundle(for: RawSocket.self).bundleURL.deletingLastPathComponent().appendingPathComponent("isletctl")
        return FileManager.default.isExecutableFile(atPath: url.path) ? url : nil
    }

    func run(_ exe: URL, _ arguments: [String], supportDirectory: URL) throws -> (status: Int32, out: String, err: String) {
        let p = Process()
        p.executableURL = exe
        p.arguments = arguments
        var env = ProcessInfo.processInfo.environment
        env["ISLET_SUPPORT_DIR"] = supportDirectory.path
        env["ISLET_TOKEN"] = nil
        env["ISLET_PORT"] = nil
        p.environment = env
        let out = Pipe(), err = Pipe()
        p.standardOutput = out
        p.standardError = err
        try p.run()
        let stdout = out.fileHandleForReading.readDataToEndOfFile()
        let stderr = err.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return (p.terminationStatus, String(decoding: stdout, as: UTF8.self), String(decoding: stderr, as: UTF8.self))
    }

    @Test func printsTheBridgeTokenOrSaysItWasNeverTurnedOn() throws {
        guard let exe = isletctl else { return }
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("islet-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let never = try run(exe, ["token", "--lan"], supportDirectory: dir)
        #expect(never.status == 1)
        #expect(never.out.isEmpty)
        #expect(never.err.contains("never been turned on"))
        // What the app saves when the bridge is turned on.
        let token = LANTokenStore.loadOrCreate(at: dir.appendingPathComponent("lan.json"), distinctFrom: nil)
        let printed = try run(exe, ["token", "--lan"], supportDirectory: dir)
        #expect(printed.status == 0)
        #expect(printed.out == token + "\n")
    }
}
