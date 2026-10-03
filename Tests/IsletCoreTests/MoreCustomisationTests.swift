import Foundation
import Testing
@testable import IsletCore

private func decode(_ json: String) -> IsletSettings { IsletSettings.decodeLenient(Data(json.utf8)) }

private func writtenKeys(_ s: IsletSettings) throws -> [String: Any] {
    try JSONSerialization.jsonObject(with: JSONEncoder().encode(s)) as? [String: Any] ?? [:]
}

private func song(playing: Bool, elapsed: Double? = 60, duration: Double? = 240, rate: Double = 1, at t: Double = 0) -> NowPlaying {
    NowPlaying(source: .spotify, title: "Midnight City", artist: "M83", isPlaying: playing, duration: duration,
               elapsed: elapsed, playbackRate: rate, timestamp: t0.addingTimeInterval(t))
}

@Suite struct MusicColourTests {
    @Test func artworkByDefaultWithTheRingOff() {
        #expect(IsletSettings().musicColour == .artwork)
        #expect(IsletSettings().songProgressRing == false)
        #expect(decode(#"{"songProgressRing": true}"#).songProgressRing)
        #expect(decode(#"{"musicColour": "accent"}"#).musicColour == .accent)
        #expect(decode(#"{"musicColour": "plaid"}"#).musicColour == .artwork)
    }

    @Test func visualiserColourCarriesOver() throws {
        // The indicator's own colour becomes the colour of all the music.
        let old = decode(#"{"visualiserColour": "white"}"#)
        #expect(old.musicColour == .white)
        #expect(decode(#"{"visualiserColour": "accent"}"#).musicColour == .accent)
        // A value that can't be read leaves the default.
        #expect(decode(#"{"visualiserColour": "neon"}"#).musicColour == .artwork)
        #expect(decode(#"{"visualiserColour": 3}"#).musicColour == .artwork)
        // The new key wins, and the old one isn't written back.
        #expect(decode(#"{"visualiserColour": "white", "musicColour": "accent"}"#).musicColour == .accent)
        // A new key that can't be read doesn't count: the old choice still carries over.
        #expect(decode(#"{"visualiserColour": "white", "musicColour": "neon"}"#).musicColour == .white)
        let keys = try writtenKeys(old)
        #expect(keys["visualiserColour"] == nil)
        #expect(keys["musicColour"] as? String == "white")
        #expect(IsletSettings.decodeLenient(try JSONEncoder().encode(old)) == old)
    }
}

@Suite struct SongProgressTests {
    @Test func fillsFromWhereTheSongIsToItsEnd() {
        let p = SongProgress(song(playing: true), now: t0.addingTimeInterval(20))
        #expect(p?.fraction == 80.0 / 240)
        #expect(p?.remaining == 160)
    }

    @Test func pausedHoldsStill() {
        let p = SongProgress(song(playing: false), now: t0.addingTimeInterval(20))
        #expect(p?.fraction == 0.25)
        #expect(p?.remaining == nil)
    }

    @Test func followsThePlayersRate() {
        let p = SongProgress(song(playing: true, rate: 2), now: t0)
        #expect(p?.remaining == 90)
        // A rate of nothing doesn't move.
        #expect(SongProgress(song(playing: true, rate: 0), now: t0)?.remaining == nil)
    }

    @Test func nothingToFillWithoutALength() {
        #expect(SongProgress(song(playing: true, duration: nil), now: t0) == nil)
        #expect(SongProgress(song(playing: true, duration: 0), now: t0) == nil)
        #expect(SongProgress(song(playing: true, duration: .infinity), now: t0) == nil)
        #expect(SongProgress(song(playing: true, elapsed: nil), now: t0) == nil)
    }

    @Test func staysInsideTheRing() {
        // A report from long ago, or past the end, is full and has nothing left.
        let late = SongProgress(song(playing: true), now: t0.addingTimeInterval(10_000))
        #expect(late?.fraction == 1)
        #expect(late?.remaining == 0)
        #expect(SongProgress(song(playing: false, elapsed: -5), now: t0)?.fraction == 0)
    }

