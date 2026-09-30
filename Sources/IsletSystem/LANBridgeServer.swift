import Foundation
import IsletCore
import Network

extension LocalAPIServer {
    /// Requests per client in `lanRateWindow` seconds on the local-network listener.
    public static let lanRateLimit = 30
    public static let lanRateWindow: TimeInterval = 10
    /// Bridge requests are a title and a few fields; 16 KB is plenty.
    public static let lanBodyLimit = 16 * 1024
    public static let lanConnectionLimit = 8

    /// The listener for the iPhone bridge, where anyone on the Wi-Fi can connect: each client
    /// is rate-limited, bodies are small, and only a few connections are open at once.
    public static func localNetwork(router: APIRouter) -> LocalAPIServer {
        let server = LocalAPIServer(router: router)
        server.rateLimiter = RateLimiter(limit: lanRateLimit, window: lanRateWindow)
        server.maxBodyBytes = lanBodyLimit
        server.maxConnections = lanConnectionLimit
        return server
    }

    /// Rate-limit key: the IPv4 address, or the /64 prefix for IPv6, since one device can pick
    /// any address in its /64.
    static func clientKey(_ endpoint: NWEndpoint) -> String {
        guard case .hostPort(let host, _) = endpoint else { return "unknown" }
        switch host {
        case .ipv6(let address):
            if let v4 = address.asIPv4 { return "\(v4)" }
            return "v6:" + address.rawValue.prefix(8).map { String(format: "%02x", $0) }.joined()
        case .ipv4(let address):
            return "\(address)"
        default:
            return "\(host)"
        }
    }
}

/// The iPhone bridge's token, in `lan.json` (mode 0600) beside the API discovery file. It is
/// separate from the local API's token: the bridge is plain HTTP, and a token read off the
/// Wi-Fi must not open the loopback API.
public enum LANTokenStore {
    public static var defaultURL: URL { IsletPaths.supportDirectory.appendingPathComponent("lan.json") }

    struct Contents: Codable { var token: String }

    public static func read(from url: URL = defaultURL) -> String? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return (try? JSONDecoder().decode(Contents.self, from: data))?.token
    }

    /// The saved token, or a new one (saved) when there is none, it is too short, or it is the
    /// same as `apiToken`.
    public static func loadOrCreate(at url: URL = defaultURL, distinctFrom apiToken: String?) -> String {
        if let existing = read(from: url), existing.count >= 32, existing != apiToken { return existing }
        return rotate(at: url, distinctFrom: apiToken)
    }

    /// Saves a new token; the old one stops working as soon as the listener gets it. If the file
    /// can't be written the token still works until Islet quits.
    @discardableResult
    public static func rotate(at url: URL = defaultURL, distinctFrom apiToken: String?) -> String {
        var token = APIDiscovery.generateToken()
        while token == apiToken { token = APIDiscovery.generateToken() }
        try? write(token, to: url)
        return token
    }

    static func write(_ token: String, to url: URL) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(Contents(token: token))
        // Create with 0600 before writing so the token is never world-readable.
        if !fm.fileExists(atPath: url.path) {
            fm.createFile(atPath: url.path, contents: nil, attributes: [.posixPermissions: 0o600])
        }
        try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        try data.write(to: url)
    }
}
