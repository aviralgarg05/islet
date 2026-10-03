import Foundation

/// Script widgets: any executable in the plugins folder is run on a schedule and its
/// output is shown in the island. Two output formats are accepted:
///
/// 1. **xbar / SwiftBar text format**, so the hundreds of existing community plugins work
///    unchanged: header line(s), `---`, then items with `| key=value` parameters.
/// 2. **Islet JSON**: a single `ActivitySpec` object, which becomes a live activity.
///
/// The refresh interval comes from the file name, xbar style: `cpu.10s.sh`, `weather.30m.py`.
public enum ScriptPlugins {
    public struct Line: Equatable, Sendable {
        public var text: String
        public var params: [String: String]
        /// Submenu depth (`--` prefix count); 0 for top level.
        public var depth: Int

        public init(text: String, params: [String: String] = [:], depth: Int = 0) {
            self.text = text
            self.params = params
            self.depth = depth
        }

        /// Link to open on click. Only `http` and `https`, with a host: a widget printing text
        /// it fetched could otherwise emit `file://` or an app's own scheme, and a click would
        /// hand that to macOS. The sibling `shell=` is confirmed by an alert; this isn't.
        public var href: URL? {
            guard let url = params["href"].flatMap(URL.init(string:)),
                  ["http", "https"].contains(url.scheme?.lowercased() ?? ""), url.host?.isEmpty == false else { return nil }
            return url
        }
        public var color: String? { params["color"] }
        public var sfSymbol: String? { params["sfimage"] ?? params["sfsymbol"] }
        public var isDisabled: Bool { params["disabled"] == "true" }
        /// Shell command to run on click (`shell=` / `bash=` plus `param1=`… arguments).
        /// Ignored on a line that also has `href=`: a link printed from outside data could
        /// otherwise smuggle in a command.
        public var shellCommand: [String]? {
            guard params["href"] == nil, let exe = params["shell"] ?? params["bash"] else { return nil }
            var argv = [exe]
            var i = 1
            while let p = params["param\(i)"] {
                argv.append(p)
                i += 1
            }
            return argv
        }
        public var refreshOnClick: Bool { params["refresh"] == "true" }
    }

    public enum Output: Equatable, Sendable {
        case text(header: [Line], items: [Line])
        case activity(ActivitySpec)
        case empty
    }

    /// What a script widget runs with: enough to find its tools and its home folder, and the
    /// variables xbar and SwiftBar plugins check, but none of Islet's own environment (an API
    /// token or a key someone exported before launching Islet stays out).
    public static func environment(parent: [String: String], extra: [String: String] = [:]) -> [String: String] {
        var env: [String: String] = [:]
        for key in ["HOME", "USER", "LOGNAME", "TMPDIR", "SHELL", "LANG", "LC_ALL", "LC_CTYPE"] {
            if let v = parent[key], !v.isEmpty { env[key] = v }
        }
        // Apps opened from Finder get a short PATH; plugins expect Homebrew's tools.
        let base = parent["PATH"].flatMap { $0.isEmpty ? nil : $0 } ?? "/usr/bin:/bin:/usr/sbin:/sbin"
        var seen = Set<String>()
        env["PATH"] = (["/opt/homebrew/bin", "/usr/local/bin"] + base.split(separator: ":").map(String.init))
            .filter { !$0.isEmpty && seen.insert($0).inserted }.joined(separator: ":")
        env["ISLET"] = "1"
        env["XBARDarkMode"] = "true"
        env["SWIFTBAR"] = "1"
        for (k, v) in extra { env[k] = v }
        return env
    }

    /// Split `text | a=1 b="two words"` into text and params.
    public static func parseLine(_ raw: String) -> Line {
        var depth = 0
        var s = Substring(raw)
        while s.hasPrefix("--") && !s.hasPrefix("---") {
            depth += 1
            s = s.dropFirst(2)
        }
        guard let bar = s.range(of: "|", options: .backwards) else {
            return Line(text: String(s).trimmingCharacters(in: .whitespaces), depth: depth)
        }
        let text = s[..<bar.lowerBound].trimmingCharacters(in: .whitespaces)
        let params = parseParams(String(s[bar.upperBound...]))
        // A "|" with no key=value pairs after it was part of the text.
        if params.isEmpty { return Line(text: String(s).trimmingCharacters(in: .whitespaces), depth: depth) }
        return Line(text: text, params: params, depth: depth)
    }

    static func parseParams(_ s: String) -> [String: String] {
        var result: [String: String] = [:]
        var i = s.startIndex
        func skipSpaces() { while i < s.endIndex, s[i] == " " || s[i] == "\t" { i = s.index(after: i) } }
        while true {
            skipSpaces()
            guard i < s.endIndex else { break }
            let keyStart = i
            while i < s.endIndex, s[i] != "=", s[i] != " " { i = s.index(after: i) }
            let key = String(s[keyStart..<i]).lowercased()
            guard i < s.endIndex, s[i] == "=" else { continue }
            i = s.index(after: i)
            var value = ""
            if i < s.endIndex, s[i] == "\"" || s[i] == "'" {
                let quote = s[i]
                i = s.index(after: i)
                while i < s.endIndex, s[i] != quote {
                    if s[i] == "\\", s.index(after: i) < s.endIndex {
                        i = s.index(after: i)
                    }
                    value.append(s[i])
                    i = s.index(after: i)
                }
                if i < s.endIndex { i = s.index(after: i) }
            } else {
                while i < s.endIndex, s[i] != " " {
                    value.append(s[i])
                    i = s.index(after: i)
                }
            }
            if !key.isEmpty { result[key] = value }
        }
        return result
    }

    public static func parse(_ output: String) -> Output {
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .empty }
        if trimmed.hasPrefix("{"), let data = trimmed.data(using: .utf8),
           let spec = try? APIJSON.decoder.decode(ActivitySpec.self, from: data), spec.title != nil || spec.id != nil {
            return .activity(spec)
        }
        var header: [Line] = []
        var items: [Line] = []
        var inBody = false
        for raw in trimmed.components(separatedBy: .newlines) {
            if raw.trimmingCharacters(in: .whitespaces) == "---" {
                if inBody { items.append(Line(text: "---")) }
                inBody = true
                continue
            }
            if raw.trimmingCharacters(in: .whitespaces).isEmpty { continue }
            let line = parseLine(raw)
            if inBody { items.append(line) } else { header.append(line) }
        }
        return .text(header: header, items: items)
    }

    /// Refresh interval from an xbar-style file name (`name.5m.sh` → 300 s).
    /// Returns nil when the name carries no interval; callers default to 5 minutes.
    public static func interval(fromFileName name: String) -> TimeInterval? {
        let parts = name.split(separator: ".")
        guard parts.count >= 3 else { return nil }
        let token = parts[parts.count - 2].lowercased()
        let units: [(String, Double)] = [("ms", 0.001), ("s", 1), ("m", 60), ("h", 3600), ("d", 86400)]
        for (suffix, mult) in units where token.hasSuffix(suffix) {
            let number = token.dropLast(suffix.count)
            if let n = Double(number), n > 0 {
                // Never run a script more often than once a second.
                return max(1, n * mult)
            }
        }
        return nil
    }

    /// Display name derived from the file name (`github-prs.5m.py` → "github-prs").
    public static func displayName(fromFileName name: String) -> String {
        String(name.split(separator: ".").first ?? Substring(name))
    }
}
