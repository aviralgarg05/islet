import Foundation

/// The teleprompter's arithmetic: how fast the script moves for a reading pace, and where it is
/// at a moment. The view moves the text with one linear animation from where it is to the end,
/// so nothing ticks while it scrolls; these give the same answer the animation draws.
public enum Teleprompter {
    /// The longest script kept, in characters (a long talk is about 60,000).
    public static let maxScriptLength = 200_000

    /// Words in a script: runs of letters or digits, with apostrophes inside a word ("it's").
    public static func wordCount(_ script: String) -> Int {
        var count = 0
        var inWord = false
        for scalar in script.unicodeScalars {
            let letter = CharacterSet.alphanumerics.contains(scalar)
            if letter && !inWord { count += 1 }
            inWord = letter || (inWord && (scalar == "'" || scalar == "\u{2019}"))
        }
        return count
    }

    /// Seconds to read `words` at `wordsPerMinute`.
    public static func readingTime(words: Int, wordsPerMinute: Double) -> TimeInterval {
        guard words > 0, wordsPerMinute > 0 else { return 0 }
        return Double(words) / wordsPerMinute * 60
    }

    /// How far the text moves in all: until its last line has reached the reading line near the
    /// top, `lead` points below the page's top edge.
    public static func travel(textHeight: Double, lead: Double) -> Double {
        max(0, textHeight - lead)
    }

    /// Points a second that read `words` in the time the pace allows over `travel` points. A
    /// script too short to need moving doesn't move.
    public static func speed(travel: Double, words: Int, wordsPerMinute: Double) -> Double {
        let time = readingTime(words: words, wordsPerMinute: wordsPerMinute)
        guard travel > 0, time > 0 else { return 0 }
        return travel / time
    }

    /// "About 3 min" for a script, "Under a minute" for a short one.
    public static func durationLabel(words: Int, wordsPerMinute: Double) -> String {
        let minutes = readingTime(words: words, wordsPerMinute: wordsPerMinute) / 60
        if minutes < 1 { return "Under a minute" }
        return "About \(Int(minutes.rounded())) min"
    }

    /// Points a line of a classic mouse wheel moves the script.
    public static let wheelLine: Double = 12

    /// How far a scroll over the page moves the script, in points (positive goes on in the
    /// script), or nil when the scroll isn't the script's: with no script to move, or a mostly
    /// sideways scroll. Then it stays a swipe, so swiping up still closes the island.
    public static func scrollDistance(dx: Double, dy: Double, precise: Bool, hasScript: Bool) -> Double? {
        guard hasScript, dy != 0, dx.isFinite, dy.isFinite, abs(dy) >= abs(dx) else { return nil }
        return -dy * (precise ? 1 : wheelLine)
    }

    /// The script as kept: no trailing blank lines or spaces, and no longer than the limit.
    public static func normalised(_ script: String) -> String {
        var s = script.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        while let last = s.unicodeScalars.last, CharacterSet.whitespacesAndNewlines.contains(last) { s.unicodeScalars.removeLast() }
        if s.count > maxScriptLength { s = String(s.prefix(maxScriptLength)) }
        return s
    }
}

/// How the teleprompter page is cut into lines of the script. `shown` is the height drawn;
/// `whole` the lines that fit in it whole; `gap` the space between two lines. The next line
/// peeks in under the whole ones only when at least half of it shows, so it reads as words,
/// never as the dots of its i's.
public struct TeleprompterLines: Equatable, Sendable {
    public var shown: CGFloat
    public var whole: Int
    public var pitch: CGFloat
    public var gap: CGFloat

    /// `line` is one line's height, `pitch` from one line to the next; 0 before they are known.
    public init(height: CGFloat, line: CGFloat, pitch: CGFloat) {
        guard line > 0, pitch >= line, height > 0 else {
            shown = max(0, height); whole = 0; self.pitch = 0; gap = 0
            return
        }
        gap = pitch - line
        self.pitch = pitch
        whole = max(1, Int(((height + gap) / pitch).rounded(.down)))
        let peek = height - CGFloat(whole) * pitch
        shown = peek >= line * 0.5 ? height : min(height, CGFloat(whole) * pitch)
    }

    /// Where the fades end and start, as fractions of `shown`: in from the top over a gap,
    /// and out at the bottom from the end of the last whole line.
    public var fade: (top: CGFloat, bottom: CGFloat) {
        guard pitch > 0 else { return (0.08, 0.8) }
        let h = max(1, shown)
        let top = min(0.3, max(gap, 4) / h)
        return (top, min(0.95, max(top + 0.01, (CGFloat(whole) * pitch - gap) / h)))
    }
}

