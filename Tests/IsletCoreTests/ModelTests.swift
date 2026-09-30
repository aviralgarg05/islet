import CoreGraphics
import Foundation
import Testing
@testable import IsletCore

@Suite struct GeometryTests {
    // 14" MacBook Pro at default scaling: 1512x982, notch ~185pt wide, 32pt tall.
    let mbp = ScreenDescriptor(
        id: 1, name: "Built-in", frame: CGRect(x: 0, y: 0, width: 1512, height: 982),
        safeAreaTop: 32, auxiliaryLeftWidth: 663.5, auxiliaryRightWidth: 663.5, menuBarHeight: 32, isBuiltIn: true
    )
    let external = ScreenDescriptor(id: 2, name: "LG", frame: CGRect(x: 1512, y: 0, width: 1920, height: 1080), safeAreaTop: 0, menuBarHeight: 25)

    @Test func notchFromAuxiliaryAreas() {
        let m = NotchGeometry.metrics(for: mbp)
        #expect(!m.isSynthetic)
        #expect(m.notch == CGSize(width: 185, height: 32))
        #expect(m.compact.width == 185 + 2 * m.wingWidth)
    }

    @Test func fallbackWidthWithoutAuxiliaryAreas() {
        var s = mbp
        s.auxiliaryLeftWidth = nil
        s.auxiliaryRightWidth = nil
        #expect(NotchGeometry.metrics(for: s).notch.width == NotchGeometry.fallbackNotchWidth)
        // Absurd aux widths (would give a 0-wide notch) also fall back.
        s.auxiliaryLeftWidth = 756
        s.auxiliaryRightWidth = 756
        #expect(NotchGeometry.metrics(for: s).notch.width == NotchGeometry.fallbackNotchWidth)
    }

    @Test func syntheticPillOnExternalDisplay() {
        let m = NotchGeometry.metrics(for: external)
        #expect(m.isSynthetic)
        #expect(m.notch.height == 25)
        #expect(m.notch.width == NotchGeometry.syntheticWidth)
        var hidden = external
        hidden.menuBarHeight = 0
        #expect(NotchGeometry.metrics(for: hidden).notch.height == NotchGeometry.syntheticHeight)
    }

    @Test func expandedIsClampedToScreen() {
        let tiny = ScreenDescriptor(id: 3, name: "tiny", frame: CGRect(x: 0, y: 0, width: 500, height: 300), safeAreaTop: 0)
        let m = NotchGeometry.metrics(for: tiny, expandedSize: CGSize(width: 2000, height: 2000))
        #expect(m.expanded.width <= 460)
        #expect(m.expanded.height <= 150)
    }

    @Test func windowIsTopCenteredOnItsScreen() {
        let m = NotchGeometry.metrics(for: external)
        let f = NotchGeometry.windowFrame(for: external, metrics: m)
        #expect(abs(f.midX - external.frame.midX) < 0.001)
        #expect(f.maxY == external.frame.maxY)
        #expect(f.width >= m.expanded.width)
        let hover = NotchGeometry.hoverZone(for: external, metrics: m)
        #expect(hover.maxY == external.frame.maxY)
        #expect(hover.width == m.notch.width + 16)
        let visible = NotchGeometry.visibleRect(for: mbp, size: CGSize(width: 300, height: 32))
        #expect(visible.minX == 606)
        #expect(visible.minY == 950)
    }

    @Test func pointerAgainstTheTopEdgeIsInsideTheNotch() {
        // Quartz y 0 (the top row) arrives from NSEvent.mouseLocation as exactly frame.maxY.
        let m = NotchGeometry.metrics(for: mbp)
        let zone = NotchGeometry.hoverZone(for: mbp, metrics: m, slop: 0)
        let edge = CGPoint(x: mbp.frame.midX, y: mbp.frame.maxY)
        #expect(!zone.contains(edge))
        #expect(zone.contains(NotchGeometry.hitPoint(edge, in: mbp.frame)))
        let below = CGPoint(x: mbp.frame.midX, y: mbp.frame.maxY - 10)
        #expect(NotchGeometry.hitPoint(below, in: mbp.frame) == below)
        // The top edge of a display without a notch arms its thin strip too.
        let strip = CGRect(x: external.frame.midX - 50, y: external.frame.maxY - 4, width: 100, height: 4)
        #expect(strip.contains(NotchGeometry.hitPoint(CGPoint(x: external.frame.midX, y: external.frame.maxY), in: external.frame)))
    }
}

