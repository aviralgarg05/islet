import Foundation

/// One Server-Sent Events record.
public struct SSEEvent: Equatable, Sendable {
    /// The `event:` field, or "message" when the record had none.
    public var event: String
    /// All `data:` lines of the record, joined with "\n".
    public var data: String
    /// The last `id:` seen on the stream so far.
    public var id: String?

    public init(event: String = "message", data: String, id: String? = nil) {
        self.event = event
        self.data = data
        self.id = id
    }
}

/// Incremental Server-Sent Events parser following the WHATWG rules: LF, CR or CRLF line
/// endings, multi-line `data`, `:` comment lines, a leading BOM, and input split anywhere,
/// even inside a CRLF pair or a UTF-8 sequence.
///
/// Feed raw bytes rather than `AsyncLineSequence` lines: that sequence drops empty lines,
/// and empty lines are what end an event.
public struct SSEParser: Sendable {
    private var line: [UInt8] = []
    private var skipLF = false
    private var atStart = true
    private var eventType = ""
    private var dataLines: [String] = []
    private var hasData = false
    private var lastID: String?
    /// Reconnection time the server asked for (`retry:`), in milliseconds.
    public private(set) var retry: Int?
    /// Longer lines are cut, so a runaway stream can't grow memory without bound.
    public var maxLineBytes = 1 << 20

    public init() {}

    public mutating func feed<S: Sequence>(_ bytes: S) -> [SSEEvent] where S.Element == UInt8 {
        var out: [SSEEvent] = []
        for b in bytes {
            if skipLF {
                skipLF = false
                if b == 0x0A { continue }
            }
            switch b {
            case 0x0A:
                endLine(into: &out)
            case 0x0D:
                endLine(into: &out)
                skipLF = true
            default:
                if line.count < maxLineBytes { line.append(b) }
            }
        }
        return out
    }

    public mutating func feed(_ text: String) -> [SSEEvent] { feed(Array(text.utf8)) }

    /// End of stream. Unlike a browser, this also delivers a last record that wasn't followed by
    /// a blank line, so a server that omits the final separator still gets its closing event read.
    public mutating func finish() -> [SSEEvent] {
        var out: [SSEEvent] = []
        if !line.isEmpty { endLine(into: &out) }
        dispatch(into: &out)
        return out
    }

    private mutating func endLine(into out: inout [SSEEvent]) {
        defer { line.removeAll(keepingCapacity: true) }
        var bytes = line[...]
        if atStart {
            atStart = false
            if bytes.starts(with: [0xEF, 0xBB, 0xBF]) { bytes = bytes.dropFirst(3) }
        }
        if bytes.isEmpty {
            dispatch(into: &out)
            return
        }
        if bytes.first == 0x3A { return }  // ":" comment, used for keep-alives
        let field: String
        var value = ""
        if let colon = bytes.firstIndex(of: 0x3A) {
            field = String(decoding: bytes[..<colon], as: UTF8.self)
            var rest = bytes[(colon + 1)...]
            if rest.first == 0x20 { rest = rest.dropFirst() }
            value = String(decoding: rest, as: UTF8.self)
        } else {
            field = String(decoding: bytes, as: UTF8.self)
        }
        switch field {
        case "event":
            eventType = value
        case "data":
            dataLines.append(value)
            hasData = true
        case "id":
            if !value.contains("\u{0}") { lastID = value }
        case "retry":
            if !value.isEmpty, value.utf8.allSatisfy({ (0x30...0x39).contains($0) }), let ms = Int(value) { retry = ms }
        default:
            break
        }
    }

    private mutating func dispatch(into out: inout [SSEEvent]) {
        defer {
            eventType = ""
            dataLines.removeAll()
            hasData = false
        }
        guard hasData else { return }
        out.append(SSEEvent(event: eventType.isEmpty ? "message" : eventType, data: dataLines.joined(separator: "\n"), id: lastID))
    }
}
