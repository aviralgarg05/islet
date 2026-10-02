import CoreGraphics
import Foundation

// GIF stickers: a small animation in the closed island's right wing while music plays (the
// "GIF" look of the playing indicator). Five built-ins drawn for Islet (scripts/make-stickers.py)
// and up to twelve of the user's own, copied into the support folder. The decisions live here:
// which sticker, where it sits, how its frames are timed and what an import may be.

/// The stickers that come with Islet, in the order the gallery shows them.
public enum BuiltInSticker: String, CaseIterable, Sendable {
    case cat, jelly, notes, record, star

    public var title: String {
        switch self {
        case .cat: return "Cat"
        case .jelly: return "Jelly"
        case .notes: return "Notes"
        case .record: return "Record"
        case .star: return "Star"
        }
    }

    /// The file in the app's Stickers folder.
    public var fileName: String { "\(rawValue).gif" }
}

/// Which sticker shows: a built-in one, or one of the user's own by its id.
public enum StickerChoice: Equatable, Hashable, Sendable {
    case builtIn(BuiltInSticker)
    case custom(String)

    /// Custom ids are what `CustomStickerID.make()` gives: lower-case hex and dashes, so an id
    /// from a hand-edited config.json can never name a path outside the stickers folder.
    public init?(id: String) {
        if let b = BuiltInSticker(rawValue: id) {
            self = .builtIn(b)
        } else if id.hasPrefix(Self.customPrefix), CustomStickerID.isValid(String(id.dropFirst(Self.customPrefix.count))) {
            self = .custom(String(id.dropFirst(Self.customPrefix.count)))
        } else {
            return nil
        }
    }

    public var id: String {
        switch self {
        case .builtIn(let b): return b.rawValue
        case .custom(let name): return Self.customPrefix + name
        }
    }

    static let customPrefix = "custom-"
}

/// Names for the user's stickers in the stickers folder.
public enum CustomStickerID {
    /// A fresh id: a UUID in lower case.
    public static func make() -> String { UUID().uuidString.lowercased() }

    /// Only lower-case hex digits and dashes, 1 to 64 of them: no dots, no slashes.
    public static func isValid(_ name: String) -> Bool {
        !name.isEmpty && name.count <= 64 && name.unicodeScalars.allSatisfy { ("0"..."9").contains($0) || ("a"..."f").contains($0) || $0 == "-" }
    }

    /// The file for `name` in `directory`, or nil for a name that isn't one of ours.
    public static func file(_ name: String, in directory: URL) -> URL? {
        guard isValid(name) else { return nil }
        return directory.appendingPathComponent("\(name).\(fileExtension)")
    }

    /// Stickers are kept as animated PNG, which keeps soft edges from any source.
    public static let fileExtension = "png"
}

/// The sticker's settings (Settings → Now Playing → Playing indicator → GIF).
public struct StickerSettings: Codable, Equatable, Sendable {
    /// `BuiltInSticker.rawValue`, or "custom-" and the id of one of the user's own.
    public var id = BuiltInSticker.cat.rawValue
    /// Points right (positive) or left of where it sits by default, at the wing's outer edge.
    public var offsetX: Double = 0
    /// Points down (positive) or up from the middle of the menu bar row.
    public var offsetY: Double = 0
    /// Size against the standard one.
    public var scale: Double = 1
    /// Show the sticker, still, beside the notch when nothing is playing. Off: the island stays
    /// hidden as usual.
    public var whenIdle = false

    public static let offsetRange: ClosedRange<Double> = -12...12
    public static let scaleRange: ClosedRange<Double> = 0.6...1.6

    public init(id: String = BuiltInSticker.cat.rawValue, offsetX: Double = 0, offsetY: Double = 0, scale: Double = 1,
                whenIdle: Bool = false) {
        self.id = id; self.offsetX = offsetX; self.offsetY = offsetY; self.scale = scale; self.whenIdle = whenIdle
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = StickerSettings()
        id = (try? c.decodeIfPresent(String.self, forKey: .id)) ?? d.id
        offsetX = (try? c.decodeIfPresent(Double.self, forKey: .offsetX)) ?? d.offsetX
        offsetY = (try? c.decodeIfPresent(Double.self, forKey: .offsetY)) ?? d.offsetY
        scale = (try? c.decodeIfPresent(Double.self, forKey: .scale)) ?? d.scale
        whenIdle = (try? c.decodeIfPresent(Bool.self, forKey: .whenIdle)) ?? d.whenIdle
        self = sanitized()
    }

