import CoreGraphics
import Foundation

/// How big a cover is kept once it is decoded.
///
/// A player embeds whatever it likes: a 3000 pixel square cover is ordinary, and decoding one
/// costs about 36 MB of bitmap, held until the track changes. The island draws a cover far smaller
/// than that, so nearly all of it is bitmap nobody looks at. The bytes themselves are already
/// bounded (`HelperLines` keeps a helper line under 8 MB), but a few megabytes of JPEG decode to a
/// great deal more.
public enum ArtworkDecode {
    /// The largest a cover is ever drawn, in points: the open island's now-playing card.
    public static let largestDrawn: CGFloat = 72
    /// Pixels per point to allow for: twice what any Mac display has today, so a sharper one
    /// wouldn't make covers soft.
    public static let scaleAllowance: CGFloat = 4

    /// The longest side to decode a cover at: enough for the largest draw at `scaleAllowance`,
    /// rounded up to a power of two so one picture serves every size. A cover already smaller than
    /// this is kept as it is; nothing is ever enlarged.
    public static let maxPixels = 512

    /// Whether `maxPixels` leaves a cover drawn `points` across sharp. The cap must never be the
    /// thing that softens artwork, so this holds for every size the island draws.
    public static func isSharp(at points: CGFloat, scale: CGFloat = scaleAllowance) -> Bool {
        CGFloat(maxPixels) >= points * scale
    }
}

/// The artwork the Now Playing helper sent, for the players in its last report.
///
/// The helper sends a player's artwork only when it changes and names it by hash otherwise. A
/// report can also leave it out for a moment: Chrome posts its info in two steps, the picture
/// last, and a helper that has just started knows nothing it sent before. Such a report keeps the
/// picture the player had for the same track, rather than blinking to the app icon and back.
public struct BridgeArtwork: Equatable, Sendable {
    /// Bytes by the helper's hash.
    public private(set) var byHash: [Int: Data] = [:]
    /// Each player's last picture and the track it was for, by `MediaArbiter.playerID`.
    private var byPlayer: [String: Kept] = [:]

    private struct Kept: Equatable, Sendable {
        var track: String
        var hash: Int?
        var data: Data
    }

    public init() {}

    /// One player from a helper line: its snapshot, the hash it named and any new bytes.
    public struct Entry: Sendable {
        public var player: NowPlaying
        public var hash: Int?
        public var bytes: Data?

        public init(player: NowPlaying, hash: Int?, bytes: Data?) {
            self.player = player
            self.hash = hash
            self.bytes = bytes
        }
    }

    /// The players of one report with their artwork filled in. Afterwards this holds only what
    /// they use, so a player that goes takes its picture with it.
    public mutating func resolve(_ entries: [Entry]) -> [NowPlaying] {
        var hashes: [Int: Data] = [:]
        var players: [String: Kept] = [:]
        let resolved = entries.map { e -> NowPlaying in
            var np = e.player
            let id = MediaArbiter.playerID(np)
            if let hash = e.hash, let data = e.bytes ?? byHash[hash] {
                np.artworkData = data
                hashes[hash] = data
                players[id] = Kept(track: np.trackKey, hash: hash, data: data)
            } else if let kept = byPlayer[id] ?? players[id], kept.track == np.trackKey, e.hash == nil || e.hash == kept.hash {
                // Nothing new for the same track: the picture it had stays.
                np.artworkData = kept.data
                if let h = kept.hash { hashes[h] = kept.data }
                players[id] = kept
            }
            return np
        }
        byHash = hashes
        byPlayer = players
        return resolved
    }
}
