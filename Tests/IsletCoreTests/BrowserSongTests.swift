import Foundation
import Testing
@testable import IsletCore

/// Lyrics for music in a web browser: what YouTube, YouTube Music and the like report, read as a
/// song LRCLIB could know, and everything else left alone or left out.
@Suite struct BrowserSongTests {
    struct Case: CustomTestStringConvertible, Sendable {
        var title: String
        var artist: String
        var album: String?
        var song: String
        var by: String
        var unsure = false

        var testDescription: String { title }
    }

    @Test(arguments: [
        // An artist's own channel, and YouTube's VEVO and "Topic" channels.
        Case(title: "Rick Astley - Never Gonna Give You Up (Official Music Video)", artist: "Rick Astley",
             song: "Never Gonna Give You Up", by: "Rick Astley"),
        Case(title: "Adele - Hello (Official Music Video)", artist: "AdeleVEVO", song: "Hello", by: "Adele"),
        Case(title: "The Weeknd – Blinding Lights (Official Audio)", artist: "TheWeekndVEVO", song: "Blinding Lights", by: "The Weeknd"),
        Case(title: "Taylor Swift - Anti-Hero (Official Music Video)", artist: "TaylorSwiftVEVO", song: "Anti-Hero", by: "Taylor Swift"),
        Case(title: "Tum Hi Ho", artist: "Arijit Singh - Topic", song: "Tum Hi Ho", by: "Arijit Singh"),
        Case(title: "Shape of You", artist: "Ed Sheeran - Topic", song: "Shape of You", by: "Ed Sheeran"),
        Case(title: "Guru Randhawa - Lahore (Official Video)", artist: "Guru Randhawa Official", song: "Lahore", by: "Guru Randhawa"),
        // Labels in brackets, after a colon and at the end, with whatever credits follow them.
        Case(title: "Billie Eilish - bad guy [Lyric Video]", artist: "Billie Eilish", song: "bad guy", by: "Billie Eilish"),
        Case(title: "Coldplay - Viva La Vida (Official Video)", artist: "Coldplay", song: "Viva La Vida", by: "Coldplay"),
        Case(title: "Diljit Dosanjh: G.O.A.T. (Official Video) Karan Aujla | Desi Crew | Latest Punjabi Songs 2020",
             artist: "Diljit Dosanjh", song: "G.O.A.T.", by: "Diljit Dosanjh"),
        Case(title: "Sidhu Moose Wala - 295 (Official Audio) | The Kidd | Moosetape", artist: "Sidhu Moose Wala",
             song: "295", by: "Sidhu Moose Wala"),
        Case(title: "Adele - \"Easy On Me\" (Official Video)", artist: "Adele", song: "Easy On Me", by: "Adele"),
        // Featured artists go, bracketed or not.
        Case(title: "Daft Punk - Get Lucky (Official Audio) ft. Pharrell Williams, Nile Rodgers", artist: "Daft Punk",
             song: "Get Lucky", by: "Daft Punk"),
        Case(title: "Luis Fonsi - Despacito ft. Daddy Yankee", artist: "LuisFonsiVEVO", song: "Despacito", by: "Luis Fonsi"),
        Case(title: "Despacito ft. Daddy Yankee", artist: "Luis Fonsi", song: "Despacito", by: "Luis Fonsi"),
        Case(title: "AP Dhillon - Brown Munde (Official Video) ft. Gurinder Gill, Shinda Kahlon", artist: "AP Dhillon",
             song: "Brown Munde", by: "AP Dhillon"),
        Case(title: "Calm Down (feat. Selena Gomez) - Rema", artist: "Rema", song: "Calm Down", by: "Rema"),
        // Hindi and Punjabi songs in Latin script, with "| Song" and credits after the bar.
        Case(title: "Tera Naa | Song", artist: "Gurlez Akhtar", song: "Tera Naa", by: "Gurlez Akhtar"),
        Case(title: "Excuses (Official Audio) | AP Dhillon | Gurinder Gill | Intense", artist: "AP Dhillon", song: "Excuses",
             by: "AP Dhillon"),
        Case(title: "AP Dhillon | Excuses | Official Audio", artist: "AP Dhillon", song: "Excuses", by: "AP Dhillon"),
        // A version after a dash is the same song's words.
        Case(title: "Bohemian Rhapsody - Remastered 2011", artist: "Queen", song: "Bohemian Rhapsody", by: "Queen"),
        // YouTube Music and the other players' web pages report the song itself, with its album.
        Case(title: "Brown Munde", artist: "AP Dhillon, Gurinder Gill & Shinda Kahlon", album: "Brown Munde",
             song: "Brown Munde", by: "AP Dhillon, Gurinder Gill & Shinda Kahlon"),
        Case(title: "Kesariya (From \"Brahmastra\")", artist: "Pritam, Arijit Singh & Amitabh Bhattacharya",
             album: "Kesariya (From \"Brahmastra\")", song: "Kesariya (From \"Brahmastra\")", by: "Pritam, Arijit Singh & Amitabh Bhattacharya"),
        Case(title: "Tum Hi Ho (Official Audio)", artist: "Arijit Singh", album: "Aashiqui 2", song: "Tum Hi Ho", by: "Arijit Singh"),
        // A label's channel that names nobody in the title: the artist is a guess.
        Case(title: "Full Video: Tum Hi Ho | Aashiqui 2 | Aditya Roy Kapur, Shraddha Kapoor | Mithoon | Arijit Singh",
             artist: "T-Series", song: "Tum Hi Ho", by: "T-Series", unsure: true),
        Case(title: "Lyrical: Kesariya | Brahmāstra | Arijit Singh | Pritam", artist: "Sony Music India", song: "Kesariya",
             by: "Sony Music India", unsure: true),
        Case(title: "Pasoori | Coke Studio | Season 14 | Ali Sethi x Shae Gill", artist: "Coke Studio Pakistan", song: "Pasoori",
             by: "Coke Studio Pakistan", unsure: true),
        Case(title: "Alan Walker - Faded (Lyrics)", artist: "7clouds", song: "Faded", by: "Alan Walker", unsure: true),
        // Credits that leave the channel out: it may be the singer's or a label's.
        Case(title: "Kesariya | Brahmastra | Lyrical", artist: "Arijit Singh", song: "Kesariya", by: "Arijit Singh", unsure: true),
    ])
    func readsTheSong(c: Case) throws {
        let song = try #require(BrowserSong.song(title: c.title, artist: c.artist, album: c.album))
        #expect(song.title == c.song)
        #expect(song.artist == c.by)
        #expect(song.unsure == c.unsure)
    }