@Suite struct NowPlayingTests {
    func np(_ source: MediaSourceKind, _ title: String, playing: Bool, at t: Double, elapsed: Double? = nil) -> NowPlaying {
        NowPlaying(source: source, title: title, artist: "A", isPlaying: playing, duration: 200, elapsed: elapsed, timestamp: t0.addingTimeInterval(t))
    }

    @Test func positionExtrapolatesWhilePlaying() {
        let p = np(.spotify, "x", playing: true, at: 0, elapsed: 10)
        #expect(p.position(at: t0.addingTimeInterval(5)) == 15)
        #expect(p.position(at: t0.addingTimeInterval(500)) == 200)
        let paused = np(.spotify, "x", playing: false, at: 0, elapsed: 10)
        #expect(paused.position(at: t0.addingTimeInterval(5)) == 10)
        #expect(paused.fraction(at: t0) == 0.05)
    }

    @Test func playingBeatsPaused() {
        var a = MediaArbiter()
        a.update(np(.spotify, "old", playing: false, at: 10))
        a.update(np(.appleMusic, "new", playing: true, at: 0))
        #expect(a.current(now: t0.addingTimeInterval(11))?.title == "new")
    }

    @Test func mostRecentWinsAmongEquals() {
        var a = MediaArbiter()
        a.update(np(.spotify, "s", playing: true, at: 0))
        a.update(np(.browser, "b", playing: true, at: 5))
        #expect(a.current(now: t0.addingTimeInterval(6))?.title == "b")
    }

    @Test func staleSnapshotsAreForgotten() {
        var a = MediaArbiter(pausedTimeout: 60)
        a.update(np(.spotify, "s", playing: false, at: 0))
        #expect(a.current(now: t0.addingTimeInterval(59)) != nil)
        #expect(a.current(now: t0.addingTimeInterval(61)) == nil)
    }

    @Test func directIntegrationEnrichesSystemBridge() {
        var a = MediaArbiter()
        var sys = np(.system, "Song", playing: true, at: 5, elapsed: 30)
        sys.artworkData = Data([1, 2, 3])
        a.update(sys)
        var spot = np(.spotify, "Song", playing: true, at: 1)
        spot.artworkURL = URL(string: "https://i.scdn.co/image/x")
        spot.duration = nil
        a.update(spot)
        let cur = a.current(now: t0.addingTimeInterval(6))!
        #expect(cur.source == .spotify)
        #expect(cur.artworkURL != nil)
        #expect(cur.artworkData == Data([1, 2, 3]))
        #expect(cur.duration == 200)
    }

    @Test func newerDirectSnapshotStillGetsSystemArtwork() {
        var a = MediaArbiter()
        var sys = np(.system, "Song", playing: true, at: 0, elapsed: 30)
        sys.artworkData = Data([9])
        a.update(sys)
        var spot = np(.spotify, "Song", playing: true, at: 5)
        spot.duration = nil
        a.update(spot)
        let cur = a.current(now: t0.addingTimeInterval(6))!
        #expect(cur.source == .spotify)
        #expect(cur.artworkData == Data([9]))
        #expect(cur.elapsed == 30)
        #expect(cur.duration == 200)
    }

    @Test func disabledSourcesAndClear() {
        var a = MediaArbiter(disabled: [.browser])
        a.update(np(.browser, "b", playing: true, at: 0))
        #expect(a.current(now: t0) == nil)
        a.disabled = []
        #expect(a.current(now: t0)?.title == "b")
        a.clear(.browser)
        #expect(a.current(now: t0) == nil)
    }

