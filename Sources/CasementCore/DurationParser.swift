import Foundation

/// Reads timer lengths the way people type or say them: "20m", "1h 30m", "1h30", "25 min",
/// "half an hour", "tea 4m", "in 20 minutes to take the pizza out", "at 18:30", "at 6pm".
/// Words that are not part of the duration become the title.
///
/// `NSDataDetector` can't do this: it finds no relative durations at all and reads "6pm" as
/// today even after 6 pm has passed, so clock times here always roll forward.
public enum DurationParser {
    public struct Result: Equatable, Sendable {
        public var seconds: TimeInterval
        public var title: String?

        public init(seconds: TimeInterval, title: String? = nil) {
            self.seconds = seconds
            self.title = title
        }
    }

    public enum Failure: Error, Equatable, Sendable, CustomStringConvertible {
        case empty
        case noDuration(String)
        case tooShort
        case tooLong

        public var description: String {
            switch self {
            case .empty: return "no duration given; try 5m, 1h 30m, \"tea 4m\" or \"at 18:30\""
            case .noDuration(let s): return "can't find a duration in '\(s)'; try 5m, 1h 30m, \"tea 4m\" or \"at 18:30\""
            case .tooShort: return "a timer needs to run for at least a second"
            case .tooLong: return "timers can run for up to 24 hours"
            }
        }
    }

    public static let maxSeconds: TimeInterval = 24 * 3600

    /// - Parameters:
    ///   - now: the moment clock times ("at 18:30") are measured from.
    ///   - bareNumberUnit: what a number without a unit means ("25", "tea 4"): 60 reads it as
    ///     minutes, 1 as seconds (what `casementctl timer 300` has always meant).
    public static func parse(_ text: String, now: Date = Date(), calendar: Calendar = .current,
                             bareNumberUnit: TimeInterval = 60) throws -> Result {
        let words = text.split(whereSeparator: \.isWhitespace).map(String.init)
        guard !words.isEmpty else { throw Failure.empty }
        let scanner = Scanner(tokens: tokenize(words), now: now, calendar: calendar)
        guard let match = scanner.find() ?? scanner.bareNumber(unit: bareNumberUnit) else {
            throw Failure.noDuration(text.trimmingCharacters(in: .whitespaces))
        }
        guard match.seconds > 0 else { throw Failure.tooShort }
        guard match.seconds <= maxSeconds else { throw Failure.tooLong }
        let consumed = Set(scanner.tokens[match.range].map(\.word))
        let rest = words.indices.filter { !consumed.contains($0) }.map { words[$0] }
        return Result(seconds: match.seconds, title: cleanTitle(rest))
    }

    // MARK: Tokens

    struct Token: Equatable {
        var text: String
        /// Index of the whitespace-separated word this token came from.
        var word: Int
        /// Starts in the middle of a word ("30" in "1h30").
        var attached: Bool
    }

    /// Splits words into number and letter runs: "1h30m" → 1 h 30 m, "6:15pm" → 6:15 pm,
    /// "forty-five" → forty five. Punctuation separates tokens and is dropped, except a minus
    /// sign in front of a number ("-5m"), which is kept so the length can be refused.
    static func tokenize(_ words: [String]) -> [Token] {
        var out: [Token] = []
        for (w, raw) in words.enumerated() {
            var word = raw.lowercased()
            for (from, to) in [("a.m.", "am"), ("p.m.", "pm"), ("a.m", "am"), ("p.m", "pm")] {
                word = word.replacingOccurrences(of: from, with: to)
            }
            let chars = Array(word)
            var i = 0
            var first = true
            while i < chars.count {
                let c = chars[i]
                var run = ""
                let minus = c == "-" && i + 1 < chars.count && chars[i + 1].isNumber && chars[i + 1].isASCII
                    && (i == 0 || !(chars[i - 1].isLetter || chars[i - 1].isNumber))
                if c.isNumber && c.isASCII || minus {
                    if minus {
                        run = "-"
                        i += 1
                    }
                    // Digits, with '.' or ':' only between digits (1.5, 18:30, 18.30).
                    while i < chars.count {
                        let d = chars[i]
                        if d.isNumber, d.isASCII {
                            run.append(d)
                        } else if (d == "." || d == ":"), i + 1 < chars.count, chars[i + 1].isNumber, !run.isEmpty {
                            run.append(d)
                        } else {
                            break
                        }
                        i += 1
                    }
                } else if c.isLetter {
                    while i < chars.count, chars[i].isLetter {
                        run.append(chars[i])
                        i += 1
                    }
                } else {
                    i += 1
                    continue
                }
                out.append(Token(text: run, word: w, attached: !first))
                first = false
            }
        }
        return out
    }

    // MARK: Grammar

    struct Match {
        var seconds: TimeInterval
        var range: Range<Int>
    }

