import Foundation

/// `islet://` URL scheme, for Shortcuts, Raycast, Alfred, BetterTouchTool, Stream Deck,
/// Keyboard Maestro and anything else that can open a URL.
///
///     islet://notify?title=Build%20done&icon=sf:hammer&tint=green&ttl=5
///     islet://activity?id=deploy&title=Deploying&progress=0.4
///     islet://activity?id=pizza&title=Pizza&endsIn=1200&url=https://…&actionTitle=Track&actionURL=https://…
///     islet://dismiss?id=deploy
///     islet://timer?seconds=300&title=Tea
///     islet://timer?in=20m&title=Pizza   (in= takes "tea 4m", "1h 30m", "at 18:30", …)
///     islet://timer?action=pause&id=timer-1   (pause, resume, add, stop, restart, snooze)
///     islet://pomodoro?action=start   (start, stop, toggle)
///     islet://hud?kind=volume&value=0.5
///     islet://media/playpause   (also play, pause, next, previous, forward, rewind, shuffle, repeat)
///     islet://awake?for=1h      (also 15m, on, off; islet://awake/off)
///     islet://focus?name=Work&state=on   (from a Shortcuts Focus automation)
///     islet://open  islet://close  islet://toggle  islet://settings
///
/// Any app or web page can open these URLs, and no token is involved, so what they can do is
/// limited: activities they create get ids starting with `url-` (they can't replace Islet's own
/// or the API's), links must be https, icons are symbols, emoji or app icons, and priority tops
/// out at high. Scripts that need more use the local API.
public enum URLCommand: Equatable, Sendable {
    case activity(ActivitySpec)
    case dismiss(id: String)
    case timer(seconds: Double, title: String?)
    /// Pause, resume, extend, stop, restart or snooze a timer, or start and stop the Pomodoro.
    case timerCommand(TimerCommand)
    case hud(HUDKind, Double)
    case media(PlaybackCommand)
    case focus(name: String, on: Bool)
    case awake(KeepAwakeChange)
    case open, close, toggle, settings

    /// Activities created or dismissed through the URL scheme live under this id prefix.
    public static let idPrefix = "url-"

    static func namespaced(_ id: String) -> String { id.hasPrefix(idPrefix) ? id : idPrefix + id }

    /// Only https links: a click on the notch opens them, so no files or app-launching schemes.
    static func link(_ raw: String, _ param: String) throws -> URL {
        guard let url = URL(string: raw), url.scheme?.lowercased() == "https", url.host?.isEmpty == false else {
            throw ParseError.invalid(param, raw)
        }
        return url
    }

    /// Symbols, emoji and installed apps' icons; never a file or remote image.
    static func icon(_ raw: String?) -> ActivityIcon? {
        switch raw.flatMap(ActivityIcon.init(string:)) {
        case .symbol(let s)?: return .symbol(s)
        case .emoji(let e)?: return .emoji(e)
        case .app(let b)?: return .app(bundleID: b)
        default: return nil
        }
    }

    public enum ParseError: Error, Equatable, CustomStringConvertible {
        case wrongScheme(String?)
        case unknownCommand(String)
        case missing(String)
        case invalid(String, String)

        public var description: String {
            switch self {
            case .wrongScheme(let s): return "expected islet:// URL, got '\(s ?? "")://'"
            case .unknownCommand(let c): return "unknown command '\(c)'"
            case .missing(let p): return "missing parameter '\(p)'"
            case .invalid(let p, let v): return "invalid value '\(v)' for '\(p)'"
            }
        }
    }