    /// Offsets in whole points and the size in tenths, inside their ranges; an id that names
    /// nothing Islet could have made becomes the cat.
    public func sanitized() -> StickerSettings {
        var s = self
        let d = StickerSettings()
        func clamp(_ v: Double, _ r: ClosedRange<Double>, step: Double, _ fallback: Double) -> Double {
            guard v.isFinite else { return fallback }
            return min(r.upperBound, max(r.lowerBound, (v / step).rounded() * step))
        }
        s.offsetX = clamp(offsetX, Self.offsetRange, step: 1, d.offsetX)
        s.offsetY = clamp(offsetY, Self.offsetRange, step: 1, d.offsetY)
        s.scale = (clamp(scale, Self.scaleRange, step: 0.1, d.scale) * 10).rounded() / 10
        if StickerChoice(id: id) == nil { s.id = d.id }
        return s
    }

    public var choice: StickerChoice { StickerChoice(id: id) ?? .builtIn(.cat) }

    /// The sticker that shows: the chosen one, or the cat when it is one of yours whose file
    /// has gone (removed, or a config.json from another Mac). The island and the gallery's
    /// selection both follow this, so they never disagree.
    public func shown(customExists: (String) -> Bool) -> StickerChoice {
        if case .custom(let name) = choice, !customExists(name) { return .builtIn(.cat) }
        return choice
    }
}

/// What the sticker is doing: playing with the music, frozen and dim while it is paused, or
/// resting, still, beside the notch when nothing plays ("Also when nothing is playing").
public enum StickerMode: Equatable, Sendable {
    case playing, paused, idle
}

/// How the sticker's frames are shown in a given state: looping, or one frame held still.
public enum StickerPlayback: Equatable, Sendable {
    /// Play the loop, starting at this frame.
    case loop(from: Int)
    /// Hold this frame.
    case hold(Int)

    /// It loops only while the music plays, for a picture with more than one frame, without
    /// Reduce Motion (or animation style Off) and outside Low Power Mode. Otherwise it holds a
    /// frame: the first with Reduce Motion and when resting with nothing playing, the one it
    /// had reached when paused or in Low Power Mode. `current` is the frame on show now.
    public static func plan(mode: StickerMode, animated: Bool, reduceMotion: Bool, lowPower: Bool, current: Int) -> StickerPlayback {
        let frame = max(0, current)
        if mode == .playing, animated, !reduceMotion, !lowPower { return .loop(from: frame) }
        return .hold(reduceMotion || mode == .idle ? 0 : frame)
    }

    /// Paused music dims the sticker as it does the bars; playing and resting are whole.
    public static func opacity(_ mode: StickerMode, paused: Float) -> Float {
        mode == .paused ? paused : 1
    }
}

/// What an imported sticker may be.
public enum StickerLimits {
    /// The user's own stickers, at most.
    public static let maxCustom = 12
    /// Bigger files are turned away before they are read.
    public static let maxFileBytes = 5 * 1024 * 1024
    /// Longer animations keep this many frames, spread over the whole loop.
    public static let maxFrames = 150
    /// Pictures with more pixels than this (per frame) are turned away unread.
    public static let maxSourcePixels = 4096 * 4096
    /// A kept sticker fits this box, in pixels: the menu bar row's height at 2x, and twice as
    /// wide for wide ones.
    public static let storedHeight = 80
    public static let storedWidth = 160
    /// The quickest a frame may go.
    public static let minDelay = 0.02
    /// A frame that asks for this little time or less (0 or 10 ms, old tools' "as fast as you
    /// can") gets `defaultDelay` instead, as browsers play it.
    public static let browserFloor = 0.011
    /// A frame that says nothing about its time, or something unreadable, gets this.
    public static let defaultDelay = 0.1
    /// No frame waits longer than this.
    public static let maxDelay = 10.0
}