    /// "Song - Film" and "Song - Singer" are as common on Indian labels' channels as "Artist -
    /// Song" is elsewhere: with a channel that is neither half, both halves are searched.
    @Test(arguments: [
        ("Kesariya - Brahmāstra | Ranbir Kapoor | Alia Bhatt | Pritam | Arijit Singh | Amitabh Bhattacharya", "Sony Music India",
         "Kesariya", "Brahmāstra"),
        ("Lahore - Guru Randhawa | Official Video | T-Series", "T-Series", "Lahore", "Guru Randhawa"),
        ("Lag Ja Gale - Lata Mangeshkar | Woh Kaun Thi | Old Hindi Song", "Saregama Music", "Lag Ja Gale", "Lata Mangeshkar"),
    ])
    func eitherHalfMayBeTheSong(title: String, channel: String, left: String, right: String) throws {
        let song = try #require(BrowserSong.song(title: title, artist: channel))
        #expect(song.unsure)
        #expect(song.title == right)
        #expect(song.otherTitle == left)
        let np = NowPlaying(source: .browser, bundleID: "com.google.Chrome", title: title, artist: channel, isPlaying: true,
                            duration: 240, elapsed: 0, timestamp: Date(timeIntervalSince1970: 0))
        let q = try #require(LyricsQuery(np, includeBrowsers: true))
        #expect(q.searchText == "\(left) \(right)")
        let items = try #require(URLComponents(url: LRCLIB.searchURL(q), resolvingAgainstBaseURL: false)?.queryItems)
        #expect(items.map(\.name) == ["q"], "the search gets the title's words, not a guessed artist")
    }

