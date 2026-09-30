import Foundation

/// Picks an SF Symbol and tint for an activity that didn't send one, from its title,
/// subtitle and source. Deterministic, instant and private (no network, no model); an
/// on-device language model can refine the choice where available.
public enum SmartIcon {
    public struct Suggestion: Equatable, Sendable {
        public var symbol: String
        public var tint: String
    }

    /// Ordered rules: the first rule with a matching keyword wins, so specific rules come first.
    static let rules: [(keywords: [String], symbol: String, tint: String)] = [
        (["pull request", "merge request", "pr", "merge", "rebase", "commit", "push", "git", "branch"], "arrow.triangle.pull", "purple"),
        (["claude", "codex", "gpt", "chatgpt", "llm", "agent", "copilot", "gemini", "cursor", "ai", "prompt"], "sparkles", "#D97757"),
        (["epoch", "training", "finetune", "fine-tune", "inference", "model", "gpu"], "brain", "pink"),
        (["test", "pytest", "jest", "spec", "xctest", "vitest", "lint", "typecheck"], "testtube.2", "teal"),
        (["build", "compile", "compiling", "xcodebuild", "cargo", "gradle", "make", "cmake", "bundle", "webpack", "vite"], "hammer.fill", "orange"),
        (["deploy", "release", "ship", "publish", "rollout", "launch", "production"], "paperplane.fill", "blue"),
        (["docker", "container", "kubernetes", "k8s", "pod", "image"], "shippingbox.fill", "cyan"),
        (["database", "migration", "sql", "postgres", "mysql", "redis", "query"], "cylinder.split.1x2.fill", "indigo"),
        (["server", "api", "request", "endpoint", "http", "webhook", "health"], "server.rack", "gray"),
        (["upload", "uploading"], "icloud.and.arrow.up.fill", "blue"),
        (["download", "downloading"], "arrow.down.circle.fill", "blue"),
        (["install", "update", "upgrade", "brew", "npm", "pip", "package"], "shippingbox.and.arrow.backward.fill", "blue"),
        (["backup", "sync", "syncing", "time machine"], "arrow.triangle.2.circlepath", "cyan"),
        (["render", "export", "encode", "transcode", "video", "ffmpeg", "handbrake"], "film.stack", "purple"),
        (["meeting", "standup", "call", "zoom", "facetime", "huddle", "webex", "teams"], "video.fill", "green"),
        (["mail", "email", "inbox"], "envelope.fill", "blue"),
        (["message", "chat", "slack", "discord", "dm", "whatsapp", "telegram", "imessage"], "message.fill", "green"),
        (["timer", "pomodoro", "countdown"], "timer", "orange"),
        (["alarm", "wake", "sleep"], "alarm.fill", "orange"),
        (["reminder", "todo", "to-do", "task", "checklist"], "checklist", "blue"),
        (["calendar", "event", "appointment"], "calendar", "red"),
        (["flight", "boarding", "gate", "airport", "plane"], "airplane", "blue"),
        (["uber", "lyft", "ride", "taxi", "driver", "car", "parking"], "car.fill", "gray"),
        (["delivery", "order", "food", "doordash", "ubereats", "deliveroo", "swiggy", "zomato"], "takeoutbag.and.cup.and.straw.fill", "orange"),
        (["parcel", "shipment", "shipping", "tracking", "courier"], "shippingbox.fill", "brown"),
        (["score", "match", "goal", "game", "innings", "league"], "sportscourt.fill", "green"),
        (["stock", "market", "price", "crypto", "bitcoin", "portfolio"], "chart.line.uptrend.xyaxis", "green"),
        (["workout", "run", "running", "gym", "exercise", "steps"], "figure.run", "green"),
        (["weather", "rain", "storm", "temperature", "forecast"], "cloud.sun.rain.fill", "cyan"),
        (["battery", "charging", "charge"], "battery.100percent.bolt", "green"),
        (["music", "song", "playlist", "album", "podcast"], "music.note", "pink"),
        (["print", "printer", "printing"], "printer.fill", "gray"),
        (["password", "login", "auth", "2fa", "otp", "security", "vpn"], "lock.fill", "yellow"),
        (["payment", "invoice", "paid", "refund", "bank", "transfer"], "creditcard.fill", "green"),
        (["photo", "camera", "screenshot", "scan"], "camera.fill", "gray"),
        (["search", "index", "indexing", "crawl"], "magnifyingglass", "gray"),
        (["focus", "do not disturb", "dnd"], "moon.fill", "indigo"),
        (["airdrop", "share", "transfer"], "dot.radiowaves.left.and.right", "blue"),
        (["error", "failed", "failure", "crash", "exception"], "xmark.octagon.fill", "red"),
        (["warning", "alert", "attention"], "exclamationmark.triangle.fill", "yellow"),
    ]

    /// Lowercased words, plus the words with a trailing "s", "ed" or "ing" removed.
    static func tokens(_ text: String) -> Set<String> {
        let words = text.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-")).inverted)
            .filter { !$0.isEmpty }
        var out = Set(words)
        for w in words where w.count > 4 {
            for suffix in ["ing", "ed", "es", "s"] where w.hasSuffix(suffix) {
                out.insert(String(w.dropLast(suffix.count)))
            }
        }
        return out
    }

    public static func suggest(title: String, subtitle: String? = nil, source: String? = nil) -> Suggestion? {
        let text = [title, subtitle ?? "", source ?? ""].joined(separator: " ")
        let lower = text.lowercased()
        let words = tokens(text)
        for rule in rules {
            for k in rule.keywords {
                let hit = k.contains(" ") ? lower.contains(k) : words.contains(k)
                if hit { return Suggestion(symbol: rule.symbol, tint: rule.tint) }
            }
        }
        return nil
    }
}

extension Activity {
    /// Icon to show: explicit icon, else a state icon for finished/failed/waiting activities
    /// (the outcome matters most), else a smart suggestion, else the state default.
    public func icon(smart: Bool) -> ActivityIcon {
        if let icon { return icon }
        if smart, ![.success, .failure, .warning, .waiting].contains(state),
           let s = SmartIcon.suggest(title: title, subtitle: subtitle, source: source) {
            return .symbol(s.symbol)
        }
        return effectiveIcon
    }

    /// Tint to show, following the same precedence as `icon(smart:)`.
    public func tintName(smart: Bool) -> String {
        if let tint { return tint }
        if smart, ![.success, .failure, .warning, .waiting].contains(state),
           let s = SmartIcon.suggest(title: title, subtitle: subtitle, source: source) {
            return s.tint
        }
        return effectiveTint
    }
}