    @Test func pausedPlayerHasADeadline() {
        var a = MediaArbiter(pausedTimeout: 60)
        #expect(a.nextDeadline(now: t0) == nil)
        a.update(np(.spotify, "s", playing: true, at: 0))
        // Playing never times out.
        #expect(a.nextDeadline(now: t0) == nil)
        a.update(np(.spotify, "s", playing: false, at: 10))
        a.update(np(.browser, "b", playing: false, at: 5))
        #expect(a.nextDeadline(now: t0.addingTimeInterval(10)) == t0.addingTimeInterval(65))
        #expect(a.nextDeadline(now: t0.addingTimeInterval(65)) == t0.addingTimeInterval(70))
        #expect(a.nextDeadline(now: t0.addingTimeInterval(70)) == nil)
    }

    @Test func expireForgetsTimedOutPausedPlayers() {
        var a = MediaArbiter(pausedTimeout: 60)
        a.update(np(.spotify, "s", playing: false, at: 0))
        a.update(np(.appleMusic, "m", playing: true, at: 0))
        let early = a.expire(now: t0.addingTimeInterval(59))
        #expect(!early)
        #expect(a.current(now: t0.addingTimeInterval(59))?.title == "m")
        let due = a.expire(now: t0.addingTimeInterval(60))
        #expect(due)
        #expect(a.snapshots[.spotify] == nil)
        #expect(a.snapshots[.appleMusic] != nil)
        let playing = a.expire(now: t0.addingTimeInterval(600))
        #expect(!playing)
        // Forgetting the only player is reported, so the app takes the track down at once.
        var b = MediaArbiter(pausedTimeout: 60)
        b.update(np(.spotify, "s", playing: false, at: 0))
        let forgotten = b.expire(now: t0.addingTimeInterval(60))
        #expect(forgotten)
        #expect(b.current(now: t0.addingTimeInterval(60)) == nil)
    }

    @Test func switchedOffPlayerIsHiddenWhicheverPathReportsIt() {
        func bridge(_ bundle: String, _ title: String) -> NowPlaying {
            var s = np(.system, title, playing: true, at: 0)
            s.bundleID = bundle
            return s
        }
        #expect(MediaSourceKind.player(bundleID: "com.apple.Music") == .appleMusic)
        #expect(MediaSourceKind.player(bundleID: "com.spotify.client") == .spotify)
        #expect(MediaSourceKind.player(bundleID: "com.apple.podcasts") == nil)
        #expect(MediaSourceKind.player(bundleID: nil) == nil)

        var a = MediaArbiter(disabled: [.appleMusic])
        a.update(bridge("com.apple.Music", "Song"))
        #expect(a.current(now: t0) == nil)
        a.update(np(.appleMusic, "Song", playing: true, at: 0))
        #expect(a.current(now: t0) == nil)
        a.disabled = [.spotify]
        #expect(a.current(now: t0)?.title == "Song")

        var s = MediaArbiter(disabled: [.spotify])
        s.update(bridge("com.spotify.client", "Track"))
        #expect(s.current(now: t0) == nil)
        // Other apps still come through the bridge.
        s.update(bridge("com.apple.podcasts", "Episode"))
        #expect(s.current(now: t0)?.title == "Episode")

        // Music and Spotify aren't "Other apps": switching that off leaves them alone, and hides the rest.
        var o = MediaArbiter(disabled: [.system])
        o.update(bridge("com.apple.Music", "Song"))
        #expect(o.current(now: t0)?.title == "Song")
        o.update(bridge("com.apple.podcasts", "Episode"))
        #expect(o.current(now: t0) == nil)
        // A browser keeps its own switch.
        var w = MediaArbiter(disabled: [.browser])
        var video = np(.browser, "Video", playing: true, at: 0)
        video.bundleID = "com.apple.Safari"
        w.update(video)
        #expect(w.current(now: t0) == nil)
        #expect(MediaArbiter.setting(for: video) == .browser)
    }
}

@Suite struct ClipboardHistoryTests {
    @Test func loweringTheLimitTrimsAtOnce() {
        var h = ClipboardHistory(limit: 5)
        for (i, text) in ["one", "two", "three", "four", "five"].enumerated() {
            h.add(text, types: [], sourceBundleID: nil, now: t0.addingTimeInterval(Double(i)))
        }
        let oldest = h.entries.last!.id
        h.togglePin(id: oldest)
        h.limit = 2
        // The newest unpinned entry and the pinned one stay; nothing waits for the next copy.
        #expect(h.entries.map(\.text) == ["five", "one"])
        h.limit = 10
        #expect(h.entries.count == 2)
        // The smallest limit is 1, and a pinned entry outlasts newer unpinned ones.
        h.limit = 0
        #expect(h.limit == 1)
        #expect(h.entries.map(\.text) == ["one"])
    }
}