    @Test(arguments: [
        ("The Joe Rogan Experience #2000 - Podcast", "PowerfulJRE"),
        ("Avengers: Doomsday | Official Trailer", "Marvel Entertainment"),
        ("🔴 LIVE: India vs Australia, 3rd ODI", "Star Sports"),
        ("iPhone 17 Pro Review: Two Weeks Later", "Marques Brownlee"),
        ("Kapil Sharma Show | Full Episode 12", "Sony LIV"),
        ("Lecture 1: Introduction to Algorithms", "MIT OpenCourseWare"),
        ("Weekly vlog: Delhi in the rain", "Wanderlust Diaries"),
        ("Interview with the director", "Film Companion"),
        ("Minecraft Hardcore Gameplay #12", "Some Gamer"),
        ("City sounds 24/7", "Ambient Worlds"),
    ])
    func videosThatArentSongsAreLeftOut(title: String, channel: String) {
        #expect(BrowserSong.song(title: title, artist: channel) == nil)
    }

    /// A browser plays the news, lessons and vlogs as often as songs. With browsers on, a video
    /// that shows no sign of music (no label such as "(Official Video)", no music channel, no
    /// half of "A - B" naming the channel) is left out, so its title never reaches LRCLIB and it
    /// gets no lyrics button. The cost: an artist's upload titled only "Song | Artist" is left
    /// out too, as it reads just like "Budget 2026 | Nirmala Sitharaman | Aaj Tak".
    @Test(arguments: [
        ("Breaking News: Earthquake shakes Delhi | Aaj Tak", "Aaj Tak"),
        ("Budget 2026 | Nirmala Sitharaman | Aaj Tak", "Aaj Tak"),
        ("How to Center a Div in CSS", "Kevin Powell"),
        ("Python Lists - Lesson 3", "Corey Schafer"),
        ("Symptoms of Type 2 Diabetes - What to Look For", "Mayo Clinic"),
        ("Making Sourdough at Home", "Joshua Weissman"),
        ("I Tried Living on $1 for a Week", "MrBeast"),
        ("Apple Event - September 9", "Apple"),
        ("lofi hip hop radio 📚 beats to relax/study to", "Lofi Girl"),
        ("Excuses | AP Dhillon | Gurinder Gill | Intense", "AP Dhillon"),
    ])
    func videosWithNoSignOfMusicAreLeftOut(title: String, channel: String) {
        #expect(BrowserSong.song(title: title, artist: channel) == nil)
        let np = NowPlaying(source: .browser, bundleID: "com.google.Chrome", title: title, artist: channel, isPlaying: true,
                            duration: 420, elapsed: 30, timestamp: Date(timeIntervalSince1970: 0))
        #expect(LyricsQuery(np, includeBrowsers: true) == nil)
        #expect(!LyricsQuery.couldHaveLyrics(np), "no lyrics button either")
    }

    /// A live stream has no length, so even a song's is never looked up.
    @Test func aLiveStreamIsNeverLookedUp() throws {
        let stream = NowPlaying(source: .browser, bundleID: "com.google.Chrome", title: "Adele - Hello (Official Video)",
                                artist: "AdeleVEVO", isPlaying: true, duration: nil, elapsed: 30,
                                timestamp: Date(timeIntervalSince1970: 0))
        #expect(BrowserSong.song(title: stream.title, artist: "AdeleVEVO") != nil)
        #expect(LyricsQuery(stream, includeBrowsers: true) == nil)
    }

