import Foundation

/// Which listener a router serves.
public enum APIScope: Sendable {
    /// The loopback API: every route, with the local API token.
    case local
    /// The iPhone bridge on the local network. It is plain HTTP, so anyone on the same Wi-Fi
    /// can read its token. It has a token of its own and only the routes Shortcuts needs: they
    /// can put something in the island, but not read anything back or act on the Mac.
    case lan
}

extension APIRouter {
    /// Activities and timers created over the local network get ids under this prefix, so the
    /// bridge can't replace Casement's own, the local API's or the URL scheme's.
    public static let lanIDPrefix = "lan-"

    static let lanRefusal = "the local-network bridge only accepts POST /v1/notify, /v1/timer, /v1/focus and /v1/activities, and PUT /v1/activities/{id}"

    /// The local network's allow-list: notifications, timers, Focus and simple activities.
    /// `GET /v1/health` is answered before this is asked.
    static func lanAllows(_ request: HTTPRequest) -> Bool {
        let seg = request.segments
        guard seg.first == "v1" else { return false }
        let rest = Array(seg.dropFirst())
        switch request.method {
        case "POST":
            if rest.count == 1 { return ["notify", "timer", "timers", "focus", "activities"].contains(rest[0]) }
            return rest.count == 2 && rest[0] == "activities"
        case "PUT":
            return rest.count == 2 && rest[0] == "activities"
        default:
            return false
        }
    }

    static func lanNamespaced(_ id: String) -> String { id.hasPrefix(lanIDPrefix) ? id : lanIDPrefix + id }

    /// The longest an activity from the local network lives without being sent again. An
    /// omitted ttl, or one of 0, means "until it is dismissed" everywhere else, so a peer with
    /// the bridge token could fill all 64 slots in about twenty seconds and push out the user's
    /// own pills. On the network every pill expires.
    public static let lanMaxTTL: Double = 3600

    /// On the local network: the id goes under `lan-` (a new one when there is none), links and
    /// buttons are dropped, image files and remote images are dropped, priority tops out at
    /// high, and the ttl at `lanMaxTTL`. Elsewhere the spec is unchanged.
    func admitted(_ spec: ActivitySpec) -> ActivitySpec {
        guard scope == .lan else { return spec }
        var s = spec
        s.id = Self.lanNamespaced(s.id ?? UUID().uuidString.lowercased())
        s.url = nil
        s.actions = nil
        s.icon = admitted(s.icon)
        s.trackerIcon = admitted(s.trackerIcon)
        if s.stageSymbols?.contains(where: { admitted($0) == nil }) == true { s.stageSymbols = nil }
        s.priority = s.priority.map { min($0, .high) }
        let ttl = s.ttl ?? Self.lanMaxTTL
        s.ttl = ttl > 0 && ttl.isFinite ? min(ttl, Self.lanMaxTTL) : Self.lanMaxTTL
        return s
    }

    /// Symbols, emoji and app icons; on the local network, never a file or a remote image.
    func admitted(_ icon: ActivityIcon?) -> ActivityIcon? {
        guard scope == .lan else { return icon }
        switch icon {
        case .symbol?, .emoji?, .app?: return icon
        case .url?, .file?, nil: return nil
        }
    }

    /// Timer ids from the local network go under `lan-`, so a Shortcut can't replace a Mac timer.
    func admitted(timerID id: String?) -> String? {
        scope == .lan ? id.map(Self.lanNamespaced) : id
    }
}