/// Why a file can't be a sticker, in plain words for Settings.
public enum StickerImportError: Error, Equatable, Sendable {
    case full
    case tooLarge
    case tooBigPicture
    case notAnimation
    case unreadable
    case couldNotSave

    public var message: String {
        switch self {
        case .full: return "You have \(StickerLimits.maxCustom) stickers already. Remove one to add another."
        case .tooLarge: return "That file is over 5 MB. Try a smaller one."
        case .tooBigPicture: return "That picture is too big to use as a sticker."
        case .notAnimation: return "Islet can use GIF, animated PNG, WebP and HEIC files."
        case .unreadable: return "Islet couldn't read that file."
        case .couldNotSave: return "Islet couldn't save the sticker."
        }
    }
}

/// The frame-timing maths: each frame's time, the key times for the animation that plays them,
/// thinning very long animations, and where a paused sticker is in its loop.
public enum StickerTiming {
    /// Each frame's delay, as the file asks, made safe and played as a browser plays it: 0 or
    /// 10 ms (under `browserFloor`), missing or unreadable is `defaultDelay`; anything else is
    /// at least `minDelay` and at most `maxDelay`.
    public static func delays(_ raw: [Double?]) -> [Double] {
        raw.map { d in
            guard let d, d.isFinite, d >= StickerLimits.browserFloor else { return StickerLimits.defaultDelay }
            return min(StickerLimits.maxDelay, max(StickerLimits.minDelay, d))
        }
    }

    public static func duration(_ delays: [Double]) -> Double { delays.reduce(0, +) }

    /// The frame rate the loop asks Core Animation for: as often as its quickest frame needs,
    /// and never more than 30 a second.
    public static func frameRate(_ delays: [Double]) -> Float {
        guard let quickest = delays.filter({ $0.isFinite && $0 > 0 }).min() else { return 10 }
        return Float(min(30, max(1, (1 / quickest).rounded(.up))))
    }

    /// Key times for a discrete keyframe animation over `delays`: one more than the frames,
    /// from 0 to 1, each frame starting at its share of the loop.
    public static func keyTimes(_ delays: [Double]) -> [Double] {
        let total = duration(delays)
        guard total > 0, !delays.isEmpty else { return [0, 1] }
        var times: [Double] = [0]
        var t = 0.0
        for d in delays.dropLast() {
            t += d
            times.append(t / total)
        }
        times.append(1)
        return times
    }

    /// The frames to keep from `count` so no more than `limit` remain, spread evenly from the
    /// first, so a long animation still plays its whole loop.
    public static func kept(count: Int, limit: Int = StickerLimits.maxFrames) -> [Int] {
        guard count > 0, limit > 0 else { return [] }
        guard count > limit else { return Array(0..<count) }
        var out: [Int] = []
        for k in 0..<limit {
            let i = Int((Double(k) * Double(count) / Double(limit)).rounded(.down))
            if out.last != i { out.append(i) }
        }
        return out
    }

    /// The delays of the kept frames: each one also takes the time of the frames dropped after
    /// it, so the loop lasts as long as before.
    public static func delays(_ delays: [Double], keeping kept: [Int]) -> [Double] {
        guard !kept.isEmpty else { return [] }
        return kept.enumerated().map { k, start in
            let end = k + 1 < kept.count ? kept[k + 1] : delays.count
            return delays[start..<max(start + 1, min(end, delays.count))].reduce(0, +)
        }
    }

    /// The frame showing `time` seconds into the loop.
    public static func frame(at time: Double, delays: [Double]) -> Int {
        let total = duration(delays)
        guard total > 0, time.isFinite else { return 0 }
        var t = time.truncatingRemainder(dividingBy: total)
        if t < 0 { t += total }
        for (i, d) in delays.enumerated() {
            if t < d { return i }
            t -= d
        }
        return max(0, delays.count - 1)
    }

    /// When frame `index` starts, in seconds into the loop.
    public static func start(of index: Int, delays: [Double]) -> Double {
        delays.prefix(max(0, min(index, delays.count))).reduce(0, +)
    }
}

