import Foundation
import Testing
@testable import IsletCore

@Suite struct ToolSettingsTests {
    @Test func everyToolStartsOff() {
        let s = IsletSettings()
        #expect(!s.mirror.enabled && !s.teleprompter.enabled && !s.stocks.enabled && !s.sales.enabled)
        #expect(!s.openRouterUsageEnabled && !s.ollamaUsageEnabled && !s.copilotUsageEnabled)
        #expect(s.sales.stores.isEmpty)
        let pages = IslandPage.switcher(s, current: nil)
        for tool in [IslandPage.mirror, .teleprompter, .stocks, .sales, .stats] {
            #expect(!pages.main.contains(tool) && !pages.more.contains(tool))
            #expect(!tool.isAvailable(s))
        }
    }

    @Test func toolsTurnedOnAreListedUnderMoreOnly() {
        var s = IsletSettings()
        s.mirror.enabled = true
        s.teleprompter.enabled = true
        s.stocks.enabled = true
        s.sales.enabled = true
        s.shortcutsEnabled = true
        s.weatherEnabled = true
        s.todosEnabled = true
        s.noteEnabled = true
        s.converterEnabled = true
        s.emojiEnabled = true
        s.systemStatsEnabled = true
        let pages = IslandPage.switcher(s, current: nil)
        #expect(pages.main == [.home, .today, .shelf])
        #expect(pages.more.contains(.todos) && pages.more.contains(.emoji))
        #expect(Array(pages.more.suffix(4)) == [.mirror, .teleprompter, .stocks, .sales])
        #expect(IslandPage.allCases.allSatisfy { $0.isAvailable(s) || $0 == .widgets || $0 == .clipboard })
    }

    @Test func toolSettingsRoundTripThroughTheFile() throws {
        var s = IsletSettings()
        s.mirror = MirrorSettings(enabled: true, flipped: false)
        s.teleprompter.enabled = true
        s.teleprompter.wordsPerMinute = 180
        s.teleprompter.seeThrough = true
        s.sales = SalesSettings(enabled: true, stores: [.paddle, .stripe], shopifyStore: "example")
        s.stocks = StocksSettings(enabled: true, symbols: ["NVDA", "^FTSE"])
        s.copilotUsageEnabled = true
        s.copilotPlan = .proPlus
        let data = try JSONEncoder().encode(s)
        #expect(IsletSettings.decodeLenient(data) == s)
    }

    @Test func aBadValueInsideAToolFallsBackAlone() {
        let json = """
        {"teleprompter": {"enabled": true, "wordsPerMinute": "fast", "textSize": 99},
         "sales": {"enabled": true, "stores": ["stripe", "etsy", "stripe", "polar"], "shopifyStore": "  shop  "},
         "stocks": {"enabled": true, "symbols": ["aapl", "AAPL", "bad symbol", "^gspc", "btc-usd"]},
         "mirror": {"enabled": "yes", "flipped": false},
         "copilotPlan": 7}
        """
        let s = IsletSettings.decodeLenient(Data(json.utf8))
        #expect(s.teleprompter.enabled)
        #expect(s.teleprompter.wordsPerMinute == 140)
        #expect(s.teleprompter.textSize == TeleprompterSettings.textSizeRange.upperBound)
        #expect(s.sales.stores == [.stripe, .polar])
        #expect(s.sales.shopifyStore == "shop")
        #expect(s.stocks.symbols == ["AAPL", "^GSPC", "BTC-USD"])
        #expect(!s.mirror.enabled && !s.mirror.flipped)
        #expect(s.copilotPlan == .pro)
    }

    @Test func watchlistIsCapped() {
        let many = (0..<30).map { "S\($0)" }
        #expect(StocksSettings(enabled: true, symbols: many).sanitized().symbols.count == StocksSettings.maxSymbols)
    }

    @Test func paceAndSizeStayInRange() {
        var t = TeleprompterSettings()
        t.wordsPerMinute = 10
        t.textSize = .infinity
        let s = t.sanitized()
        #expect(s.wordsPerMinute == TeleprompterSettings.wordsPerMinuteRange.lowerBound)
        #expect(s.textSize == TeleprompterSettings().textSize)
    }

    @Test func cameraPermissionNamesTheMirror() {
        var s = IsletSettings()
        #expect(PermissionKind.camera.uses(s) == [PermissionUse("Camera mirror", on: false)])
        s.mirror.enabled = true
        #expect(PermissionKind.camera.uses(s).first?.isOn == true)
        #expect(PermissionKind.camera.settingsURL.absoluteString.hasSuffix("Privacy_Camera"))
        // The Permissions page names it as the Tools page does.
        #expect(SettingsIndex.entries.contains { $0.title == "Camera mirror" && $0.page == .tools })
    }