    /// Titles a looser reading got wrong: a version word that starts a song's own title
    /// ("Demons", "Stereo Hearts", "Live Forever"), a VEVO title with a colon, a singer after a
    /// label, and a channel's own name ahead of the song.
    @Test(arguments: [
        Case(title: "Imagine Dragons - Demons (Official Music Video)", artist: "ImagineDragonsVEVO", song: "Demons",
             by: "Imagine Dragons"),
        Case(title: "Oasis - Live Forever (Official HD Remastered Video)", artist: "Oasis", song: "Live Forever", by: "Oasis"),
        Case(title: "Gym Class Heroes - Stereo Hearts ft. Adam Levine [Official Video]", artist: "Fueled By Ramen",
             song: "Stereo Hearts", by: "Gym Class Heroes", unsure: true),
        Case(title: "Ariana Grande - Monopoly (Audio)", artist: "Ariana Grande", song: "Monopoly", by: "Ariana Grande"),
        Case(title: "Coldplay - Viva La Vida - Live in São Paulo", artist: "Coldplay", song: "Viva La Vida", by: "Coldplay"),
        Case(title: "Hello: Live at the NRJ Music Awards", artist: "AdeleVEVO", song: "Hello: Live at the NRJ Music Awards",
             by: "Adele"),
        Case(title: "Coke Studio | Season 14 | Pasoori | Ali Sethi x Shae Gill", artist: "Coke Studio Pakistan", song: "Pasoori",
             by: "Coke Studio Pakistan", unsure: true),
    ])
    func titlesThatLookLikeVersionsOrChannels(c: Case) throws {
        let song = try #require(BrowserSong.song(title: c.title, artist: c.artist, album: c.album))
        #expect(song.title == c.song)
        #expect(song.artist == c.by)
        #expect(song.unsure == c.unsure)
    }

    @Test func aSingerAfterALabelIsKept() throws {
        let song = try #require(BrowserSong.song(title: "Tera Naa (Official Video) - Gurlez Akhtar", artist: "Speed Records"))
        #expect(song.unsure)
        #expect([song.title, song.otherTitle] == ["Gurlez Akhtar", "Tera Naa"], "both halves are searched")
        // A label after the dash still goes.
        let label = try #require(BrowserSong.song(title: "Tera Naa (Official Video) - Latest Punjabi Song 2024", artist: "Speed Records"))
        #expect(label.title == "Tera Naa")
    }

    @Test func aPartNamingTheChannelIsNotTheSong() {
        #expect(BrowserSong.namesChannel("Coke Studio", "Coke Studio Pakistan"))
        #expect(BrowserSong.namesChannel("AP Dhillon", "APDhillon"))
        #expect(BrowserSong.namesChannel("Season 14", "Coke Studio Pakistan"))
        #expect(!BrowserSong.namesChannel("Love", "Lovely Music"), "whole words only")
        #expect(!BrowserSong.namesChannel("Pasoori", "Coke Studio Pakistan"))
    }

    @Test func versionsAreWholeWords() {
        #expect(BrowserSong.dropVersion("Bohemian Rhapsody - Remastered 2011") == "Bohemian Rhapsody")
        #expect(BrowserSong.dropVersion("Here Comes the Sun - 2019 Mix") == "Here Comes the Sun")
        #expect(BrowserSong.dropVersion("Blinding Lights - Radio Edit") == "Blinding Lights")
        #expect(BrowserSong.dropVersion("Kesariya - Slowed + Reverb") == "Kesariya")
        #expect(BrowserSong.dropVersion("Fix You - Live at River Plate") == "Fix You")
        #expect(BrowserSong.dropVersion("Imagine Dragons - Demons") == "Imagine Dragons - Demons")
        #expect(BrowserSong.dropVersion("Gym Class Heroes - Stereo Hearts") == "Gym Class Heroes - Stereo Hearts")
        #expect(BrowserSong.dropVersion("Oasis - Live Forever") == "Oasis - Live Forever")
        #expect(BrowserSong.dropVersion("Pixies - Up") == "Pixies - Up")
        // Never down to the artist alone.
        #expect(BrowserSong.dropVersion("Mono - Mono", artist: "Mono") == "Mono - Mono")
    }

