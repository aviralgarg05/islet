import Foundation

/// What the island draws as glyphs, rings and clock digits, in words for VoiceOver. Views put
/// `label` on the element for an activity and `value` where the value is drawn, inside the same
/// timeline as the digits, so a countdown is read as it stands, not as it was when the row last
/// changed.
public enum SpokenText {
    /// Separators and short units read aloud: "Claude · islet" is "Claude, islet", "SFO → JFK"
    /// is "SFO to JFK", "102–98" is "102 to 98" and "in 9 min" is "in 9 minutes".
    public static func phrase(_ text: String) -> String {
        var s = text.replacingOccurrences(of: " · ", with: ", ").replacingOccurrences(of: " → ", with: " to ")
        for (pattern, template) in expansions {
            s = pattern.stringByReplacingMatches(in: s, range: NSRange(s.startIndex..., in: s), withTemplate: template)
        }
        return s
    }

    /// Short units after a number, and a dash between two numbers. Only whole words, so a word
    /// that merely starts with "min" or "h" stays as it is.
    private static let expansions: [(NSRegularExpression, String)] = [
        ("(?<![\\d.])1 min\\b", "1 minute"),
        ("(\\d+) min\\b", "$1 minutes"),
        ("(?<![\\d.])1 h\\b", "1 hour"),
        ("(\\d+) h\\b", "$1 hours"),
        ("(\\d)\\s?–\\s?(\\d)", "$1 to $2"),
    ].map { (try! NSRegularExpression(pattern: $0.0), $0.1) }

    /// "4 minutes 32 seconds", "1 hour 5 minutes", "3 days 4 hours", "0 seconds". Seconds are
    /// left out from an hour up, and minutes from two days up.
    public static func duration(_ seconds: Double) -> String {
        let total = Int(min(TemplateFormat.maxSeconds, max(0, seconds.isFinite ? seconds : 0)).rounded(.down))
        let d = total / 86400, h = total / 3600, m = (total % 3600) / 60, s = total % 60
        func pair(_ a: String, _ b: String?) -> String { b.map { "\(a) \($0)" } ?? a }
        if d >= 2 { return pair(unit(d, "day"), h % 24 == 0 ? nil : unit(h % 24, "hour")) }
        if h > 0 { return pair(unit(h, "hour"), m == 0 ? nil : unit(m, "minute")) }
        if m > 0 { return pair(unit(m, "minute"), s == 0 ? nil : unit(s, "second")) }
        return unit(s, "second")
    }

    /// "1 minute", "2 minutes".
    static func unit(_ n: Int, _ word: String) -> String { n == 1 ? "1 \(word)" : "\(n) \(word)s" }

    /// "46%".
    public static func percent(_ fraction: Double) -> String {
        "\(Int((min(1, max(0, fraction.isFinite ? fraction : 0)) * 100).rounded()))%"
    }

    // MARK: Activities

    /// The state when it is news in itself; nil while an activity simply runs.
    public static func state(of a: Activity) -> String? {
        switch a.state {
        case .waiting: return a.source == TimerEngine.source ? "time's up" : "waiting for you"
        case .success: return "done"
        case .failure: return "failed"
        case .warning: return "needs attention"
        case .running, .info: return nil
        }
    }