    @Test func everyToolHasASearchEntry() {
        for query in ["teleprompter", "mirror", "stocks", "watchlist", "sales", "Stripe", "Paddle", "OpenRouter", "Ollama", "Copilot",
                      "words per minute", "see-through"] {
            #expect(!SettingsIndex.search(query).isEmpty, "\(query)")
        }
        #expect(SettingsIndex.search("Shopify").first?.page == .tools)
        #expect(SettingsIndex.search("OpenRouter").first?.page == .agents)
        #expect(SettingsPage.tools.group == .features)
    }
}

@Suite struct TeleprompterTests {
    let t0 = Date(timeIntervalSince1970: 1_790_000_000)

    @Test func wordsAndReadingTime() {
        #expect(Teleprompter.wordCount("") == 0)
        #expect(Teleprompter.wordCount("Hello, world! It's 9 o'clock.") == 5)
        #expect(Teleprompter.wordCount("don’t stop") == 2)
        #expect(Teleprompter.wordCount("  line one\n\nline two  ") == 4)
        #expect(Teleprompter.readingTime(words: 140, wordsPerMinute: 140) == 60)
        #expect(Teleprompter.readingTime(words: 10, wordsPerMinute: 0) == 0)
        #expect(Teleprompter.durationLabel(words: 50, wordsPerMinute: 140) == "Under a minute")
        #expect(Teleprompter.durationLabel(words: 420, wordsPerMinute: 140) == "About 3 min")
    }

    @Test func speedReadsTheScriptInTheTimeThePaceAllows() {
        let travel = Teleprompter.travel(textHeight: 1_000, lead: 40)
        #expect(travel == 960)
        // 280 words at 140 a minute: two minutes for 960 points.
        #expect(Teleprompter.speed(travel: travel, words: 280, wordsPerMinute: 140) == 8)
        #expect(Teleprompter.speed(travel: 0, words: 280, wordsPerMinute: 140) == 0)
        #expect(Teleprompter.travel(textHeight: 30, lead: 40) == 0)
    }

    @Test func playPauseAndScrollKeepThePosition() {
        var p = TeleprompterPlayback()
        p.configure(speed: 10, end: 100, now: t0)
        #expect(!p.isPlaying && p.position(at: t0) == 0)
        p.play(now: t0)
        #expect(p.position(at: t0.addingTimeInterval(3)) == 30)
        #expect(p.endsAt(now: t0.addingTimeInterval(3)) == t0.addingTimeInterval(10))
        p.pause(now: t0.addingTimeInterval(4))
        #expect(!p.isPlaying && p.position(at: t0.addingTimeInterval(60)) == 40)
        p.scroll(by: -100, now: t0.addingTimeInterval(61))
        #expect(p.position(at: t0) == 0)
        p.scroll(by: 25, now: t0)
        #expect(p.position(at: t0) == 25)
        // Scrolling while playing stops it where it is, then moves.
        p.play(now: t0)
        p.scroll(by: 5, now: t0.addingTimeInterval(1))
        #expect(!p.isPlaying && p.position(at: t0) == 40)
    }

    @Test func thePageShowsWholeLines() {
        // 28 pt text on the smallest island: two whole lines, and none of the third's dots.
        let large = TeleprompterLines(height: 90, line: 33.4, pitch: 40.4)
        #expect(large.whole == 2 && abs(large.shown - 80.8) < 0.001)
        // 20 pt text: three whole lines fill it.
        let small = TeleprompterLines(height: 90, line: 24, pitch: 30)
        #expect(small.whole == 3 && small.shown == 90)
        // Most of the next line showing: it peeks in, fading.
        let peek = TeleprompterLines(height: 110, line: 24, pitch: 30)
        #expect(peek.whole == 3 && peek.shown == 110)
        // A sliver of it: the page stops after the whole lines.
        #expect(TeleprompterLines(height: 121, line: 24, pitch: 30).shown == 120)
        #expect(peek.fade.bottom < 1 && peek.fade.top > 0)
        // Before the lines are measured: the whole page, with plain fades.
        #expect(TeleprompterLines(height: 90, line: 0, pitch: 0).shown == 90)
    }