    @Test func needsATitleAndAnArtist() {
        #expect(BrowserSong.song(title: "  ", artist: "Adele") == nil)
        #expect(BrowserSong.song(title: "Hello", artist: " ") == nil)
        #expect(BrowserSong.song(title: "(Official Video)", artist: "Adele") == nil)
    }

    @Test func namesCompareWithoutCaseAccentsOrSpaces() {
        #expect(BrowserSong.same("Brahmāstra", "brahmastra"))
        #expect(BrowserSong.same("Arijit Singh", "ArijitSingh"))
        #expect(!BrowserSong.same("Coke Studio", "Coke Studio Pakistan"))
        #expect(BrowserSong.bareTitle("Kesariya (From \"Brahmastra\")") == "Kesariya")
        #expect(BrowserSong.bareTitle("Bohemian Rhapsody - Remastered 2011") == "Bohemian Rhapsody")
        #expect(BrowserSong.bareTitle("(Intro)") == "(Intro)")
    }
}

@Suite struct BrowserLyricsQueryTests {
    func video(_ title: String, artist: String? = "AdeleVEVO", album: String? = nil, duration: Double? = 295,
               bundle: String = "com.google.Chrome") -> NowPlaying {
        NowPlaying(source: .browser, bundleID: bundle, appName: "Google Chrome", title: title, artist: artist, album: album,
                   isPlaying: true, duration: duration, elapsed: 10, timestamp: Date(timeIntervalSince1970: 0))
    }

    @Test func browsersOnlyWithTheirSwitch() throws {
        let np = video("Adele - Hello (Official Music Video)")
        #expect(LyricsQuery(np) == nil)
        #expect(LyricsQuery(np, includeBrowsers: false) == nil)
        let q = try #require(LyricsQuery(np, includeBrowsers: true))
        #expect(q.title == "Hello")
        #expect(q.artist == "Adele")
        #expect(q.fromBrowser)
        #expect(q.searchText == nil)
        #expect(LyricsQuery.origin(of: np) == .browser)
        // A browser's helper process, and one reported by the system bridge, count as browsers.
        #expect(LyricsQuery.origin(of: NowPlaying(source: .system, bundleID: "com.google.Chrome.helper", title: "x", isPlaying: true,
                                                  timestamp: Date())) == .browser)
        #expect(LyricsQuery.couldHaveLyrics(np))
    }

    @Test func aBrowserMustSayHowLongAndLookLikeASong() {
        #expect(LyricsQuery(video("Adele - Hello", duration: nil), includeBrowsers: true) == nil, "a live stream")
        #expect(LyricsQuery(video("Adele - Hello", duration: 20), includeBrowsers: true) == nil, "an advert or a short")
        #expect(LyricsQuery(video("Adele - Hello", duration: 16 * 60), includeBrowsers: true) == nil, "a mix")
        #expect(LyricsQuery(video("Adele - Hello", artist: nil), includeBrowsers: true) == nil)
        #expect(LyricsQuery(video("Avengers: Doomsday | Official Trailer", artist: "Marvel"), includeBrowsers: true) == nil)
        #expect(!LyricsQuery.couldHaveLyrics(video("Avengers: Doomsday | Official Trailer", artist: "Marvel")))
        #expect(LyricsQuery(video("Adele - Hello", duration: 30), includeBrowsers: true) != nil)
        #expect(LyricsQuery(video("Adele - Hello", duration: 15 * 60), includeBrowsers: true) != nil)
    }

    @Test func musicAndSpotifyMayLeaveTheLengthOut() {
        let spotify = NowPlaying(source: .spotify, bundleID: "com.spotify.client", title: "Tum Hi Ho", artist: "Arijit Singh",
                                 isPlaying: true, duration: nil, timestamp: Date())
        #expect(LyricsQuery(spotify) != nil)
        #expect(LyricsQuery.origin(of: spotify) == .player)
        var long = spotify
        long.duration = 16 * 60
        #expect(LyricsQuery(long) == nil)
        // Other apps never: a podcast app, a video call.
        let podcast = NowPlaying(source: .system, bundleID: "com.apple.podcasts", title: "Episode", artist: "Host", isPlaying: true,
                                 duration: 1800, timestamp: Date())
        #expect(LyricsQuery.origin(of: podcast) == nil)
        #expect(!LyricsQuery.couldHaveLyrics(podcast))
    }

    @Test func youTubeMusicKeepsItsAlbum() throws {
        let q = try #require(LyricsQuery(video("Tum Hi Ho", artist: "Arijit Singh", album: "Aashiqui 2", duration: 262),
                                         includeBrowsers: true))
        #expect(q.title == "Tum Hi Ho")
        #expect(q.album == "Aashiqui 2")
        let items = try #require(URLComponents(url: LRCLIB.getURL(q), resolvingAgainstBaseURL: false)?.queryItems)
        #expect(Set(items.map(\.name)) == ["track_name", "artist_name", "album_name", "duration"])
    }
}