/// Where the sticker sits in the closed island's right wing. Everything stays inside the menu
/// bar row and inside the wing, whatever the offsets and size say: nothing hangs below the row
/// and nothing covers the menu bar.
public enum StickerLayout {
    /// The standard height in points: a little taller than the closed artwork, never more than
    /// the row allows.
    public static func standardHeight(row: CGFloat) -> CGFloat { max(10, min(24, row - 8)) }

    /// The sizes that look different in a row `row` points tall: past the row's height (less
    /// a point each side) the sticker is held to the row, so Settings' slider stops there.
    public static func scaleRange(row: CGFloat) -> ClosedRange<Double> {
        let all = StickerSettings.scaleRange
        guard row.isFinite, row > 2 else { return all }
        let most = (Double((row - 2) / standardHeight(row: row)) * 10).rounded(.down) / 10
        return all.lowerBound...min(all.upperBound, max(all.lowerBound + 0.1, most))
    }

    /// How far, in whole points, a sticker at `scale` can move left (negative) and right of
    /// where it rests before the wing holds it: across the room, and into the space beyond it.
    public static func horizontalRange(room: CGFloat, row: CGFloat, outerSpace: CGFloat, aspect: CGFloat,
                                       scale: Double) -> ClosedRange<Double> {
        let r = frame(room: room, row: row, outerSpace: outerSpace, aspect: aspect, settings: StickerSettings(scale: scale))
        guard r.width > 0 else { return 0...0 }
        let cap = StickerSettings.offsetRange.upperBound
        let left = min(cap, max(0, Double((r.minX - 1).rounded(.down))))
        let right = min(cap, max(0, Double((room + max(0, outerSpace) - 1 - r.maxX).rounded(.down))))
        return -left...right
    }

    /// How far, in whole points, a sticker at `scale` can move up or down from the middle of
    /// the row before the row's edge holds it. 0 when it fills the row.
    public static func verticalReach(row: CGFloat, scale: Double) -> Double {
        guard row.isFinite, row > 2 else { return 0 }
        let h = min(row - 2, standardHeight(row: row) * CGFloat(scale.isFinite ? scale : 1))
        return min(StickerSettings.offsetRange.upperBound, max(0, Double(((row - 2 - h) / 2).rounded(.down))))
    }

    /// The sticker's frame inside the wing's room: `room` points wide (from the notch side to
    /// the content inset at the wing's outer edge) and `row` points tall. `aspect` is the
    /// sticker's width over its height. At rest it sits against the outer edge, centred in the
    /// row; the offsets move it from there and are held inside the room, and a sticker bigger
    /// than the room is scaled down to fit.
    public static func frame(room: CGFloat, row: CGFloat, outerSpace: CGFloat, aspect: CGFloat,
                             settings s: StickerSettings) -> CGRect {
        guard room > 0, row > 0 else { return .zero }
        let a = aspect.isFinite && aspect > 0 ? min(4, max(0.25, aspect)) : 1
        // The room plus the space outside it (the wing's inset), less a point at each edge.
        let box = CGRect(x: 1, y: 1, width: max(1, room + max(0, outerSpace) - 2), height: max(1, row - 2))
        var h = standardHeight(row: row) * CGFloat(s.scale.isFinite ? s.scale : 1)
        var w = h * a
        let fit = min(1, box.width / w, box.height / h)
        h *= fit; w *= fit
        let restX = room - w  // right edge on the room's outer edge
        let restY = (row - h) / 2
        let x = min(box.maxX - w, max(box.minX, restX + CGFloat(s.offsetX)))
        let y = min(box.maxY - h, max(box.minY, restY + CGFloat(s.offsetY)))
        return CGRect(x: x, y: y, width: w, height: h)
    }

    /// The pixel size to decode frames at for a frame `size` points big on a screen of `scale`.
    public static func pixelSize(_ size: CGSize, scale: CGFloat) -> Int {
        let s = scale.isFinite && scale > 0 ? scale : 2
        return max(1, Int((max(size.width, size.height) * s).rounded(.up)))
    }
}
