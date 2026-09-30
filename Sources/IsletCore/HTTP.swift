import Foundation

/// Minimal HTTP/1.1 request model and incremental parser for the local API.
/// Only what the API needs: Content-Length bodies, no chunked encoding, no keep-alive pipelining.
public struct HTTPRequest: Equatable, Sendable {
    public var method: String
    public var path: String
    public var query: [String: String]
    /// Header names are lowercased.
    public var headers: [String: String]
    public var body: Data

    public init(method: String, path: String, query: [String: String] = [:], headers: [String: String] = [:], body: Data = Data()) {
        self.method = method.uppercased()
        self.path = path
        self.query = query
        self.headers = Dictionary(uniqueKeysWithValues: headers.map { ($0.key.lowercased(), $0.value) })
        self.body = body
    }

    /// Path split into non-empty components: "/v1/activities/x" -> ["v1", "activities", "x"].
    public var segments: [String] {
        path.split(separator: "/").map { String($0).removingPercentEncoding ?? String($0) }
    }
}

public struct HTTPResponse: Equatable, Sendable {
    public var status: Int
    public var headers: [String: String]
    public var body: Data

    public init(status: Int, headers: [String: String] = [:], body: Data = Data()) {
        self.status = status
        self.headers = headers
        self.body = body
    }

    public static func json<T: Encodable>(_ value: T, status: Int = 200) -> HTTPResponse {
        let data = (try? APIJSON.encoder.encode(value)) ?? Data("{}".utf8)
        return HTTPResponse(status: status, headers: ["Content-Type": "application/json; charset=utf-8"], body: data)
    }

    public static func error(_ status: Int, _ message: String) -> HTTPResponse {
        json(["error": message], status: status)
    }

    public static let noContent = HTTPResponse(status: 204)

    public static func reason(_ status: Int) -> String {
        switch status {
        case 200: return "OK"
        case 201: return "Created"
        case 204: return "No Content"
        case 400: return "Bad Request"
        case 401: return "Unauthorized"
        case 403: return "Forbidden"
        case 404: return "Not Found"
        case 405: return "Method Not Allowed"
        case 411: return "Length Required"
        case 413: return "Payload Too Large"
        case 422: return "Unprocessable Entity"
        case 429: return "Too Many Requests"
        case 500: return "Internal Server Error"
        case 503: return "Service Unavailable"
        default: return "Status"
        }
    }

    public func serialized() -> Data {
        var head = "HTTP/1.1 \(status) \(Self.reason(status))\r\n"
        var h = headers
        h["Content-Length"] = String(body.count)
        h["Connection"] = "close"
        for key in h.keys.sorted() { head += "\(key): \(h[key]!)\r\n" }
        head += "\r\n"
        return Data(head.utf8) + body
    }
}

public enum HTTPParseResult: Equatable, Sendable {
    case incomplete
    case complete(HTTPRequest)
    case invalid(status: Int, reason: String)
}

public enum HTTPParser {
    public static let maxHeaderBytes = 16 * 1024
    public static let maxBodyBytes = 1 * 1024 * 1024

    public static func parse(_ data: Data) -> HTTPParseResult {
        let separator = Data("\r\n\r\n".utf8)
        guard let headerEnd = data.range(of: separator) else {
            return data.count > maxHeaderBytes ? .invalid(status: 413, reason: "headers too large") : .incomplete
        }
        guard let head = String(data: data[data.startIndex..<headerEnd.lowerBound], encoding: .utf8) else {
            return .invalid(status: 400, reason: "headers are not UTF-8")
        }
        var lines = head.components(separatedBy: "\r\n")
        let requestLine = lines.removeFirst().split(separator: " ", omittingEmptySubsequences: true)
        guard requestLine.count == 3, requestLine[2].hasPrefix("HTTP/1.") else {
            return .invalid(status: 400, reason: "malformed request line")
        }
        var headers: [String: String] = [:]
        for line in lines where !line.isEmpty {
            guard let colon = line.firstIndex(of: ":") else { return .invalid(status: 400, reason: "malformed header") }
            let name = line[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
            let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            headers[name] = value
        }
        if let te = headers["transfer-encoding"], te.lowercased() != "identity" {
            return .invalid(status: 411, reason: "chunked bodies are not supported; send Content-Length")
        }
        let length: Int
        if let cl = headers["content-length"] {
            guard let n = Int(cl), n >= 0 else { return .invalid(status: 400, reason: "bad Content-Length") }
            length = n
        } else {
            length = 0
        }
        if length > maxBodyBytes { return .invalid(status: 413, reason: "body too large") }
        let bodyStart = headerEnd.upperBound
        guard data.distance(from: bodyStart, to: data.endIndex) >= length else { return .incomplete }
        let body = data[bodyStart..<data.index(bodyStart, offsetBy: length)]

        let target = String(requestLine[1])
        var path = target
        var query: [String: String] = [:]
        if let comps = URLComponents(string: target.hasPrefix("/") ? "http://h" + target : target) {
            path = comps.percentEncodedPath.isEmpty ? "/" : comps.percentEncodedPath
            for item in comps.queryItems ?? [] { query[item.name] = item.value ?? "" }
        }
        return .complete(HTTPRequest(method: String(requestLine[0]), path: path, query: query, headers: headers, body: Data(body)))
    }
}

/// Shared JSON configuration: ISO-8601 dates on output; ISO-8601 (with or without
/// fractional seconds) or Unix seconds accepted on input.
public enum APIJSON {
    public static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.sortedKeys]
        return e
    }()

    public static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .custom { decoder in
            let c = try decoder.singleValueContainer()
            if let seconds = try? c.decode(Double.self) {
                // Accept milliseconds too (JavaScript Date.now()).
                return Date(timeIntervalSince1970: seconds > 1e11 ? seconds / 1000 : seconds)
            }
            let s = try c.decode(String.self)
            if let d = parseISO8601(s) { return d }
            throw DecodingError.dataCorruptedError(in: c, debugDescription: "Expected ISO-8601 date or Unix seconds, got '\(s)'")
        }
        return d
    }()

    public static func parseISO8601(_ s: String) -> Date? {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f.date(from: s) { return d }
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: s)
    }
}

/// Sliding-window rate limiter keyed by client address (used for the LAN listener).
public struct RateLimiter: Sendable {
    public var limit: Int
    public var window: TimeInterval
    private var hits: [String: [Date]] = [:]

    public init(limit: Int = 30, window: TimeInterval = 10) {
        self.limit = limit
        self.window = window
    }

    /// Records a request and returns whether it is allowed.
    public mutating func allow(_ client: String, now: Date) -> Bool {
        var list = (hits[client] ?? []).filter { now.timeIntervalSince($0) < window }
        guard list.count < limit else {
            hits[client] = list
            return false
        }
        list.append(now)
        hits[client] = list
        if hits.count > 1024 { hits = hits.filter { !$0.value.isEmpty && now.timeIntervalSince($0.value.last!) < window } }
        return true
    }
}