@Suite struct PresenterTests {
    func playing() -> NowPlaying {
        NowPlaying(source: .appleMusic, title: "Song", isPlaying: true, timestamp: t0)
    }

    @Test func idleWhenNothingHappens() {
        #expect(Presenter.present(PresenterInputs(now: t0, center: ActivityCenter())) == .idle)
    }

    @Test func precedence() throws {
        var c = ActivityCenter(sneakDuration: 1)
        try c.apply(ActivitySpec(id: "n", title: "normal"), now: t0)
        let later = t0.addingTimeInterval(2)
        // Playing media beats a normal activity...
        if case .compact(.nowPlaying) = Presenter.present(PresenterInputs(now: later, center: c, nowPlaying: playing())) {} else {
            Issue.record("expected now playing")
        }
        // ...but not a high-priority one.
        try c.apply(ActivitySpec(id: "h", title: "high", priority: .high, sneak: false), now: later)
        guard case .compact(.activity(let a, let others)) = Presenter.present(PresenterInputs(now: later, center: c, nowPlaying: playing())) else {
            Issue.record("expected activity"); return
        }
        #expect(a.id == "h")
        #expect(others == 1)
        // HUD beats everything except expanded.
        c.showHUD(.volume, value: 0.5, now: later)
        if case .hud = Presenter.present(PresenterInputs(now: later, center: c, nowPlaying: playing())) {} else { Issue.record("expected hud") }
        #expect(Presenter.present(PresenterInputs(now: later, center: c, isExpanded: true)) == .expanded)
    }

    @Test func pausedMediaHiddenUnlessEnabled() {
        var np = playing()
        np.isPlaying = false
        #expect(Presenter.present(PresenterInputs(now: t0, center: ActivityCenter(), nowPlaying: np)) == .idle)
        #expect(Presenter.present(PresenterInputs(now: t0, center: ActivityCenter(), nowPlaying: np, showPausedMedia: true)) == .compact(.nowPlaying(np)))
    }

    @Test func fullscreenSuppression() throws {
        var c = ActivityCenter()
        try c.apply(ActivitySpec(id: "n", title: "normal"), now: t0)
        #expect(Presenter.present(PresenterInputs(now: t0, center: c, nowPlaying: playing(), isSuppressed: true)) == .hidden)
        try c.apply(ActivitySpec(id: "crit", title: "Battery 5%", priority: .critical), now: t0)
        if case .sneak(let a) = Presenter.present(PresenterInputs(now: t0, center: c, isSuppressed: true)) {
            #expect(a.id == "crit")
        } else { Issue.record("critical should break through fullscreen") }
        c.showHUD(.brightness, value: 0.3, now: t0)
        if case .hud = Presenter.present(PresenterInputs(now: t0, center: c, isSuppressed: true)) {} else { Issue.record("HUD shows in fullscreen") }
    }

    @Test func batteryEventShowsBriefly() {
        let ev = BatteryEvent(kind: .pluggedIn, state: BatteryState(level: 50, isCharging: true, isPluggedIn: true), until: t0.addingTimeInterval(3))
        #expect(Presenter.present(PresenterInputs(now: t0, center: ActivityCenter(), batteryEvent: ev)) == .compact(.battery(ev)))
        #expect(Presenter.present(PresenterInputs(now: t0.addingTimeInterval(4), center: ActivityCenter(), batteryEvent: ev)) == .idle)
    }
}

@Suite struct BatteryTests {
    func s(_ level: Int, plugged: Bool, charging: Bool? = nil) -> BatteryState {
        BatteryState(level: level, isCharging: charging ?? plugged, isPluggedIn: plugged)
    }