    /// Title and state, the label for the closed island and a bubble: "Claude, islet, waiting
    /// for you". With `detail`, the subtitle too, as a peek or a row shows it, unless it only
    /// says the state again ("Time's up").
    public static func label(_ a: Activity, detail: Bool = false) -> String {
        let state = state(of: a)
        // Either apostrophe: "Time’s up" underneath says the same as "time's up".
        func same(_ s: String?) -> String? { s?.lowercased().replacingOccurrences(of: "\u{2019}", with: "'") }
        let sub = detail ? a.subtitle.map(phrase).flatMap { same($0) == same(state) ? nil : $0 } : nil
        return [phrase(a.title), state, sub].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: ", ")
    }

    /// The value the island shows for `a`, in words: "4 minutes 32 seconds left", "46%",
    /// "step 3 of 5", "Lakers 102, Celtics 98, Q4". Nil when there is none, or when it only
    /// repeats the state ("Waiting"). A game clock is left to `time`, where it is drawn.
    public static func value(_ a: Activity, now: Date) -> String? {
        // A paused timer's wing holds the time left, still: "paused, 3 minutes 20 seconds left".
        if a.source == TimerEngine.source, a.state == .info, let t = a.trailing, let left = clockSeconds(t) {
            return "paused, \(duration(left)) left"
        }
        if let t = a.trailing { return repeatsState(t, of: a) ? nil : phrase(t) }
        switch a.resolvedTemplate {
        case .score:
            if let teams = a.teams, teams.count == 2 {
                var parts = teams.map { "\($0.name ?? $0.abbr ?? "Team") \($0.score ?? "0")" }
                if let period = a.period, !period.isEmpty { parts.append(period) }
                return parts.joined(separator: ", ")
            }
        case .flight:
            if let f = a.flight {
                switch a.flightPhase(now: now) {
                case "landed": return a.templateTrailing(now: now).map(phrase)
                case "airborne": if let at = f.arrives { return "lands in \(minutes(until: at, now: now))" }
                default: if let at = f.departs { return "departs in \(minutes(until: at, now: now))" }
                }
            }
        case .eta where a.phase == "arrived" || a.phase == "delivered":
            return a.templateTrailing(now: now)
        case .route where a.route?.stopsLeft != nil || a.route?.distance != nil:
            return a.templateTrailing(now: now).map(phrase)
        case .stages:
            if let count = a.stageCount, let i = a.currentStage {
                return [a.currentStageLabel, "stage \(i) of \(count)", time(a, now: now)].compactMap { $0 }.joined(separator: ", ")
            }
        case .gauge:
            if let p = a.clampedProgress { return [percent(p), time(a, now: now)].compactMap { $0 }.joined(separator: ", ") }
        case .agent:
            if a.state != .waiting, let phase = a.phase, !phase.isEmpty { return phrase(ActivityPhase.title(phase)) }
        case .workout:
            if a.endsAt == nil, a.startedAt == nil, let m = a.metrics?.first { return m.text }
        default:
            break
        }
        if let t = time(a, now: now) { return t }
        if let steps = a.steps, let step = a.step, steps > 0 { return "step \(min(max(step, 0), steps)) of \(steps)" }
        if let p = a.clampedProgress { return percent(p) }
        if a.isIndeterminate { return "in progress" }
        return nil
    }

    /// Time left or time so far. Templates that count in minutes ("4 min") are read in minutes.
    public static func time(_ a: Activity, now: Date) -> String? {
        if let end = a.endsAt {
            if [.eta, .stages, .gauge, .route].contains(a.resolvedTemplate) {
                return end > now ? "\(minutes(until: end, now: now)) left" : nil
            }
            return "\(duration(end.timeIntervalSince(now).rounded(.up))) left"
        }
        if let start = a.startedAt { return "\(duration(now.timeIntervalSince(start))) so far" }
        return nil
    }

    /// Whole minutes, rounded up: "5 minutes", "1 hour 12 minutes".
    static func minutes(until date: Date, now: Date) -> String {
        let remaining = max(0, date.timeIntervalSince(now))
        return duration((remaining / 60).rounded(.up) * 60)
    }

    /// Seconds in a clock as `Format.clock` writes it ("4:05", "1:02:03"); nil for anything else.
    ///
    /// Worked out in `Double`, as `MenuBarLiveActivities.clockSeconds(in:)` is: the text can
    /// come from a link or a script, which leave the leading field unbounded, and the same sum
    /// in `Int` overflows and traps.
    static func clockSeconds(_ text: String) -> Double? {
        let parts = text.split(separator: ":", omittingEmptySubsequences: false)
        guard (2...3).contains(parts.count),
              parts.allSatisfy({ !$0.isEmpty && $0.allSatisfy { $0.isASCII && $0.isNumber } }),
              parts.dropFirst().allSatisfy({ $0.count == 2 }) else { return nil }
        let numbers = parts.compactMap { Double($0) }
        guard numbers.count == parts.count, numbers.dropFirst().allSatisfy({ $0 < 60 }) else { return nil }
        let seconds = numbers.reduce(0) { $0 * 60 + $1 }
        return seconds.isFinite ? seconds : nil
    }

    /// Status words already said by `state(of:)`: "Waiting" after "waiting for you".
    static func repeatsState(_ text: String, of a: Activity) -> Bool {
        let t = text.trimmingCharacters(in: .whitespaces).lowercased()
        switch a.state {
        case .waiting: return a.source == TimerEngine.source || ["waiting", "waiting for you", "needs you"].contains(t)
        case .success: return ["done", "finished", "complete", "completed", "success"].contains(t)
        case .failure: return ["failed", "failure", "error"].contains(t)
        case .warning: return t == "warning"
        case .running, .info: return false
        }
    }

    // MARK: Everything else on the island

    /// The HUD's label and value: "Volume", "62%".
    public static func hud(_ h: HUDEvent) -> (label: String, value: String) {
        switch h.kind {
        case .volume: return ("Volume", h.muted ? "muted" : percent(h.value))
        case .brightness: return ("Brightness", percent(h.value))
        case .keyboardBrightness: return ("Keyboard brightness", percent(h.value))
        case .microphone: return ("Microphone", h.muted ? "muted" : "on")
        }
    }

    /// "Midnight City, M83".
    public static func media(_ np: NowPlaying) -> String {
        [np.title, np.artist ?? np.appName].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: ", ")
    }

    /// Where a song is: "1 minute 20 seconds of 3 minutes 45 seconds".
    public static func position(_ seconds: Double, of length: Double) -> String {
        "\(duration(seconds)) of \(duration(length))"
    }

    /// "in 9 minutes", "in 1 hour 5 minutes", "now", "5 minutes ago", "tomorrow", "in 3 days":
    /// what `Format.relative` shows, in words.
    public static func relative(to date: Date, now: Date, calendar: Calendar = .current) -> String {
        let delta = date.timeIntervalSince(now)
        if delta <= 30 && delta > -60 { return "now" }
        if delta < 0 {
            let mins = Int((-delta / 60).rounded())
            return mins < 60 ? "\(unit(mins, "minute")) ago" : "\(unit(mins / 60, "hour")) ago"
        }
        let mins = Int((delta / 60).rounded(.up))
        if mins >= 60, !calendar.isDate(date, inSameDayAs: now) {
            if let tomorrow = calendar.date(byAdding: .day, value: 1, to: now), calendar.isDate(date, inSameDayAs: tomorrow) {
                return "tomorrow"
            }
            let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: now), to: calendar.startOfDay(for: date)).day ?? 0
            return "in \(unit(days, "day"))"
        }
        return "in \(duration(Double(mins) * 60))"
    }

    /// When an event is: "in 9 minutes, at 10:00", or "now, until 10:30" once it has begun.
    /// The times come formatted for the reader's locale.
    public static func when(start: Date, now: Date, ongoing: Bool, startText: String, endText: String,
                            calendar: Calendar = .current) -> String {
        ongoing ? "now, until \(endText)" : "\(relative(to: start, now: now, calendar: calendar)), at \(startText)"
    }

    /// A timer's value: "4 minutes 32 seconds left", "paused, 4 minutes left" or "time's up".
    public static func timer(_ t: TimerItem, now: Date) -> String {
        let left = "\(duration(t.timeLeft(at: now).rounded(.up))) left"
        switch t.status {
        case .ringing: return "time's up"
        case .paused: return "paused, \(left)"
        case .running: return left
        }
    }

    /// The stopwatch's value: "12 minutes 3 seconds, lap 3", "4 minutes, paused".
    public static func stopwatch(_ s: Stopwatch, now: Date) -> String {
        let time = duration(s.elapsed(at: now))
        if !s.isRunning { return "\(time), paused" }
        return s.laps.isEmpty ? time : "\(time), lap \(s.laps.count + 1)"
    }

    /// A plan limit: ("5-hour limit", "62% used, resets in 1 hour 12 minutes").
    public static func usage(_ w: UsageWindow, now: Date) -> (label: String, value: String) {
        let long = w.longLabel
        let label = long.prefix(1).uppercased() + long.dropFirst() + " limit"
        let reset = w.hasReset(at: now)
        let used = "\(UsageFormat.percent(reset ? 0 : w.usedPercent)) used"
        guard let at = w.resetsAt else { return (label, used) }
        return (label, used + (reset ? ", reset" : ", resets in \(minutes(until: at, now: now))"))
    }

    /// "76%", "76%, charging", "100%, plugged in".
    public static func battery(level: Int, charging: Bool, pluggedIn: Bool) -> String {
        "\(level)%" + (charging ? ", charging" : pluggedIn ? ", plugged in" : "")
    }
}