    /// A length that isn't a number counts as no length, as it does for the ring. The
    /// AppleScript players and `POST /v1/media` read it straight from the player, and an
    /// infinite date reaches `MediaArbiter`'s deadlines, arming the app's one timer for never.
    @Test func aTrackWhoseLengthIsNotANumberHasNoEnd() {
        for duration in [Double.infinity, -.infinity, .nan] {
            let s = song(playing: true, duration: duration)
            #expect(s.endsAt == nil, "\(duration)")
            #expect(s.fraction(at: t0) == nil, "\(duration)")
        }
        #expect(song(playing: true, elapsed: .infinity).endsAt == nil)
        #expect(song(playing: true, rate: .infinity).endsAt == nil)
        // A real length still ends where it should.
        #expect(song(playing: true).endsAt == t0.addingTimeInterval(180))
    }
}

@Suite struct SongPeekLengthTests {
    @Test func peekLastsTheGivenTime() {
        // AppModel builds the peek with "New activities stay open for".
        var peek = SongPeek(settle: 0.6, duration: IsletSettings().alertDuration)
        peek.ingest(song(playing: true), now: t0)
        var next = song(playing: true)
        next.title = "Wait"
        peek.ingest(next, now: t0.addingTimeInterval(1))
        let first = peek.advance(now: t0.addingTimeInterval(1.6), context: .init())
        #expect(first)
        #expect(peek.current(now: t0.addingTimeInterval(1.6 + 2.4)) != nil)
        #expect(peek.current(now: t0.addingTimeInterval(1.6 + 2.5)) == nil)
        peek.duration = 5
        var third = song(playing: true)
        third.title = "Outro"
        peek.ingest(third, now: t0.addingTimeInterval(10))
        let second = peek.advance(now: t0.addingTimeInterval(10.6), context: .init())
        #expect(second)
        #expect(peek.current(now: t0.addingTimeInterval(15.5)) != nil)
        #expect(peek.current(now: t0.addingTimeInterval(15.6)) == nil)
    }
}

@Suite struct HoverPeekTests {
    private var clickToOpen: IsletSettings {
        var s = IsletSettings()
        s.hoverToOpen = false
        return s
    }

    @Test func onByDefaultForClickToOpen() {
        #expect(IsletSettings().peekOnHover)
        #expect(decode(#"{"peekOnHover": false}"#).peekOnHover == false)
        let np = song(playing: true)
        #expect(Presenter.hoverPeek(np, hovering: true, settings: clickToOpen) == np)
        // Paused music is still what's playing.
        #expect(Presenter.hoverPeek(song(playing: false), hovering: true, settings: clickToOpen) != nil)
    }

    @Test func onlyWhileHoveringAndOnlyWhenHoverDoesNotOpen() {
        let np = song(playing: true)
        #expect(Presenter.hoverPeek(np, hovering: false, settings: clickToOpen) == nil)
        // Hovering opens the island, so there is nothing to peek at.
        #expect(Presenter.hoverPeek(np, hovering: true, settings: IsletSettings()) == nil)
        var off = clickToOpen
        off.peekOnHover = false
        #expect(Presenter.hoverPeek(np, hovering: true, settings: off) == nil)
        var noMedia = clickToOpen
        noMedia.mediaEnabled = false
        #expect(Presenter.hoverPeek(np, hovering: true, settings: noMedia) == nil)
        #expect(Presenter.hoverPeek(nil, hovering: true, settings: clickToOpen) == nil)
    }

    @Test func showsAsASongPeekBelowAHUD() {
        let np = song(playing: true)
        var center = ActivityCenter()
        let peek = Presenter.present(PresenterInputs(now: t0, center: center, nowPlaying: np, songPeek: np))
        #expect(peek == .songPeek(np))
        center.showHUD(.volume, value: 0.5, now: t0)
        let hud = Presenter.present(PresenterInputs(now: t0, center: center, nowPlaying: np, songPeek: np))
        if case .hud = hud {} else { Issue.record("expected the HUD, got \(hud)") }
    }
}

@Suite struct HUDChoiceTests {
    @Test func compactByDefaultWithMacOSShowingVolumeAndBrightness() {
        let s = IsletSettings()
        #expect(s.hudStyle == .compact)
        // macOS draws its own volume and brightness display, so Islet's start off.
        #expect(!s.showsHUD(.volume) && !s.showsHUD(.brightness))
        #expect(s.showsHUD(.keyboardBrightness) && s.showsHUD(.microphone))
        #expect(s.showsAnyHUD)
        #expect(decode(#"{"hudStyle": "detailed"}"#).hudStyle == .detailed)
        #expect(decode(#"{"hudStyle": "huge"}"#).hudStyle == .compact)
    }

