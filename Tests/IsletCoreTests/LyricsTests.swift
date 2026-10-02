import Foundation
import Testing
@testable import IsletCore

@Suite struct LRCParserTests {
    @Test func readsTimedLinesInOrder() {
        let lines = LRC.parse("""
        [ar: M83]
        [ti: Midnight City]
        [00:12.50] Waiting in a car
        [00:15.00]Waiting for a ride in the dark
        [00:09] The city is my church
        """)
        #expect(lines.map(\.time) == [9, 12.5, 15])
        #expect(lines.map(\.text) == ["The city is my church", "Waiting in a car", "Waiting for a ride in the dark"])
    }

    @Test func fractionsOfOneTwoOrThreeDigitsAndAColonBeforeThem() throws {
        let lines = LRC.parse("[01:02.5]a\n[01:02.25]b\n[01:02.125]c\n[01:03:50]d")
        #expect(lines.map(\.time) == [62.125, 62.25, 62.5, 63.5])
    }

    @Test func aRepeatedChorusHasSeveralTags() {
        let lines = LRC.parse("[00:10.00][01:10.00][02:10.00]Chorus\n[00:20.00]Verse")
        #expect(lines.map(\.time) == [10, 20, 70, 130])
        #expect(lines.filter { $0.text == "Chorus" }.count == 3)
    }

    @Test func offsetMovesEveryLineAndNeverBelowZero() {
        let lines = LRC.parse("[offset:+500]\n[00:00.20]First\n[00:10.00]Second")
        #expect(lines.map(\.time) == [0, 9.5])
        #expect(LRC.parse("[offset:-1000]\n[00:01.00]x").first?.time == 2)
    }

    @Test func emptyLinesStayAsBreaksAndWordTagsGo() {
        let lines = LRC.parse("[00:01.00]<00:01.00>Hello <00:01.50>there\n[00:04.00]\n[00:05.00]a <b> c")
        #expect(lines.map(\.text) == ["Hello there", "", "a <b> c"])
    }

    @Test func ignoresJunk() {
        #expect(LRC.parse("").isEmpty)
        #expect(LRC.parse("no tags here\n[xx:yy]bad\n[1:99]bad seconds\n[00:01.abc]bad fraction").isEmpty)
        #expect(LRC.parse("[length: 03:20]\n[by:someone]").isEmpty)
    }
}

@Suite struct SongLyricsTests {
    let lyrics = SongLyrics(lines: [
        LyricLine(time: 5, text: "one"), LyricLine(time: 10, text: "two"), LyricLine(time: 20, text: "three"),
    ])

    @Test func currentLineAtAPosition() {
        #expect(lyrics.index(at: 0) == nil)
        #expect(lyrics.index(at: 4.99) == nil)
        #expect(lyrics.index(at: 5) == 0)
        #expect(lyrics.index(at: 9.9) == 0)
        #expect(lyrics.index(at: 10) == 1)
        #expect(lyrics.index(at: 500) == 2)
        #expect(SongLyrics().index(at: 3) == nil)
    }

    @Test func nextChangeIsTheNextLine() {
        #expect(lyrics.nextTime(after: 0) == 5)
        #expect(lyrics.nextTime(after: 5) == 10)
        #expect(lyrics.nextTime(after: 12) == 20)
        #expect(lyrics.nextTime(after: 20) == nil)
    }

    @Test func changesFollowThePlayersRateAndStopWhilePaused() {
        let now = Date(timeIntervalSince1970: 1000)
        #expect(lyrics.changes(from: 6, rate: 1, now: now) == [now.addingTimeInterval(4), now.addingTimeInterval(14)])
        #expect(lyrics.changes(from: 6, rate: 2, now: now) == [now.addingTimeInterval(2), now.addingTimeInterval(7)])
        #expect(lyrics.changes(from: 6, rate: 0, now: now).isEmpty)
        #expect(lyrics.changes(from: 25, rate: 1, now: now).isEmpty)
    }
}

@Suite struct LyricsQueryTests {
    func song(_ source: MediaSourceKind = .spotify, bundle: String? = "com.spotify.client", title: String = "Midnight City",
              artist: String? = "M83", album: String? = "Hurry Up, We're Dreaming", duration: Double? = 243.4) -> NowPlaying {
        NowPlaying(source: source, bundleID: bundle, title: title, artist: artist, album: album, isPlaying: true,
                   duration: duration, elapsed: 0, timestamp: Date(timeIntervalSince1970: 0))
    }

    @Test func onlyMusicAndSpotifySongsAreLookedUp() {
        #expect(LyricsQuery(song()) != nil)
        #expect(LyricsQuery(song(.appleMusic, bundle: "com.apple.Music")) != nil)
        // Through the system bridge, the player is known by its bundle id.
        #expect(LyricsQuery(song(.system, bundle: "com.apple.Music")) != nil)
        #expect(LyricsQuery(song(.browser, bundle: "com.apple.Safari")) == nil)
        #expect(LyricsQuery(song(.system, bundle: "com.apple.podcasts")) == nil)
        #expect(LyricsQuery(song(.external, bundle: nil)) == nil)
    }

