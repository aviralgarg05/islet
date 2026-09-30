import Foundation

/// An sRGB color parsed from a hex string or a system color name.
public struct RGBA: Equatable, Sendable {
    public var r: Double, g: Double, b: Double, a: Double

    public init(r: Double, g: Double, b: Double, a: Double = 1) {
        self.r = r; self.g = g; self.b = b; self.a = a
    }

    /// Apple system colors (dark appearance variants, since the island is always dark).
    public static let named: [String: RGBA] = [
        "red": RGBA(r: 1.0, g: 0.271, b: 0.227),
        "orange": RGBA(r: 1.0, g: 0.624, b: 0.039),
        "yellow": RGBA(r: 1.0, g: 0.839, b: 0.039),
        "green": RGBA(r: 0.188, g: 0.820, b: 0.345),
        "mint": RGBA(r: 0.388, g: 0.902, b: 0.886),
        "teal": RGBA(r: 0.251, g: 0.784, b: 0.878),
        "cyan": RGBA(r: 0.392, g: 0.824, b: 1.0),
        "blue": RGBA(r: 0.039, g: 0.518, b: 1.0),
        "indigo": RGBA(r: 0.369, g: 0.361, b: 0.902),
        "purple": RGBA(r: 0.749, g: 0.353, b: 0.949),
        "pink": RGBA(r: 1.0, g: 0.216, b: 0.373),
        "brown": RGBA(r: 0.675, g: 0.557, b: 0.408),
        "gray": RGBA(r: 0.557, g: 0.557, b: 0.576),
        "white": RGBA(r: 1, g: 1, b: 1),
        "black": RGBA(r: 0, g: 0, b: 0),
    ]

    /// Parse `#RGB`, `#RRGGBB`, `#RRGGBBAA` (the `#` is optional) or a named color.
    public static func parse(_ raw: String) -> RGBA? {
        let s = raw.trimmingCharacters(in: .whitespaces).lowercased()
        if let n = named[s] { return n }
        if s == "grey" { return named["gray"] }
        var hex = s.hasPrefix("#") ? String(s.dropFirst()) : s
        guard hex.allSatisfy(\.isHexDigit) else { return nil }
        if hex.count == 3 { hex = hex.map { "\($0)\($0)" }.joined() }
        guard hex.count == 6 || hex.count == 8, let v = UInt64(hex, radix: 16) else { return nil }
        if hex.count == 6 {
            return RGBA(
                r: Double((v >> 16) & 0xFF) / 255,
                g: Double((v >> 8) & 0xFF) / 255,
                b: Double(v & 0xFF) / 255
            )
        }
        return RGBA(
            r: Double((v >> 24) & 0xFF) / 255,
            g: Double((v >> 16) & 0xFF) / 255,
            b: Double((v >> 8) & 0xFF) / 255,
            a: Double(v & 0xFF) / 255
        )
    }
}

public enum Format {
    /// `m:ss` below an hour, `h:mm:ss` above.
    public static func clock(_ seconds: Double) -> String {
        guard seconds.isFinite else { return "--:--" }
        // Capped: dates come from API clients, and a huge span would trap converting to Int.
        let total = Int(min(TemplateFormat.maxSeconds, max(0, seconds)).rounded(.down))
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        if h > 0 { return String(format: "%d:%02d:%02d", h, m, s) }
        return String(format: "%d:%02d", m, s)
    }

    /// Remaining time until `date`, rounded up so a timer never shows 0:00 early.
    public static func countdown(until date: Date, now: Date) -> String {
        let remaining = date.timeIntervalSince(now)
        return clock(remaining <= 0 ? 0 : remaining.rounded(.up))
    }

    /// Short relative phrase for an upcoming event: "now", "in 5 min", "in 1 h 20 min", "tomorrow".
    public static func relative(to date: Date, now: Date, calendar: Calendar = .current) -> String {
        let delta = date.timeIntervalSince(now)
        if delta <= 30 && delta > -60 { return "now" }
        if delta < 0 {
            let mins = Int((-delta / 60).rounded())
            return mins < 60 ? "\(mins) min ago" : "\(mins / 60) h ago"
        }
        let mins = Int((delta / 60).rounded(.up))
        if mins < 60 { return "in \(mins) min" }
        if !calendar.isDate(date, inSameDayAs: now) {
            if let tomorrow = calendar.date(byAdding: .day, value: 1, to: now),
               calendar.isDate(date, inSameDayAs: tomorrow) {
                return "tomorrow"
            }
            let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: now), to: calendar.startOfDay(for: date)).day ?? 0
            return "in \(days) days"
        }
        let h = mins / 60, m = mins % 60
        return m == 0 ? "in \(h) h" : "in \(h) h \(m) min"
    }

    /// "1:05 left" style battery estimate; nil when unknown.
    public static func batteryTime(minutes: Int?) -> String? {
        guard let minutes, minutes > 0, minutes < 24 * 60 else { return nil }
        return String(format: "%d:%02d", minutes / 60, minutes % 60)
    }

    /// Human readable byte count ("1.2 GB").
    public static func bytes(_ count: Int64) -> String {
        let units = ["B", "KB", "MB", "GB", "TB"]
        var value = Double(count)
        var unit = 0
        while value >= 1000 && unit < units.count - 1 {
            value /= 1000
            unit += 1
        }
        return unit == 0 ? "\(count) B" : String(format: value < 10 ? "%.1f %@" : "%.0f %@", value, units[unit])
    }
}