@Suite struct BrowserLyricsMatchTests {
    let video: LyricsQuery = {
        var q = LyricsQuery(title: "Paper Lanterns", artist: "Neon Harbour", duration: 262)
        q.fromBrowser = true
        return q
    }()

    @Test func aMusicVideosLengthMayDifferAndThenTheWordsShowWithoutTimes() throws {
        let record = LRCLIBRecord(id: 1, trackName: "Paper Lanterns", artistName: "Neon Harbour", duration: 214,
                                  syncedLyrics: "[00:01.00]first\n[00:03.00]second")
        #expect(LRCLIB.best([record], for: video)?.id == 1)
        let lyrics = try #require(LRCLIB.lyrics(from: record, for: video))
        #expect(!lyrics.isSynced, "the video's intro would run the times early")
        #expect(lyrics.plain == "first\nsecond")
        // The same length keeps the times.
        var exact = video
        exact.duration = 215
        #expect(LRCLIB.lyrics(from: record, for: exact)?.isSynced == true)
        // Music and Spotify report the recording's length: a different one is another recording.
        var player = video
        player.fromBrowser = false
        #expect(LRCLIB.best([record], for: player) == nil)
    }

    @Test func aLooseLengthNeedsTheSameTitle() {
        let other = LRCLIBRecord(id: 2, trackName: "Something Else", duration: 230, syncedLyrics: "[00:01.00]x")
        let far = LRCLIBRecord(id: 3, trackName: "Paper Lanterns", duration: 400, syncedLyrics: "[00:01.00]x")
        #expect(LRCLIB.best([other, far], for: video) == nil)
        // The same length wins over a closer title.
        let sameLength = LRCLIBRecord(id: 4, trackName: "Paper Lanterns (Live)", duration: 262.4, syncedLyrics: "[00:01.00]x")
        let sameTitle = LRCLIBRecord(id: 5, trackName: "Paper Lanterns", duration: 240, syncedLyrics: "[00:01.00]x")
        #expect(LRCLIB.best([sameTitle, sameLength], for: video)?.id == 4)
    }

    @Test func aGuessedArtistOnlyTakesTheSongsTitle() {
        var q = LyricsQuery(title: "Brahmāstra", artist: "Kesariya", duration: 268)
        q.fromBrowser = true
        q.searchText = "Kesariya Brahmāstra"
        q.otherTitle = "Kesariya"
        let records = [
            LRCLIBRecord(id: 1, trackName: "Deva Deva (From \"Brahmastra\")", duration: 268, syncedLyrics: "[00:01.00]x"),
            LRCLIBRecord(id: 2, trackName: "Kesariya (From \"Brahmastra\")", artistName: "Pritam", duration: 268.2,
                         syncedLyrics: "[00:01.00]x"),
        ]
        #expect(LRCLIB.best(records, for: q)?.id == 2)
        #expect(LRCLIB.best([records[0]], for: q) == nil)
    }
}