    @Test func needsATitleAndAnArtistAndASongsLength() {
        #expect(LyricsQuery(song(title: "  ")) == nil)
        #expect(LyricsQuery(song(artist: nil)) == nil)
        #expect(LyricsQuery(song(duration: 12)) == nil, "an advert")
        #expect(LyricsQuery(song(duration: 3600)) == nil, "a mix")
        #expect(LyricsQuery(song(duration: nil))?.duration == nil)
        #expect(LyricsQuery(song(album: " "))?.album == nil)
    }

    @Test func sendsOnlyTitleArtistAlbumAndDuration() throws {
        let q = try #require(LyricsQuery(song()))
        let url = LRCLIB.getURL(q)
        #expect(url.host == "lrclib.net")
        #expect(url.scheme == "https")
        #expect(url.path == "/api/get")
        let items = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
        #expect(Set(items.map(\.name)) == ["track_name", "artist_name", "album_name", "duration"])
        #expect(items.first { $0.name == "duration" }?.value == "243")
        #expect(items.first { $0.name == "album_name" }?.value == "Hurry Up, We're Dreaming")
        let search = try #require(URLComponents(url: LRCLIB.searchURL(q), resolvingAgainstBaseURL: false))
        #expect(search.path == "/api/search")
        #expect(Set(search.queryItems?.map(\.name) ?? []) == ["track_name", "artist_name", "album_name"])
    }

    @Test func plusSignsSurviveTheQuery() throws {
        let q = LyricsQuery(title: "1+1", artist: "Beyoncé")
        let url = LRCLIB.getURL(q)
        #expect(url.absoluteString.contains("1%2B1"))
        #expect(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first?.value == "1+1")
    }

    @Test func cacheKeyIgnoresCaseAndFractionsOfASecond() {
        let a = LyricsQuery(title: "Song", artist: "Band", album: "LP", duration: 200.2)
        let b = LyricsQuery(title: "song", artist: "BAND", album: "lp", duration: 199.8)
        let c = LyricsQuery(title: "Song", artist: "Band", album: "LP", duration: 230)
        #expect(a.cacheKey == b.cacheKey)
        #expect(a.cacheKey != c.cacheKey)
    }
}

@Suite struct LRCLIBTests {
    let q = LyricsQuery(title: "Midnight City", artist: "M83", album: "Hurry Up", duration: 243)