    @Test func detectsTransitions() {
        var d = BatteryEventDetector()
        #expect(d.ingest(s(50, plugged: false), now: t0) == nil) // first reading: no event
        #expect(d.ingest(s(50, plugged: true), now: t0)?.kind == .pluggedIn)
        #expect(d.ingest(s(51, plugged: true), now: t0) == nil)
        #expect(d.ingest(s(51, plugged: false), now: t0)?.kind == .unplugged)
        #expect(d.ingest(s(21, plugged: false), now: t0) == nil)
        #expect(d.ingest(s(20, plugged: false), now: t0)?.kind == .low)
        #expect(d.ingest(s(19, plugged: false), now: t0) == nil)
        #expect(d.ingest(s(10, plugged: false), now: t0)?.kind == .critical)
        #expect(d.ingest(s(99, plugged: true), now: t0)?.kind == .pluggedIn)
        #expect(d.ingest(s(100, plugged: true, charging: false), now: t0)?.kind == .full)
    }

    @Test func clampsLevel() {
        #expect(BatteryState(level: 140, isCharging: false, isPluggedIn: false).level == 100)
        #expect(BatteryState(level: -3, isCharging: false, isPluggedIn: false).level == 0)
    }
}

@Suite struct FormatTests {
    @Test func clock() {
        #expect(Format.clock(0) == "0:00")
        #expect(Format.clock(59.9) == "0:59")
        #expect(Format.clock(61) == "1:01")
        #expect(Format.clock(3725) == "1:02:05")
        #expect(Format.clock(-4) == "0:00")
        #expect(Format.clock(.infinity) == "--:--")
    }

    @Test func relative() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let now = Date(timeIntervalSince1970: 1_800_000_000) // 2027-01-15 08:00 UTC
        #expect(Format.relative(to: now.addingTimeInterval(10), now: now, calendar: cal) == "now")
        #expect(Format.relative(to: now.addingTimeInterval(299), now: now, calendar: cal) == "in 5 min")
        #expect(Format.relative(to: now.addingTimeInterval(3600), now: now, calendar: cal) == "in 1 h")
        #expect(Format.relative(to: now.addingTimeInterval(4800), now: now, calendar: cal) == "in 1 h 20 min")
        #expect(Format.relative(to: now.addingTimeInterval(86400), now: now, calendar: cal) == "tomorrow")
        #expect(Format.relative(to: now.addingTimeInterval(3 * 86400), now: now, calendar: cal) == "in 3 days")
        #expect(Format.relative(to: now.addingTimeInterval(-600), now: now, calendar: cal) == "10 min ago")
    }

    @Test func battery() {
        #expect(Format.batteryTime(minutes: 65) == "1:05")
        #expect(Format.batteryTime(minutes: nil) == nil)
        #expect(Format.batteryTime(minutes: -1) == nil)
    }

    @Test func bytes() {
        #expect(Format.bytes(512) == "512 B")
        #expect(Format.bytes(1_200_000) == "1.2 MB")
        #expect(Format.bytes(35_000_000_000) == "35 GB")
    }

    @Test func colors() {
        #expect(RGBA.parse("#FF0000") == RGBA(r: 1, g: 0, b: 0))
        #expect(RGBA.parse("0f0") == RGBA(r: 0, g: 1, b: 0))
        #expect(RGBA.parse("#00000080")?.a ?? 0 > 0.5)
        #expect(RGBA.parse("Green") == RGBA.named["green"])
        #expect(RGBA.parse("grey") == RGBA.named["gray"])
        #expect(RGBA.parse("#12345") == nil)
        #expect(RGBA.parse("zzzzzz") == nil)
    }

    @Test func icons() throws {
        #expect(ActivityIcon(string: "sf:hammer.fill") == .symbol("hammer.fill"))
        #expect(ActivityIcon(string: "hammer.fill") == .symbol("hammer.fill"))
        #expect(ActivityIcon(string: "🚀") == .emoji("🚀"))
        #expect(ActivityIcon(string: "emoji:🔥") == .emoji("🔥"))
        #expect(ActivityIcon(string: "app:com.spotify.client") == .app(bundleID: "com.spotify.client"))
        #expect(ActivityIcon(string: "https://x.com/a.png") == .url(URL(string: "https://x.com/a.png")!))
        #expect(ActivityIcon(string: "/tmp/a.png") == .file("/tmp/a.png"))
        #expect(ActivityIcon(string: "file:///tmp/a.png") == .file("/tmp/a.png"))
        #expect(ActivityIcon(string: "  ") == nil)
        // Round-trips through JSON as a plain string.
        let data = try JSONEncoder().encode(ActivityIcon.app(bundleID: "com.apple.Music"))
        #expect(String(decoding: data, as: UTF8.self) == "\"app:com.apple.Music\"")
        #expect(try JSONDecoder().decode(ActivityIcon.self, from: data) == .app(bundleID: "com.apple.Music"))
    }

    @Test func priorityDecoding() throws {
        let d = JSONDecoder()
        #expect(try d.decode(ActivityPriority.self, from: Data("\"urgent\"".utf8)) == .critical)
        #expect(try d.decode(ActivityPriority.self, from: Data("2".utf8)) == .high)
        #expect(try d.decode(ActivityPriority.self, from: Data("99".utf8)) == .critical)
        #expect(throws: (any Error).self) { try d.decode(ActivityPriority.self, from: Data("\"meh\"".utf8)) }
    }
}