    @Test func aPausedScriptRestsOnWholeLines() {
        #expect(TeleprompterPlayback.onLine(18, pitch: 30, end: 500) == 30)
        #expect(TeleprompterPlayback.onLine(44, pitch: 30, end: 500) == 30)
        #expect(TeleprompterPlayback.onLine(0, pitch: 30, end: 500) == 0)
        // Never past the end, and the end itself stays.
        #expect(TeleprompterPlayback.onLine(95, pitch: 30, end: 100) == 90)
        #expect(TeleprompterPlayback.onLine(100, pitch: 30, end: 100) == 100)
        #expect(TeleprompterPlayback.onLine(40, pitch: 0, end: 100) == 40)
        var p = TeleprompterPlayback()
        p.configure(speed: 10, end: 300, now: t0)
        p.play(now: t0)
        p.settle(pitch: 30)
        #expect(p.isPlaying)
        p.pause(now: t0.addingTimeInterval(4.7))
        p.settle(pitch: 30)
        #expect(p.position(at: t0) == 60)
    }

    @Test func reachingTheEndStopsAndPlayStartsAgainFromTheTop() {
        var p = TeleprompterPlayback()
        p.configure(speed: 50, end: 100, now: t0)
        p.play(now: t0)
        let early = p.advance(now: t0.addingTimeInterval(1))
        #expect(!early)
        let atEnd = p.advance(now: t0.addingTimeInterval(2))
        #expect(atEnd)
        #expect(!p.isPlaying && p.isAtEnd(at: t0) && p.endsAt(now: t0) == nil)
        p.play(now: t0.addingTimeInterval(3))
        #expect(p.position(at: t0.addingTimeInterval(3)) == 0)
        p.restart()
        #expect(!p.isPlaying && p.position(at: t0) == 0)
    }

    @Test func aNewPaceGoesOnFromWhereItIs() {
        var p = TeleprompterPlayback()
        p.configure(speed: 10, end: 200, now: t0)
        p.play(now: t0)
        p.configure(speed: 20, end: 200, now: t0.addingTimeInterval(5))
        #expect(p.isPlaying && p.position(at: t0.addingTimeInterval(5)) == 50)
        #expect(p.position(at: t0.addingTimeInterval(6)) == 70)
        // A shorter layout clamps it, and with nothing left to move it stops.
        p.configure(speed: 20, end: 60, now: t0.addingTimeInterval(6))
        #expect(!p.isPlaying && p.position(at: t0) == 60)
        // Nothing to move: play does nothing.
        var still = TeleprompterPlayback()
        still.configure(speed: 0, end: 0, now: t0)
        still.play(now: t0)
        #expect(!still.isPlaying)
    }

    @Test func onlyAnUpAndDownScrollOverAScriptMovesIt() {
        // Fingers up (natural scrolling reports a negative delta) go on in the script.
        #expect(Teleprompter.scrollDistance(dx: 0, dy: -6, precise: true, hasScript: true) == 6)
        #expect(Teleprompter.scrollDistance(dx: 1, dy: 4, precise: true, hasScript: true) == -4)
        // A wheel counts in lines.
        #expect(Teleprompter.scrollDistance(dx: 0, dy: -1, precise: false, hasScript: true) == Teleprompter.wheelLine)
        // Sideways, still, or with no script to move: it stays a swipe.
        #expect(Teleprompter.scrollDistance(dx: 8, dy: 2, precise: true, hasScript: true) == nil)
        #expect(Teleprompter.scrollDistance(dx: 0, dy: 0, precise: true, hasScript: true) == nil)
        #expect(Teleprompter.scrollDistance(dx: 0, dy: -6, precise: true, hasScript: false) == nil)
        #expect(Teleprompter.scrollDistance(dx: .nan, dy: -6, precise: true, hasScript: true) == nil)
    }

    @Test func scriptIsNormalised() {
        #expect(Teleprompter.normalised("Hello\r\nthere\n\n  \n") == "Hello\nthere")
        #expect(Teleprompter.normalised(String(repeating: "a", count: Teleprompter.maxScriptLength + 10)).count == Teleprompter.maxScriptLength)
    }

    @Test func scriptFileIsPrivateAndAnEmptyScriptRemovesIt() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("islet-prompter-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = TeleprompterScriptFile(url: dir.appendingPathComponent("teleprompter.txt"))
        #expect(file.read() == "")
        try file.write("Good morning.\n\n")
        #expect(file.read() == "Good morning.")
        let mode = try FileManager.default.attributesOfItem(atPath: file.url.path)[.posixPermissions] as? NSNumber
        #expect(mode?.intValue == 0o600)
        try file.write("   ")
        #expect(!FileManager.default.fileExists(atPath: file.url.path))
    }
}
