import Foundation
import Testing
@testable import IsletCore

/// The cap on a decoded cover must never be what softens one.
@Suite struct ArtworkDecodeTests {
    @Test func theCapIsEnoughForEverySizeTheIslandDraws() {
        // Every size `ArtworkView` and `VinylDisc` are given, largest first.
        for points in [ArtworkDecode.largestDrawn, 72, 56, 40, 26, 20, 18] {
            #expect(ArtworkDecode.isSharp(at: points))
        }
        // And it is a real cap, not an excuse: a cover drawn across the open island would need more.
        #expect(!ArtworkDecode.isSharp(at: 900))
        #expect(ArtworkDecode.maxPixels < 1024)
    }
}

/// A player's artwork stays through a report that leaves it out, for the same track only.
@Suite struct BridgeArtworkTests {
    func video(_ title: String = "Live", app: String? = "com.google.Chrome") -> NowPlaying {
        NowPlaying(source: .browser, bundleID: app, title: title, artist: "Channel", isPlaying: true, timestamp: t0)
    }

    func entry(_ np: NowPlaying, _ hash: Int?, _ bytes: [UInt8]? = nil) -> BridgeArtwork.Entry {
        BridgeArtwork.Entry(player: np, hash: hash, bytes: bytes.map { Data($0) })
    }

    /// Chrome posts its info twice every quarter of a minute, the picture second. The first post
    /// alone, read between the two, used to show Chrome's icon for a moment and replay the
    /// artwork's arrival.
    @Test func chromesTwoStepUpdateKeepsThePicture() {
        var art = BridgeArtwork()
        #expect(art.resolve([entry(video(), 7, [1, 2])]).first?.artworkData == Data([1, 2]))
        #expect(art.resolve([entry(video(), nil)]).first?.artworkData == Data([1, 2]))
        #expect(art.resolve([entry(video(), 7)]).first?.artworkData == Data([1, 2]))
    }

    /// A helper started again knows nothing it sent before: its first report, without the
    /// picture, keeps the one the island has.
    @Test func aRestartedHelperKeepsThePicture() {
        var art = BridgeArtwork()
        _ = art.resolve([entry(video(), 7, [1])])
        #expect(art.resolve([entry(video(), nil)]).first?.artworkData == Data([1]))
    }

    @Test func anotherTrackOrPlayerDoesNotTakeIt() {
        var art = BridgeArtwork()
        _ = art.resolve([entry(video(), 7, [1])])
        // The next video, still without its own picture, has none.
        #expect(art.resolve([entry(video("Next"), nil)]).first?.artworkData == nil)
        // And the old picture isn't kept for when the first video comes back.
        #expect(art.resolve([entry(video(), nil)]).first?.artworkData == nil)
        // Safari playing the same title is another player.
        _ = art.resolve([entry(video(), 7, [1])])
        let both = art.resolve([entry(video(), nil), entry(video(app: "com.apple.Safari"), nil)])
        #expect(both.map(\.artworkData) == [Data([1]), nil])
    }

    /// A hash it doesn't know names other artwork: the old picture isn't passed off as it.
    @Test func anUnknownHashIsNotTheOldPicture() {
        var art = BridgeArtwork()
        _ = art.resolve([entry(video(), 7, [1])])
        #expect(art.resolve([entry(video(), 8)]).first?.artworkData == nil)
    }

    @Test func aPlayerThatGoesTakesItsPicture() {
        var art = BridgeArtwork()
        _ = art.resolve([entry(video(), 7, [1])])
        _ = art.resolve([])
        #expect(art.byHash.isEmpty)
        #expect(art.resolve([entry(video(), 7)]).first?.artworkData == nil)
        #expect(art.resolve([entry(video(), nil)]).first?.artworkData == nil)
    }
}