    @Test func decodesARecord() throws {
        let json = #"""
        {"id":1,"trackName":"Midnight City","artistName":"M83","albumName":"Hurry Up","duration":243.0,"instrumental":false,
         "plainLyrics":"Waiting in a car\nWaiting for a ride","syncedLyrics":"[00:01.00] Waiting in a car\n[00:03.00] Waiting for a ride"}
        """#
        let record = try JSONDecoder().decode(LRCLIBRecord.self, from: Data(json.utf8))
        let lyrics = try #require(LRCLIB.lyrics(from: record))
        #expect(lyrics.isSynced)
        #expect(lyrics.lines.count == 2)
        #expect(lyrics.plain?.hasPrefix("Waiting") == true)
    }

    @Test func plainOnlyInstrumentalAndEmpty() {
        #expect(LRCLIB.lyrics(from: LRCLIBRecord(plainLyrics: "Words"))?.isSynced == false)
        #expect(LRCLIB.lyrics(from: LRCLIBRecord(instrumental: true))?.instrumental == true)
        #expect(LRCLIB.lyrics(from: LRCLIBRecord(plainLyrics: "  ", syncedLyrics: "")) == nil)
        // Timed but wordless lines are no lyrics at all.
        #expect(LRCLIB.lyrics(from: LRCLIBRecord(syncedLyrics: "[00:01.00]\n[00:02.00]"))?.isSynced != true)
    }

    @Test func bestSearchResultHasTheSameLengthAndSyncedWords() {
        let records = [
            LRCLIBRecord(id: 1, trackName: "Midnight City", duration: 300, syncedLyrics: "[00:01.00]long version"),
            LRCLIBRecord(id: 2, trackName: "Midnight City", duration: 244, plainLyrics: "plain"),
            LRCLIBRecord(id: 3, trackName: "Midnight City (Live)", duration: 242, syncedLyrics: "[00:01.00]live"),
            LRCLIBRecord(id: 4, trackName: "Midnight City", duration: 243.5, syncedLyrics: "[00:01.00]right"),
        ]
        #expect(LRCLIB.best(records, for: q)?.id == 4)
        #expect(LRCLIB.best(Array(records.prefix(2)), for: q)?.id == 2)
        #expect(LRCLIB.best([records[0]], for: q) == nil, "a different length is a different recording")
        #expect(LRCLIB.best([], for: q) == nil)
    }

    @Test func userAgentNamesTheApp() {
        #expect(LRCLIB.userAgent(version: "0.2.0").hasPrefix("Islet 0.2.0"))
    }
}

@Suite struct LyricsCacheTests {
    func cache() -> (LyricsCache, URL) {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("islet-lyrics-\(UUID().uuidString)")
        return (LyricsCache(directory: dir, missingLifetime: 100, limit: 3), dir)
    }

    @Test func keepsFoundLyricsAndForgetsMissingOnesAfterAWhile() {
        let (c, dir) = cache()
        defer { try? FileManager.default.removeItem(at: dir) }
        let t = Date(timeIntervalSince1970: 1_000)
        let lyrics = SongLyrics(lines: [LyricLine(time: 1, text: "hi")])
        #expect(c.load("a", now: t) == nil)
        c.save("a", .found(lyrics), now: t)
        c.save("b", .missing, now: t)
        #expect(c.load("a", now: t.addingTimeInterval(1_000_000)) == .found(lyrics))
        #expect(c.load("b", now: t.addingTimeInterval(50)) == .missing)
        #expect(c.load("b", now: t.addingTimeInterval(150)) == nil)
    }

    @Test func filesAreNamedByHashNotTitle() {
        let (c, dir) = cache()
        let file = c.file("Midnight City\u{1F}M83")
        #expect(file.deletingLastPathComponent().path == dir.path)
        #expect(!file.lastPathComponent.contains("Midnight"))
        #expect(LyricsCache.hash("x") == LyricsCache.hash("x"))
        #expect(LyricsCache.hash("x") != LyricsCache.hash("y"))
        #expect(LyricsCache.hash("x").count == 16)
    }

    @Test func keepsAtMostTheLimit() throws {
        let (c, dir) = cache()
        defer { try? FileManager.default.removeItem(at: dir) }
        for i in 0..<6 { c.save("song \(i)", .missing, now: Date(timeIntervalSince1970: 1_000)) }
        let files = try FileManager.default.contentsOfDirectory(atPath: dir.path)
        #expect(files.count == 3)
    }
}

@Suite struct LyricsPlacementTests {
    @Test func lyricsTakeTheQuietColumn() {
        #expect(LyricsPlacement.column([], room: 1) == .lyrics(keeping: []))
        #expect(LyricsPlacement.column([.quiet, .quiet], room: 1) == .lyrics(keeping: []))
    }

    @Test func aCountingTimerStaysAboveTheLyrics() {
        // A Pomodoro running while the music plays is still on Home.
        #expect(LyricsPlacement.column([.quiet, .counting], room: 1) == .lyrics(keeping: [1]))
        #expect(LyricsPlacement.column([.counting, .quiet, .counting], room: 2) == .lyrics(keeping: [0, 2]))
    }

    @Test func moreCountingThanFitsKeepsTheGlances() {
        #expect(LyricsPlacement.column([.counting, .counting], room: 1) == .glances)
        #expect(LyricsPlacement.column([.counting], room: 0) == .glances)
    }

    @Test func somethingThatNeedsYouTakesTheColumnBack() {
        #expect(LyricsPlacement.column([.quiet, .needsYou], room: 2) == .glances)
        #expect(LyricsPlacement.column([.counting, .needsYou], room: 2) == .glances)
    }

    @Test func tallerIslandsKeepTwo() {
        #expect(LyricsPlacement.room(height: 90) == 1)
        #expect(LyricsPlacement.room(height: 160) == 2)
    }

    /// The lyrics button's offer takes the column from quiet glances and timers, never from an
    /// approval or a loud failure.
    @Test func theOfferWaitsForWhatNeedsYou() {
        #expect(LyricsPlacement.offerFits([]))
        #expect(LyricsPlacement.offerFits([.quiet, .counting]))
        #expect(!LyricsPlacement.offerFits([.quiet, .needsYou]))
    }
}

@Suite struct LyricsLookUpTests {
    @Test func aNewSongIsAlwaysLookedUp() {
        for state in [LyricsState.idle, .loading, .found(SongLyrics(plain: "x")), .missing, .failed] {
            #expect(state.needsLookUp(sameSong: false, force: false, sinceFailure: 0))
        }
    }

    /// The lyrics button clicked while the song's lookup is on its way sends nothing more: one
    /// lookup per song.
    @Test func aLookupOnItsWayIsNeverDoubled() {
        #expect(!LyricsState.loading.needsLookUp(sameSong: true, force: true, sinceFailure: 1000))
        #expect(!LyricsState.loading.needsLookUp(sameSong: true, force: false, sinceFailure: 1000))
    }

    @Test func aSettledSongIsAskedAgainOnlyByTheButton() {
        #expect(!LyricsState.missing.needsLookUp(sameSong: true, force: false, sinceFailure: 1000))
        #expect(LyricsState.missing.needsLookUp(sameSong: true, force: true, sinceFailure: 0))
        #expect(!LyricsState.found(SongLyrics(plain: "x")).needsLookUp(sameSong: true, force: false, sinceFailure: 1000))
    }

    @Test func aFailureIsTriedAgainAfterAMinute() {
        #expect(!LyricsState.failed.needsLookUp(sameSong: true, force: false, sinceFailure: 30))
        #expect(LyricsState.failed.needsLookUp(sameSong: true, force: false, sinceFailure: 61))
        #expect(LyricsState.failed.needsLookUp(sameSong: true, force: true, sinceFailure: 5))
    }
}