    @Test func eachKindHasItsOwnSwitch() {
        let s = decode(#"{"keyboardHUDEnabled": false, "microphoneHUDEnabled": false}"#)
        #expect(s.showsHUD(.volume))
        #expect(s.showsHUD(.brightness))
        #expect(!s.showsHUD(.keyboardBrightness))
        #expect(!s.showsHUD(.microphone))
        let none = decode(#"{"hudEnabled": false, "brightnessHUDEnabled": false, "keyboardHUDEnabled": false, "microphoneHUDEnabled": false}"#)
        #expect(!none.showsAnyHUD)
    }
}

@Suite struct AnimationSpeedTests {
    @Test func normalByDefaultAndScalesEveryMove() {
        #expect(IsletSettings().animationSpeed == .normal)
        #expect(AnimationSpeed.normal.multiplier == 1)
        #expect(AnimationSpeed.relaxed.multiplier > 1)
        #expect(AnimationSpeed.quick.multiplier < 1)
        #expect(AnimationSpeed.allCases == [.relaxed, .normal, .quick])
        #expect(decode(#"{"animationSpeed": "quick"}"#).animationSpeed == .quick)
        #expect(decode(#"{"animationSpeed": "ludicrous"}"#).animationSpeed == .normal)
    }
}

@Suite struct AppColourTests {
    @Test func anyColourIsKept() {
        let s = decode(##"{"appRules": [{"bundleID": "a.b", "tint": "#2F7CF6"}, {"bundleID": "c.d", "tint": "teal"}]}"##)
        #expect(s.rule(for: "a.b")?.tint == "#2F7CF6")
        #expect(s.rule(for: "c.d")?.tint == "teal")
    }

    @Test func somethingThatIsNotAColourMeansItsOwn() {
        let s = decode(##"{"appRules": [{"bundleID": "a.b", "tint": "sparkly"}, {"bundleID": "c.d", "tint": "#12"}]}"##)
        #expect(s.rule(for: "a.b")?.tint == nil)
        #expect(s.rule(for: "c.d")?.tint == nil)
        // The rule itself stays.
        #expect(s.appRules.map(\.bundleID) == ["a.b", "c.d"])
    }
}

@Suite struct FullscreenBehaviourTests {
    @Test func hidesEverythingByDefault() {
        #expect(IsletSettings().fullscreenBehaviour == .hide)
        #expect(decode(#"{"fullscreenBehaviour": "hideMusic"}"#).fullscreenBehaviour == .hideMusic)
        #expect(decode(#"{"fullscreenBehaviour": "sometimes"}"#).fullscreenBehaviour == .hide)
    }

    @Test func hideInFullscreenMigrates() throws {
        // false kept the island over full screen apps: "Keep showing".
        let kept = decode(#"{"hideInFullscreen": false}"#)
        #expect(kept.fullscreenBehaviour == .show)
        #expect(decode(#"{"hideInFullscreen": true}"#).fullscreenBehaviour == .hide)
        #expect(decode(#"{"hideInFullscreen": "no"}"#).fullscreenBehaviour == .hide)
        // The new key wins, and a new key that can't be read doesn't count.
        #expect(decode(#"{"hideInFullscreen": false, "fullscreenBehaviour": "hideMusic"}"#).fullscreenBehaviour == .hideMusic)
        #expect(decode(#"{"hideInFullscreen": false, "fullscreenBehaviour": 7}"#).fullscreenBehaviour == .show)
        let keys = try writtenKeys(kept)
        #expect(keys["hideInFullscreen"] == nil)
        #expect(keys["fullscreenBehaviour"] as? String == "show")
        #expect(IsletSettings.decodeLenient(try JSONEncoder().encode(kept)) == kept)
    }

    @Test func onlyAppliesInFullScreenAndAnAppRuleKeepsTheIsland() {
        var s = IsletSettings()
        s.fullscreenBehaviour = .hideMusic
        #expect(s.fullscreenEffect(isFullscreen: false, frontApp: nil) == .show)
        #expect(s.fullscreenEffect(isFullscreen: true, frontApp: "com.apple.TV") == .hideMusic)
        s.appRules = [AppRule(bundleID: "us.zoom.xos", showInFullscreen: true)]
        #expect(s.fullscreenEffect(isFullscreen: true, frontApp: "us.zoom.xos") == .show)
        s.fullscreenBehaviour = .hide
        #expect(s.fullscreenEffect(isFullscreen: true, frontApp: "com.apple.TV") == .hide)
    }
}

@Suite struct NotchlessStyleTests {
    private let external = ScreenDescriptor(id: 2, name: "External", frame: CGRect(x: 0, y: 0, width: 1920, height: 1080),
                                            safeAreaTop: 0, menuBarHeight: 24)
    private let macBook = ScreenDescriptor(id: 1, name: "Built-in", frame: CGRect(x: 0, y: 0, width: 1512, height: 982),
                                           safeAreaTop: 32, auxiliaryLeftWidth: 663.5, auxiliaryRightWidth: 663.5, menuBarHeight: 33)

    @Test func floatingPillByDefault() {
        #expect(IsletSettings().notchlessStyle == .pill)
        #expect(decode(#"{"notchlessStyle": "hover"}"#).notchlessStyle == .hover)
        #expect(decode(#"{"notchlessStyle": "ghost"}"#).notchlessStyle == .pill)
    }

    @Test func showOnNonNotchDisplaysMigrates() throws {
        let hidden = decode(#"{"showOnNonNotchDisplays": false}"#)
        #expect(hidden.notchlessStyle == .hidden)
        #expect(decode(#"{"showOnNonNotchDisplays": true}"#).notchlessStyle == .pill)
        #expect(decode(#"{"showOnNonNotchDisplays": false, "notchlessStyle": "notch"}"#).notchlessStyle == .notch)
        let keys = try writtenKeys(hidden)
        #expect(keys["showOnNonNotchDisplays"] == nil)
        #expect(keys["notchlessStyle"] as? String == "hidden")
        #expect(IsletSettings.decodeLenient(try JSONEncoder().encode(hidden)) == hidden)
    }

    @Test func onlyDisplaysWithoutANotchFloat() {
        #expect(NotchGeometry.metrics(for: external, notchless: .pill).floats)
        #expect(NotchGeometry.metrics(for: external, notchless: .hover).floats)
        #expect(!NotchGeometry.metrics(for: external, notchless: .notch).floats)
        // A MacBook's notch is hardware: the island never floats there.
        #expect(!NotchGeometry.metrics(for: macBook, notchless: .pill).floats)
        // The pill stays inside the menu bar row: the same height as the notch it replaces.
        #expect(NotchGeometry.metrics(for: external, notchless: .pill).notch.height == 24)
    }

    @Test func onlyOnHoverWaitsForThePointer() {
        let np = NowPlaying(source: .spotify, title: "Midnight City", isPlaying: true, timestamp: t0)
        var center = ActivityCenter()
        let normal = try! center.apply(ActivitySpec(id: "a", source: "s", title: "Build"), now: t0)
        let critical = try! center.apply(ActivitySpec(id: "b", source: "s", title: "Battery", priority: .critical), now: t0)
        #expect(Presenter.untilHover(.compact(.nowPlaying(np))) == .idle)
        #expect(Presenter.untilHover(.songPeek(np)) == .idle)
        #expect(Presenter.untilHover(.sneak(normal)) == .idle)
        // What you caused, what's urgent and the open island still show.
        #expect(Presenter.untilHover(.sneak(critical)) == .sneak(critical))
        let hud = HUDEvent(kind: .volume, value: 0.5, until: t0)
        #expect(Presenter.untilHover(.hud(hud)) == .hud(hud))
        #expect(Presenter.untilHover(.expanded) == .expanded)
        #expect(Presenter.untilHover(.hidden) == .hidden)
    }
}

@Suite struct OutlineAndGlassTests {
    @Test func bothOffByDefault() {
        #expect(!IsletSettings().outline)
        #expect(!IsletSettings().glassOnNotchless)
        let s = decode(#"{"outline": true, "glassOnNotchless": true}"#)
        #expect(s.outline && s.glassOnNotchless)
        #expect(!decode(#"{"outline": "yes"}"#).outline)
    }
}

@Suite struct ReverseSwipeTests {
    @Test func leftIsForwardUnlessReversed() {
        var s = IsletSettings()
        #expect(!s.reverseSideSwipes)
        #expect(GestureMap.action(for: .left, on: .compactMedia, settings: s) == .nextTrack)
        #expect(GestureMap.action(for: .right, on: .compactActivity, settings: s) == .cycle(forward: false))
        s.reverseSideSwipes = true
        #expect(GestureMap.action(for: .left, on: .compactMedia, settings: s) == .previousTrack)
        #expect(GestureMap.action(for: .right, on: .compactMedia, settings: s) == .nextTrack)
        #expect(GestureMap.action(for: .right, on: .compactActivity, settings: s) == .cycle(forward: true))
        s.swipeMediaAction = .seek
        #expect(GestureMap.action(for: .right, on: .expanded(media: true), settings: s) == .seek(MediaSeek.swipeInterval))
        // Up and down don't change.
        #expect(GestureMap.action(for: .down, on: .closed, settings: s) == .expand)
        #expect(decode(#"{"reverseSideSwipes": true}"#).reverseSideSwipes)
    }
}

@Suite struct AppPriorityTests {
    @Test func anAppsPriorityRanksItsActivities() {
        var s = IsletSettings()
        let spec = ActivitySpec(id: "x", source: "us.zoom.xos", title: "Call", priority: .low)
        #expect(s.prioritised(spec).priority == .low)
        s.appRules = [AppRule(bundleID: "us.zoom.xos", priority: .high)]
        #expect(s.prioritised(spec).priority == .high)
        // Other apps, and specs without a source, keep their own.
        #expect(s.prioritised(ActivitySpec(id: "y", source: "com.other", title: "A", priority: .low)).priority == .low)
        #expect(s.prioritised(ActivitySpec(id: "z", title: "B")).priority == nil)
    }

    @Test func mirroredNotificationsFollowIt() {
        let n = MirroredNotification(appName: "Zoom", bundleID: "us.zoom.xos", title: "Meeting")
        #expect(n.activity(rule: nil).priority == .normal)
        #expect(n.activity(rule: AppRule(bundleID: "us.zoom.xos", priority: .critical)).priority == .critical)
        #expect(decode(#"{"appRules": [{"bundleID": "a.b", "priority": "high"}]}"#).rule(for: "a.b")?.priority == .high)
    }
}

@Suite struct ResetAppearanceTests {
    @Test func appearanceGoesBackAndTheRestStays() {
        var s = IsletSettings()
        s.theme = .graphite; s.glassLevel = 0.1; s.outline = true; s.glassOnNotchless = true
        s.accentColor = "#FF0000"; s.roundedFont = false; s.smartIcons = false
        s.sizePreset = .custom; s.expandedWidth = 800; s.expandedHeight = 300; s.wingWidth = 100; s.closedLayout = .wings
        s.animationStyle = .snappy; s.animationSpeed = .quick; s.bounceOnActivity = false; s.urgentGlow = false
        s.reduceMotion = true; s.hapticsMode = .off; s.alertDuration = 5; s.maxConcurrent = 1; s.bubblePlacement = .left
        s.artworkCornerRadius = 0; s.visualiserStyle = .wave; s.musicColour = .white; s.songProgressRing = true
        // Not appearance: a calibration, and other pages.
        s.notchWidthAdjust = 6; s.notchHeightAdjust = -2
        s.hotkey = "cmd+shift+i"; s.hoverToOpen = false; s.hudStyle = .detailed; s.notchlessStyle = .hover
        s.appRules = [AppRule(bundleID: "a.b", tint: "red")]

        let r = s.resettingAppearance()
        var expected = IsletSettings()
        expected.notchWidthAdjust = 6; expected.notchHeightAdjust = -2
        expected.hotkey = "cmd+shift+i"; expected.hoverToOpen = false; expected.hudStyle = .detailed; expected.notchlessStyle = .hover
        expected.appRules = [AppRule(bundleID: "a.b", tint: "red")]
        #expect(r == expected)
        // Nothing to reset on a fresh install.
        #expect(IsletSettings().resettingAppearance() == IsletSettings())
    }
}

@Suite struct NothingHangsLowerTests {
    @Test func theHoverResponseOnlyWidens() {
        // Resting on the closed island widens it a little; it never grows below the notch.
        let notch = CGSize(width: 185, height: 32)
        let grown = NotchGeometry.hoverGrown(notch)
        #expect(grown.height == notch.height)
        #expect(grown.width == notch.width + 2 * NotchGeometry.hoverGrow)
        #expect(NotchGeometry.hoverGrown(notch, by: 0) == notch)
        #expect(NotchGeometry.hoverGrown(notch, by: -4) == notch)
    }

    @Test func theBlackUnderTheStemIsShortByDefault() {
        let level = IsletSettings().glassLevel
        // Every size of open island, up to the tallest Settings allows.
        for height in [IsletSettings.expandedHeightRange.lowerBound, 200, 260, IsletSettings.expandedHeightRange.upperBound] {
            let body = CGFloat(height) - 32
            let depth = GlassMelt.depth(body: body, level: level)
            #expect(depth < 20, "a \(height) pt island melts \(depth) pt below the menu bar")
            #expect(GlassMelt.depth(body: body, level: 1) == GlassMelt.shortest)
            // Towards Black it reaches further, up to half the body.
            #expect(GlassMelt.depth(body: body, level: 0) == body / 2)
            var last = GlassMelt.depth(body: body, level: 0)
            for step in 1...10 {
                let next = GlassMelt.depth(body: body, level: Double(step) / 10)
                #expect(next <= last)
                last = next
            }
        }
        #expect(GlassMelt.depth(body: -10, level: 0) == GlassMelt.shortest)
        #expect(GlassMelt.depth(body: 168, level: .nan) == GlassMelt.shortest)
    }

    @Test func theSmokeNeverDropsBelowItsFloor() {
        for step in 0...10 {
            #expect(GlassMelt.smoke(level: Double(step) / 10) >= GlassMelt.smokeFloor)
        }
        #expect(GlassMelt.smoke(level: IsletSettings().glassLevel) == GlassMelt.standardSmoke)
        #expect(GlassMelt.smoke(level: 0) > 0.8)
        #expect(GlassMelt.smoke(level: 1) == GlassMelt.smokeFloor)
        #expect(GlassMelt.smoke(level: -3) == GlassMelt.smoke(level: 0))
        #expect(GlassMelt.smoke(level: .infinity) == GlassMelt.smokeFloor)
    }

    /// The whole slider does something: past the default, towards Glass, the smoke and the
    /// melt keep thinning, so the Glass end never looks the same as the default.
    @Test func everyPartOfTheGlassLevelChangesTheLook() {
        let body: CGFloat = 118
        var smoke = GlassMelt.smoke(level: 0)
        var depth = GlassMelt.depth(body: body, level: 0)
        for step in 1...10 {
            let level = Double(step) / 10
            let s = GlassMelt.smoke(level: level), d = GlassMelt.depth(body: body, level: level)
            #expect(s < smoke, "smoke at \(level)")
            #expect(d < depth, "melt at \(level)")
            smoke = s
            depth = d
        }
        let standard = IsletSettings().glassLevel
        #expect(GlassMelt.smoke(level: standard) - GlassMelt.smoke(level: 1) >= 0.1)
        #expect(GlassMelt.depth(body: body, level: standard) - GlassMelt.depth(body: body, level: 1) >= 4)
    }
}

@Suite struct AppRuleLeniencyTests {
    @Test func aMisspeltPriorityKeepsEveryRule() {
        let s = decode(##"{"appRules": [{"bundleID": "a.b", "tint": "#2F7CF6", "priority": "highest", "hideIsland": true},"## +
                       ##" {"bundleID": "c.d", "priority": "urgent", "muteNotifications": "yes"}]}"##)
        #expect(s.appRules.map(\.bundleID) == ["a.b", "c.d"])
        // Only the value that can't be read falls back to "its own".
        #expect(s.rule(for: "a.b")?.priority == nil)
        #expect(s.rule(for: "a.b")?.tint == "#2F7CF6")
        #expect(s.rule(for: "a.b")?.hideIsland == true)
        #expect(s.rule(for: "c.d")?.priority == .critical)
        #expect(s.rule(for: "c.d")?.muteNotifications == nil)
    }

    @Test func aRuleStillNeedsItsApp() {
        // Without a bundle id there is nothing to apply the rule to: the list falls back as before.
        #expect(decode(#"{"appRules": [{"tint": "red"}]}"#).appRules.isEmpty)
    }

    @Test func rulesRoundTrip() throws {
        let rule = AppRule(bundleID: "a.b", tint: "teal", hideIsland: true, showInFullscreen: true, muteNotifications: true, priority: .high)
        let data = try JSONEncoder().encode(rule)
        #expect(try JSONDecoder().decode(AppRule.self, from: data) == rule)
    }
}