    struct Scanner {
        let tokens: [Token]
        let now: Date
        let calendar: Calendar

        init(tokens: [Token], now: Date, calendar: Calendar) {
            self.tokens = tokens
            self.now = now
            self.calendar = calendar
        }

        func text(_ i: Int) -> String? { i < tokens.count ? tokens[i].text : nil }

        /// The leftmost duration or clock time, with the word that introduces it ("in", "for", "at").
        func find() -> Match? {
            for i in tokens.indices {
                let t = tokens[i].text
                if Self.clockWords.contains(t), let (s, end) = clock(at: i + 1, needsMeridiem: false) {
                    return Match(seconds: s, range: i..<end)
                }
                if ["in", "for", "after"].contains(t), let (s, end) = duration(at: i + 1) {
                    return Match(seconds: s, range: i..<end)
                }
                if let (s, end) = duration(at: i) { return Match(seconds: s, range: i..<end) }
                if let (s, end) = clock(at: i, needsMeridiem: true) { return Match(seconds: s, range: i..<end) }
            }
            return nil
        }

        /// A number with no unit, accepted only as the last word ("25", "tea 4", "in 5"), and
        /// not after "at": "at 18.75" is a clock time that doesn't exist, not 18.75 minutes.
        func bareNumber(unit: TimeInterval) -> Match? {
            guard let last = tokens.last, !last.attached, let n = number(last.text) else { return nil }
            let i = tokens.count - 1
            if i > 0, Self.clockWords.contains(tokens[i - 1].text) { return nil }
            // The number must be a whole word, not the tail of "4x".
            guard tokens.filter({ $0.word == last.word }).count == 1 else { return nil }
            let start = i > 0 && ["in", "for", "after"].contains(tokens[i - 1].text) ? i - 1 : i
            return Match(seconds: n * unit, range: start..<(i + 1))
        }

        /// One or more "quantity unit" terms: "1h 30m", "1 hour and 30 minutes", "an hour and a half", "1h30".
        func duration(at start: Int) -> (TimeInterval, Int)? {
            var total: TimeInterval = 0
            var j = start
            var lastUnit: TimeInterval?
            while j < tokens.count {
                var k = j
                if lastUnit != nil, text(k) == "and" { k += 1 }
                if let (q, afterQ) = quantity(at: k), let (u, afterU) = unit(at: afterQ) {
                    total += q * u
                    j = afterU
                    if text(j) == "and", text(j + 1) == "a", text(j + 2) == "half" {
                        total += u / 2
                        j += 3
                    }
                    lastUnit = u
                    continue
                }
                // "1h30" and "5m30": a number glued to the previous unit is the next smaller unit.
                if let u = lastUnit, u > 1, j < tokens.count, tokens[j].attached, let n = number(tokens[j].text),
                   unit(at: j + 1) == nil {
                    total += n * u / 60
                    lastUnit = u / 60
                    j += 1
                    continue
                }
                break
            }
            return lastUnit == nil ? nil : (total, j)
        }

        /// A count: "20", "1.5", "a", "an", "half", "quarter", "a couple of", "twenty five", "one and a half".
        func quantity(at i: Int) -> (Double, Int)? {
            guard let t = text(i) else { return nil }
            var value: Double
            var j = i + 1
            switch t {
            case "a", "an":
                if let next = text(j), ["half", "quarter", "couple"].contains(next) { return quantity(at: j) }
                value = 1
            case "half":
                value = 0.5
                j = skipping(["of"], from: j)
                j = skipping(["a", "an"], from: j)
                return (value, j)
            case "quarter":
                value = 0.25
                j = skipping(["of"], from: j)
                j = skipping(["a", "an"], from: j)
                return (value, j)
            case "couple":
                value = 2
                j = skipping(["of"], from: j)
            default:
                if let n = number(t) {
                    value = n
                } else if let n = Self.numberWords[t] {
                    value = n
                    if n >= 20, n.truncatingRemainder(dividingBy: 10) == 0, let next = text(j), let ones = Self.numberWords[next], ones < 10 {
                        value += ones
                        j += 1
                    }
                } else {
                    return nil
                }
            }
            if text(j) == "and", text(j + 1) == "a", text(j + 2) == "half", unit(at: j + 3) != nil {
                value += 0.5
                j += 3
            }
            return (value, j)
        }

        func skipping(_ words: Set<String>, from i: Int) -> Int {
            if let t = text(i), words.contains(t) { return i + 1 }
            return i
        }

        func number(_ s: String) -> Double? {
            guard !s.contains(":"), let n = Double(s), n.isFinite else { return nil }
            return n
        }

