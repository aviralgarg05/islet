import Foundation

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