/// Where the script is and whether it is moving. While playing, the position is worked out
/// from when it started, so pausing reads exactly where the animation had got to.
public struct TeleprompterPlayback: Equatable, Sendable {
    /// Position when it last started or stopped, in points scrolled.
    public private(set) var anchor: Double = 0
    /// When it started moving from `anchor`; nil while paused.
    public private(set) var startedAt: Date?
    /// Points a second while playing.
    public private(set) var speed: Double = 0
    /// The furthest it goes.
    public private(set) var end: Double = 0

    public init() {}

    public var isPlaying: Bool { startedAt != nil }

    /// Where it is at `now`, between the top and the end.
    public func position(at now: Date) -> Double {
        guard let startedAt else { return min(anchor, end) }
        return min(end, anchor + max(0, now.timeIntervalSince(startedAt)) * speed)
    }

    /// When it reaches the end and stops, while playing.
    public func endsAt(now: Date) -> Date? {
        guard isPlaying, speed > 0 else { return nil }
        let left = max(0, end - position(at: now))
        return now.addingTimeInterval(left / speed)
    }

    /// Seconds left until the end at this speed.
    public func remaining(at now: Date) -> TimeInterval {
        guard speed > 0 else { return 0 }
        return max(0, end - position(at: now)) / speed
    }

    public func isAtEnd(at now: Date) -> Bool { position(at: now) >= end - 0.5 }

    /// Start moving. From the end, it starts again from the top. Nothing to move, nothing starts.
    public mutating func play(now: Date) {
        guard !isPlaying, speed > 0, end > 0 else { return }
        if isAtEnd(at: now) { anchor = 0 }
        startedAt = now
    }

    public mutating func pause(now: Date) {
        guard isPlaying else { return }
        anchor = position(at: now)
        startedAt = nil
    }

    /// A scroll by hand: it stops, then moves by `delta` points (positive goes on in the script).
    public mutating func scroll(by delta: Double, now: Date) {
        pause(now: now)
        anchor = min(end, max(0, anchor + delta))
    }

    /// `position` on the nearest whole line, for lines `pitch` points apart: where a paused
    /// script rests, so no line sits across the page's top edge. Never past the end; the end
    /// itself stays where it is.
    public static func onLine(_ position: Double, pitch: Double, end: Double) -> Double {
        guard pitch > 0, pitch.isFinite, position.isFinite, position < end - 0.5 else { return position }
        let nearest = (position / pitch).rounded() * pitch
        return max(0, nearest <= end ? nearest : (end / pitch).rounded(.down) * pitch)
    }

    /// Paused, settle on the nearest whole line (`onLine`), so playing again starts from
    /// where the page shows it.
    public mutating func settle(pitch: Double) {
        guard !isPlaying else { return }
        anchor = Self.onLine(anchor, pitch: pitch, end: end)
    }

    /// Back to the top, paused.
    public mutating func restart() {
        anchor = 0
        startedAt = nil
    }

    /// A new pace or a new layout: the position stays and, while playing, it goes on from there.
    public mutating func configure(speed newSpeed: Double, end newEnd: Double, now: Date) {
        let here = position(at: now)
        let playing = isPlaying
        speed = max(0, newSpeed.isFinite ? newSpeed : 0)
        end = max(0, newEnd.isFinite ? newEnd : 0)
        anchor = min(here, end)
        startedAt = playing && speed > 0 && anchor < end ? now : nil
    }

    /// Stop once the end is reached. Returns whether anything changed.
    public mutating func advance(now: Date) -> Bool {
        guard isPlaying, isAtEnd(at: now) else { return false }
        anchor = end
        startedAt = nil
        return true
    }
}

/// The script, kept as plain text in Islet's support folder. Written atomically and readable
/// only by the user.
public struct TeleprompterScriptFile: Sendable {
    public let url: URL

    public init(url: URL) { self.url = url }

    public static var standard: TeleprompterScriptFile {
        TeleprompterScriptFile(url: IsletPaths.supportDirectory.appendingPathComponent("teleprompter.txt"))
    }

    /// The saved script, or "" when there is none.
    public func read() -> String {
        guard let data = try? Data(contentsOf: url) else { return "" }
        return Teleprompter.normalised(String(decoding: data, as: UTF8.self))
    }

    /// Saves the script; an empty one removes the file.
    public func write(_ script: String) throws {
        let text = Teleprompter.normalised(script)
        let fm = FileManager.default
        if text.isEmpty {
            if fm.fileExists(atPath: url.path) { try fm.removeItem(at: url) }
            return
        }
        try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url, options: .atomic)
        try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
}