@Suite struct HoverIntentTests {
    @Test func dwellOpensAfterDelay() {
        var h = HoverIntent(openDelay: 0.2, closeDelay: 0.3)
        let p = CGPoint(x: 10, y: 10)
        #expect(h.sample(point: p, now: t0, inTrigger: true, inExpanded: true, isOpen: false) == .none)
        #expect(h.sample(point: p, now: t0.addingTimeInterval(0.1), inTrigger: true, inExpanded: true, isOpen: false) == .none)
        #expect(h.sample(point: p, now: t0.addingTimeInterval(0.25), inTrigger: true, inExpanded: true, isOpen: false) == .open)
    }

    @Test func restingPointerOpensViaTick() {
        var h = HoverIntent(openDelay: 0.2)
        _ = h.sample(point: .zero, now: t0, inTrigger: true, inExpanded: true, isOpen: false)
        #expect(h.tick(now: t0.addingTimeInterval(0.1), isOpen: false) == .none)
        #expect(h.tick(now: t0.addingTimeInterval(0.3), isOpen: false) == .open)
    }

    @Test func fastPassThroughDoesNotOpen() {
        var h = HoverIntent(openDelay: 0.05, maxOpenSpeed: 500)
        var decisions: [HoverIntent.Decision] = []
        // Sweep across the top of the screen at ~3000 pt/s.
        for i in 0..<10 {
            let t = t0.addingTimeInterval(Double(i) * 0.01)
            decisions.append(h.sample(point: CGPoint(x: Double(i) * 30, y: 0), now: t, inTrigger: true, inExpanded: true, isOpen: false))
        }
        #expect(!decisions.contains(.open))
    }

    @Test func leavingTheZoneResetsDwell() {
        var h = HoverIntent(openDelay: 0.2)
        _ = h.sample(point: .zero, now: t0, inTrigger: true, inExpanded: true, isOpen: false)
        _ = h.sample(point: .zero, now: t0.addingTimeInterval(0.1), inTrigger: false, inExpanded: false, isOpen: false)
        #expect(h.enteredAt == nil)
        #expect(h.sample(point: .zero, now: t0.addingTimeInterval(0.25), inTrigger: true, inExpanded: true, isOpen: false) == .none)
    }

    @Test func closesAfterGracePeriodOutside() {
        var h = HoverIntent(closeDelay: 0.3)
        #expect(h.sample(point: .zero, now: t0, inTrigger: false, inExpanded: false, isOpen: true) == .none)
        // Coming back inside cancels the pending close.
        #expect(h.sample(point: .zero, now: t0.addingTimeInterval(0.2), inTrigger: false, inExpanded: true, isOpen: true) == .none)
        #expect(h.sample(point: .zero, now: t0.addingTimeInterval(0.4), inTrigger: false, inExpanded: false, isOpen: true) == .none)
        #expect(h.sample(point: .zero, now: t0.addingTimeInterval(0.8), inTrigger: false, inExpanded: false, isOpen: true) == .close)
        #expect(h.tick(now: t0.addingTimeInterval(0.9), isOpen: true) == .close)
    }
}