        func unit(at i: Int) -> (TimeInterval, Int)? {
            guard let t = text(i) else { return nil }
            switch t {
            case "s", "sec", "secs", "second", "seconds": return (1, i + 1)
            case "m", "min", "mins", "minute", "minutes", "mn": return (60, i + 1)
            case "h", "hr", "hrs", "hour", "hours": return (3600, i + 1)
            default: return nil
            }
        }

        /// Words that introduce a time of day.
        static let clockWords: Set<String> = ["at", "until", "till", "by"]

        /// A time of day: "18:30", "18.30", "6pm", "6:15 am", "6", "noon", "midnight". Returns the
        /// seconds until its next occurrence. A bare "6" means whichever of 6:00 and 18:00 comes first.
        func clock(at i: Int, needsMeridiem: Bool) -> (TimeInterval, Int)? {
            guard let t = text(i) else { return nil }
            var j = i + 1
            if !needsMeridiem, t == "noon" || t == "midnight" {
                return next(hour: t == "noon" ? 12 : 0, minute: 0).map { ($0, j) }
            }
            let parts = t.split(omittingEmptySubsequences: false, whereSeparator: { $0 == ":" || $0 == "." })
            guard (1...2).contains(parts.count), parts.allSatisfy({ !$0.isEmpty && $0.allSatisfy(\.isNumber) }),
                  let h = Int(parts[0]), parts[0].count <= 2 else { return nil }
            var hour = h
            var minute = 0
            var ambiguous = false
            if parts.count == 2 {
                guard parts[1].count == 2, let m = Int(parts[1]) else { return nil }
                minute = m
            }
            let meridiem = text(j).flatMap { ["am", "pm"].contains($0) ? $0 : nil }
            if meridiem != nil { j += 1 } else if needsMeridiem || unit(at: j) != nil { return nil }
            if text(j) == "o", text(j + 1) == "clock" { j += 2 }
            guard (0...59).contains(minute) else { return nil }
            if let meridiem {
                guard (1...12).contains(hour) else { return nil }
                hour = hour % 12 + (meridiem == "pm" ? 12 : 0)
            } else {
                guard (0...23).contains(hour) else { return nil }
                // "at 6" or "at 6:30": morning or evening, whichever is next. "06:30" is always morning.
                ambiguous = (1...12).contains(hour) && !parts[0].hasPrefix("0")
            }
            guard var seconds = next(hour: hour, minute: minute) else { return nil }
            if ambiguous, let other = next(hour: (hour + 12) % 24, minute: minute) { seconds = min(seconds, other) }
            return (seconds, j)
        }

        func next(hour: Int, minute: Int) -> TimeInterval? {
            let target = calendar.nextDate(after: now, matching: DateComponents(hour: hour, minute: minute, second: 0),
                                           matchingPolicy: .nextTime)
            return target.map { $0.timeIntervalSince(now) }
        }

        static let numberWords: [String: Double] = [
            "one": 1, "two": 2, "three": 3, "four": 4, "five": 5, "six": 6, "seven": 7, "eight": 8, "nine": 9,
            "ten": 10, "eleven": 11, "twelve": 12, "thirteen": 13, "fourteen": 14, "fifteen": 15, "sixteen": 16,
            "seventeen": 17, "eighteen": 18, "nineteen": 19, "twenty": 20, "thirty": 30, "forty": 40, "fifty": 50,
            "sixty": 60, "seventy": 70, "eighty": 80, "ninety": 90,
        ]
    }

    // MARK: Title

    /// Words left over after the duration, minus connectors ("to", "for") and command words
    /// ("set a timer", "remind me to"), with a capital first letter.
    static func cleanTitle(_ words: [String]) -> String? {
        let edge = CharacterSet(charactersIn: ".,;:!?-–—\"'“”‘’()")
        var list = words.map { $0.trimmingCharacters(in: edge) }.filter { !$0.isEmpty }
        let leading: [[String]] = [["remind", "me", "to"], ["remind", "me"], ["set", "a", "timer"], ["set", "timer"],
                                   ["start", "a", "timer"], ["start", "timer"], ["a", "timer"], ["timer"],
                                   ["to"], ["for"], ["and"], ["then"]]
        let trailing: Set<String> = ["timer", "to", "for", "in", "at", "and", "after", "until", "by"]
        var changed = true
        while changed, !list.isEmpty {
            changed = false
            for phrase in leading where list.count >= phrase.count
                && zip(list, phrase).allSatisfy({ $0.lowercased() == $1 }) {
                list.removeFirst(phrase.count)
                changed = true
                break
            }
            if let last = list.last, trailing.contains(last.lowercased()) {
                list.removeLast()
                changed = true
            }
        }
        guard !list.isEmpty else { return nil }
        var title = list.joined(separator: " ")
        if title.count > 80 { title = String(title.prefix(80)).trimmingCharacters(in: .whitespaces) }
        return title.prefix(1).uppercased() + title.dropFirst()
    }
}
