import Foundation
import IsletCore
import Network
import Testing
@testable import IsletSystem

/// A plain TCP client, so a test can send a request head without its body, or hold a
/// connection open without sending anything.
final class RawSocket {
    let fd: Int32

    init(port: UInt16) throws {
        fd = socket(AF_INET, SOCK_STREAM, 0)
        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = port.bigEndian
        addr.sin_addr.s_addr = inet_addr("127.0.0.1")
        let ok = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) }
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

    /// Everything the server sends before it closes, or what arrived within `seconds`.
    func reply(within seconds: Int = 3) -> String {
        var tv = timeval(tv_sec: seconds, tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
        var out = [UInt8]()
        var buf = [UInt8](repeating: 0, count: 4096)
        while true {
            let n = recv(fd, &buf, buf.count, 0)
            guard n > 0 else { break }
            out.append(contentsOf: buf[0..<n])
        }
        return String(decoding: out, as: UTF8.self)
    }
}

@Suite(.serialized) struct LANServerTests {
    func head(_ method: String, _ path: String, token: String?, length: Int) -> String {
        var s = "\(method) \(path) HTTP/1.1\r\nHost: 127.0.0.1\r\nContent-Type: application/json\r\nContent-Length: \(length)\r\n"
        if let token { s += "Authorization: Bearer \(token)\r\n" }
        return s + "\r\n"
    }

    @Test func wrongTokenIsRefusedBeforeTheBody() async throws {
        for lan in [true, false] {
            let (server, port) = try await startServer(lan: lan)
            defer { server.stop() }
            // Only the head is sent. Waiting for the body would end in a timeout with no reply.
            let noToken = try RawSocket(port: port)
            noToken.transmit(head("POST", "/v1/notify", token: nil, length: 1000))
            #expect(noToken.reply().hasPrefix("HTTP/1.1 401"), "lan: \(lan)")
            let wrong = try RawSocket(port: port)
            wrong.transmit(head("POST", "/v1/notify", token: "not-" + "it", length: 1000))
            #expect(wrong.reply().hasPrefix("HTTP/1.1 401"), "lan: \(lan)")
        }
    }

    @Test func refusedRoutesAnswerBeforeTheBodyToo() async throws {
        let (server, port) = try await startServer(lan: true)
        defer { server.stop() }
        let s = try RawSocket(port: port)
        s.transmit(head("POST", "/v1/media", token: "tok", length: 500))
        #expect(s.reply().hasPrefix("HTTP/1.1 403"))
        #expect(try await request(port, "GET", "/v1/state").0 == 403)
        #expect(try await request(port, "GET", "/v1/activities").0 == 403)
        #expect(try await request(port, "GET", "/v1/health", token: nil).0 == 200)
    }

    @Test func lanBodiesAreCappedAt16KB() async throws {
        let (server, port) = try await startServer(lan: true)
        defer { server.stop() }
        let big = try RawSocket(port: port)
        big.transmit(head("POST", "/v1/notify", token: "tok", length: LocalAPIServer.lanBodyLimit + 1))
        #expect(big.reply().hasPrefix("HTTP/1.1 413"))
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
        let (server, port) = try await startServer(lan: true)
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
    }
}