@Suite struct BrightnessFilterTests {
    @Test func keyPressShows() {
        var f = BrightnessChangeFilter()
        let first = f.ingest(0.5, now: t0)                              // establishes the baseline
        let step = f.ingest(0.5625, now: t0.addingTimeInterval(5))      // one key step (1/16)
        let more = f.ingest(0.625, now: t0.addingTimeInterval(5.2))     // continued burst
        #expect(!first)
        #expect(step)
        #expect(more)
    }

    @Test func animatedStepShowsOnceThresholdReached() {
        var f = BrightnessChangeFilter()
        _ = f.ingest(0.5, now: t0)
        var shown: [Bool] = []
        for i in 1...6 { shown.append(f.ingest(0.5 + Double(i) * 0.0104, now: t0.addingTimeInterval(10 + Double(i) * 0.03))) }
        #expect(shown.first == false)
        #expect(shown.last == true)
    }

    @Test func slowAutoBrightnessDriftIsIgnored() {
        var f = BrightnessChangeFilter()
        var any = false
        for i in 0..<40 { any = f.ingest(0.5 + Double(i) * 0.004, now: t0.addingTimeInterval(Double(i) * 1.5)) || any }
        #expect(!any)
    }

    @Test func duplicateValuesIgnored() {
        var f = BrightnessChangeFilter()
        _ = f.ingest(0.5, now: t0)
        let dup = f.ingest(0.5, now: t0.addingTimeInterval(1))
        #expect(!dup)
    }
}

@Suite struct SmartIconTests {
    func sym(_ title: String, _ sub: String? = nil, _ source: String? = nil) -> String? {
        SmartIcon.suggest(title: title, subtitle: sub, source: source)?.symbol
    }

    @Test func picksByKeyword() {
        #expect(sym("Release build") == "hammer.fill")
        #expect(sym("Deploying web", "step 3/5") == "paperplane.fill")
        #expect(sym("pytest", "412 passed") == "testtube.2")
        #expect(sym("Uber", "Driver arriving in 3 min") == "car.fill")
        #expect(sym("Flight BA117", "Boarding at gate 22") == "airplane")
        #expect(sym("Standup in 5 min") == "video.fill")
        #expect(sym("Review pull request #42") == "arrow.triangle.pull")
        #expect(sym("Downloading", "ubuntu.iso") == "arrow.down.circle.fill")
        #expect(sym("Something", nil, "claude-code") == nil)  // "claude-code" is one token
        #expect(sym("Claude · islet") == "sparkles")
        #expect(sym("Quarterly numbers") == nil)
    }

    @Test func stemming() {
        #expect(sym("Uploads finished") == "icloud.and.arrow.up.fill")
        #expect(sym("Compiling sources") == "hammer.fill")
    }

    @Test func activityPrecedence() throws {
        var c = ActivityCenter()
        let running = try c.apply(ActivitySpec(id: "a", title: "Deploying web", state: .running), now: t0)
        #expect(running.icon(smart: true) == .symbol("paperplane.fill"))
        #expect(running.tintName(smart: true) == "blue")
        #expect(running.icon(smart: false) == .symbol("gearshape.2.fill"))
        // Outcome beats topic once finished.
        let failed = try c.apply(ActivitySpec(id: "a", state: .failure), now: t0)
        #expect(failed.icon(smart: true) == .symbol("xmark.octagon.fill"))
        #expect(failed.tintName(smart: true) == "red")
        // Explicit values always win.
        let explicit = try c.apply(ActivitySpec(id: "b", title: "Deploy", icon: .emoji("🚀"), tint: "pink"), now: t0)
        #expect(explicit.icon(smart: true) == .emoji("🚀"))
        #expect(explicit.tintName(smart: true) == "pink")
    }

    @Test func allSuggestedTintsParse() {
        for rule in SmartIcon.rules { #expect(RGBA.parse(rule.tint) != nil, "bad tint \(rule.tint)") }
    }
}