    public static func parse(_ url: URL) throws -> URLCommand {
        guard url.scheme?.lowercased() == "islet" else { throw ParseError.wrongScheme(url.scheme) }
        let comps = URLComponents(url: url, resolvingAgainstBaseURL: false)
        var q: [String: String] = [:]
        for item in comps?.queryItems ?? [] { q[item.name] = item.value ?? "" }
        // islet://media/next -> host "media", path "/next"
        let host = (url.host ?? "").lowercased()
        let path = url.path.split(separator: "/").map { $0.lowercased() }

        func double(_ key: String) throws -> Double? {
            guard let raw = q[key] else { return nil }
            guard let v = Double(raw), v.isFinite else { throw ParseError.invalid(key, raw) }
            return v
        }

        switch host {
        case "notify":
            guard let title = q["title"], !title.isEmpty else { throw ParseError.missing("title") }
            return .activity(ActivitySpec(
                source: q["source"] ?? "url", title: title, subtitle: q["subtitle"],
                icon: icon(q["icon"]) ?? .symbol("bell.fill"),
                state: .info, tint: q["tint"], ttl: try double("ttl") ?? 6, sneak: true
            ))
        case "activity":
            var spec = ActivitySpec(id: q["id"].map(namespaced), source: q["source"] ?? "url", title: q["title"], subtitle: q["subtitle"])
            spec.icon = icon(q["icon"])
            spec.trailing = q["trailing"]
            spec.progress = try double("progress")
            spec.tint = q["tint"]
            spec.ttl = try double("ttl")
            if let v = try double("endsIn") { spec.endsAt = Date().addingTimeInterval(v) }
            if let v = try double("startedAgo") { spec.startedAt = Date().addingTimeInterval(-v) }
            if let u = q["url"] { spec.url = try link(u, "url") }
            if let title = q["actionTitle"], let u = q["actionURL"] {
                spec.actions = [ActivityAction(title: title, url: try link(u, "actionURL"))]
            }
            if let v = try double("steps") { spec.steps = Int(v) }
            if let v = try double("step") { spec.step = Int(v) }
            if let s = q["state"] {
                guard let st = ActivityState(rawValue: s.lowercased()) else { throw ParseError.invalid("state", s) }
                spec.state = st
            }
            if let p = q["priority"] {
                guard let pr = ["low": ActivityPriority.low, "normal": .normal, "high": .high, "critical": .high][p.lowercased()] else {
                    throw ParseError.invalid("priority", p)
                }
                spec.priority = pr
            }
            return .activity(spec)
        case "dismiss", "remove":
            guard let id = q["id"], !id.isEmpty else { throw ParseError.missing("id") }
            return .dismiss(id: namespaced(id))
        case "timer":
            // seconds=, minutes= or in= ("20m", "tea 4m", "at 18:30"; a bare number is minutes).
            func length() throws -> DurationParser.Result? {
                if let s = try double("seconds") ?? (try double("minutes")).map({ $0 * 60 }) {
                    guard s > 0, s <= 86400 else { throw ParseError.invalid("seconds", String(s)) }
                    return DurationParser.Result(seconds: s)
                }
                guard let raw = q["in"] else { return nil }
                guard let r = try? DurationParser.parse(raw) else { throw ParseError.invalid("in", raw) }
                return r
            }
            if let a = q["action"], a.lowercased() != "start" {
                guard let action = TimerAction(rawValue: a.lowercased()) else { throw ParseError.invalid("action", a) }
                let id = q["id"].flatMap { $0.isEmpty ? nil : $0 }
                return .timerCommand(.control(action, id: id, seconds: try length()?.seconds))
            }
            guard let r = try length() else { throw ParseError.missing("seconds") }
            return .timer(seconds: r.seconds, title: q["title"] ?? r.title)
        case "pomodoro":
            let a = (q["action"] ?? path.first ?? "start").lowercased()
            guard let action = PomodoroAction(rawValue: a) else { throw ParseError.invalid("action", a) }
            return .timerCommand(.pomodoro(action))
        case "hud":
            guard let k = q["kind"] else { throw ParseError.missing("kind") }
            guard let kind = HUDKind(rawValue: k) else { throw ParseError.invalid("kind", k) }
            guard let v = try double("value") else { throw ParseError.missing("value") }
            return .hud(kind, min(1, max(0, v)))
        case "media":
            let name = path.first ?? q["command"]?.lowercased() ?? ""
            switch name {
            case "play": return .media(.play)
            case "pause": return .media(.pause)
            case "playpause", "toggle", "toggleplaypause": return .media(.togglePlayPause)
            case "next", "skip": return .media(.next)
            case "previous", "prev", "back": return .media(.previous)
            case "forward", "skipforward", "ff": return .media(.skipForward)
            case "rewind", "skipback", "skipbackward": return .media(.skipBackward)
            case "shuffle": return .media(.toggleShuffle)
            case "repeat": return .media(.toggleRepeat)
            default: throw ParseError.unknownCommand("media/\(name)")
            }
        case "focus":
            let state = (q["state"] ?? q["on"] ?? "on").lowercased()
            return .focus(name: q["name"] ?? "Focus", on: !["off", "0", "false", "no"].contains(state))
        case "awake", "keepawake", "caffeinate":
            let raw = path.first ?? q["for"] ?? q["minutes"] ?? ""
            guard let change = KeepAwake.parse(raw) else { throw ParseError.invalid("for", raw) }
            return .awake(change)
        case "open", "expand": return .open
        case "close", "collapse": return .close
        case "toggle": return .toggle
        case "settings", "preferences": return .settings
        default:
            throw ParseError.unknownCommand(host)
        }
    }
}
