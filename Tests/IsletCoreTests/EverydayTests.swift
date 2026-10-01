import Foundation
import Testing
@testable import IsletCore

private func decode(_ json: String) -> IsletSettings { IsletSettings.decodeLenient(Data(json.utf8)) }

@Suite struct HUDDefaultTests {
    @Test func newConfigsLeaveVolumeAndBrightnessToMacOS() {
        let s = IsletSettings()
        #expect(!s.hudEnabled && !s.brightnessHUDEnabled)
        #expect(s.hudOverlap.isEmpty)
        // The output card, which macOS doesn't draw, keeps its own switch and stays on.
        #expect(s.outputChangeCard)
        // A file written by Islet says what it chose, and keeps it.
        let saved = IsletSettings.decodeLenient(try! JSONEncoder().encode(s))
        #expect(!saved.hudEnabled && !saved.brightnessHUDEnabled)
    }

    @Test func anOlderFileWithoutTheKeysKeepsThemOn() {
        let old = decode(#"{"theme": "black"}"#)
        #expect(old.hudEnabled && old.brightnessHUDEnabled)
        let chose = decode(#"{"hudEnabled": true, "brightnessHUDEnabled": false}"#)
        #expect(chose.hudEnabled && !chose.brightnessHUDEnabled)
        // Nothing to go on (an empty file): the new defaults.
        #expect(!decode("{}").hudEnabled)
    }

    @Test func overlapIsWhatShowsTwice() {
        var s = IsletSettings()
        s.hudEnabled = true
        #expect(s.hudOverlap == [.volume])
        s.brightnessHUDEnabled = true
        #expect(s.hudOverlap == [.volume, .brightness])
        // Replacing the system's display: only Islet's shows.
        s.replaceSystemHUD = true
        #expect(s.hudOverlap.isEmpty)
    }
}

@Suite struct NotificationPeekTests {
    let n = MirroredNotification(appName: "Slack", bundleID: "com.tinyspeck.slackmacgap", title: "#eng", body: "Deploy is green")

    @Test func mirroredNotificationsStayBesideTheNotchByDefault() {
        #expect(!IsletSettings().notificationPeek)
        #expect(n.activity(rule: nil, peek: IsletSettings().notificationPeek).sneak == false)
        #expect(n.activity(rule: nil, peek: true).sneak == true)
        // The same activity either way, only the peek differs.
        #expect(n.activity(rule: nil, peek: true).id == n.activity(rule: nil).id)
    }
}

@Suite struct ScriptEnvironmentTests {
    @Test func onlyTheVariablesScriptsNeed() {
        let parent = ["HOME": "/Users/a", "USER": "a", "PATH": "/usr/bin:/bin", "LANG": "en_GB.UTF-8",
                      "ISLET_TOKEN": "x", "OPENAI_API_KEY": "y", "DYLD_INSERT_LIBRARIES": "/tmp/z", "SSH_AUTH_SOCK": "/tmp/s"]
        let env = ScriptPlugins.environment(parent: parent, extra: ["XBARRefresh": "1"])
        #expect(Set(env.keys) == ["HOME", "USER", "PATH", "LANG", "ISLET", "XBARDarkMode", "SWIFTBAR", "XBARRefresh"])
        #expect(env["PATH"] == "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin")
        #expect(env["HOME"] == "/Users/a")
    }

    @Test func aPathAlreadyWithHomebrewIsNotRepeated() {
        let env = ScriptPlugins.environment(parent: ["PATH": "/opt/homebrew/bin:/usr/bin"])
        #expect(env["PATH"] == "/opt/homebrew/bin:/usr/local/bin:/usr/bin")
        #expect(ScriptPlugins.environment(parent: [:])["PATH"] == "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin")
    }
}

@Suite struct CancelledEventTests {
    let start = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func cancelledEventsAreLeftOutAndNeverRemind() {
        let kept = AgendaItem(id: "a", title: "Standup", start: start, end: start.addingTimeInterval(900))
        let gone = AgendaItem(id: "b", title: "Review", start: start, end: start.addingTimeInterval(900),
                              meetingURL: URL(string: "https://zoom.us/j/1"), isCancelled: true)
        #expect(Agenda.visible([kept, gone], hiding: []).map(\.id) == ["a"])
        #expect(gone.isDeclined)
        #expect(!MeetingReminders.isEligible(gone, options: MeetingReminderOptions(lead: 600)))
        // Hidden calendars still hide.
        var other = kept
        other.calendarID = "work"
        #expect(Agenda.visible([other], hiding: ["work"]).isEmpty)
    }

    @Test func olderSavedEventsDecodeAsNotCancelled() throws {
        let json = #"{"id":"a","title":"x","start":0,"end":60}"#
        let item = try JSONDecoder().decode(AgendaItem.self, from: Data(json.utf8))
        #expect(!item.isCancelled && !item.isDeclined)
    }

    @Test func anEventWithoutAnIdentifierKeepsTheSameIdEachRefresh() {
        let a = Agenda.eventID(eventIdentifier: nil, calendarItemIdentifier: "item-1", start: start)
        #expect(a == Agenda.eventID(eventIdentifier: nil, calendarItemIdentifier: "item-1", start: start))
        #expect(a == Agenda.eventID(eventIdentifier: "", calendarItemIdentifier: "item-1", start: start))
        // Each occurrence of a repeating event is its own.
        #expect(a != Agenda.eventID(eventIdentifier: nil, calendarItemIdentifier: "item-1", start: start.addingTimeInterval(86_400)))
        #expect(Agenda.eventID(eventIdentifier: "EK1", calendarItemIdentifier: "item-1", start: start) == "EK1")
    }
}

@Suite struct CallSettlingTests {
    func at(_ s: TimeInterval) -> Date { t0.addingTimeInterval(s) }

    @Test func aMomentOnTheMicrophoneIsNotACall() {
        var d = CallDetector()
        #expect(d.update(micUsers: ["us.zoom.xos"], cameraOn: false, now: at(0)).isEmpty)
        #expect(d.nextDeadline(now: at(0)) == at(CallDetector.settle))
        #expect(d.update(micUsers: ["us.zoom.xos"], cameraOn: false, now: at(2)).isEmpty)
        // Let go before it settled: nothing ever showed, nothing to end.
        #expect(d.update(micUsers: [], cameraOn: false, now: at(2.5)).isEmpty)
        #expect(d.nextDeadline(now: at(3)) == nil)
    }

    @Test func aCallAppHeldForFourSecondsIsACall() {
        var d = CallDetector()
        _ = d.update(micUsers: ["us.zoom.xos"], cameraOn: false, now: at(0))
        let changes = d.update(micUsers: ["us.zoom.xos"], cameraOn: false, now: at(4))
        guard case .started(let s) = changes.first else { Issue.record("expected a call: \(changes)"); return }
        #expect(s.priority == .high && s.sneak == true && s.startedAt == at(0))
        #expect(d.nextDeadline(now: at(4)) == nil)
    }

    @Test func aBrowserIsQuietUntilTheCameraOrAMinute() {
        var d = CallDetector()
        _ = d.update(micUsers: ["com.google.Chrome.helper"], cameraOn: false, now: at(0))
        let quiet = d.update(micUsers: ["com.google.Chrome.helper"], cameraOn: false, now: at(4))
        guard case .started(let q) = quiet.first else { Issue.record("expected the quiet pill: \(quiet)"); return }
        #expect(q.title == "Chrome" && q.subtitle == "Microphone in use")
        #expect(q.priority == .low && q.sneak == false)
        #expect(d.nextDeadline(now: at(4)) == at(CallDetector.quietFor))
        // A minute on, it is a call, and says so once.
        let call = d.update(micUsers: ["com.google.Chrome.helper"], cameraOn: false, now: at(60))
        guard case .updated(let c) = call.first else { Issue.record("expected the call: \(call)"); return }
        #expect(c.title == "Call in Chrome" && c.priority == .high && c.sneak == true && c.startedAt == at(0))
        let later = d.update(micUsers: ["com.google.Chrome.helper"], cameraOn: false, now: at(70))
        if case .updated(let l) = later.first { #expect(l.sneak == false) } else { Issue.record("expected an update") }
    }

    @Test func theCameraMakesAQuietPillACallAtOnce() {
        var d = CallDetector()
        _ = d.update(micUsers: ["com.tinyspeck.slackmacgap"], cameraOn: false, now: at(0))
        _ = d.update(micUsers: ["com.tinyspeck.slackmacgap"], cameraOn: false, now: at(5))
        let video = d.update(micUsers: ["com.tinyspeck.slackmacgap"], cameraOn: true, now: at(8))
        guard case .updated(let v) = video.first else { Issue.record("expected the call: \(video)"); return }
        #expect(v.subtitle == "Video call" && v.priority == .high)
        // The camera going off doesn't make it quiet again.
        let audio = d.update(micUsers: ["com.tinyspeck.slackmacgap"], cameraOn: false, now: at(9))
        if case .updated(let a) = audio.first { #expect(a.priority == .high && a.subtitle == "Call") } else { Issue.record("expected an update") }
    }

    @Test func aDismissedPillStaysAwayUntilTheMicrophoneIsReleased() {
        var d = CallDetector()
        _ = d.update(micUsers: ["us.zoom.xos"], cameraOn: false, now: at(0))
        _ = d.update(micUsers: ["us.zoom.xos"], cameraOn: false, now: at(4))
        let dismissed = d.dismiss(activityID: CallDetector.activityID("us.zoom.xos"))
        let other = d.dismiss(activityID: "something-else")
        #expect(dismissed && !other)
        #expect(d.update(micUsers: ["us.zoom.xos"], cameraOn: true, now: at(30)).isEmpty)
        #expect(d.nextDeadline(now: at(30)) == nil)
        // Still on the call for meeting reminders.
        #expect(d.ongoing.map(\.bundleID) == ["us.zoom.xos"])
        // Released, then a new call: it shows again.
        #expect(d.update(micUsers: [], cameraOn: false, now: at(40)).isEmpty)
        _ = d.update(micUsers: ["us.zoom.xos"], cameraOn: false, now: at(50))
        if case .started = d.update(micUsers: ["us.zoom.xos"], cameraOn: false, now: at(54)).first {} else { Issue.record("expected a new call") }
    }

    @Test func aMutedAppShowsNothingAndItsPillGoes() {
        var d = CallDetector()
        let muted: Set<String> = ["com.hnc.Discord"]
        _ = d.update(micUsers: ["com.hnc.Discord"], cameraOn: false, now: at(0), muted: muted)
        #expect(d.update(micUsers: ["com.hnc.Discord"], cameraOn: true, now: at(10), muted: muted).isEmpty)
        #expect(d.nextDeadline(now: at(10)) == nil)
        // Muted while on show: it goes.
        _ = d.update(micUsers: ["us.zoom.xos"], cameraOn: false, now: at(0))
        _ = d.update(micUsers: ["us.zoom.xos"], cameraOn: false, now: at(4))
        #expect(d.update(micUsers: ["us.zoom.xos"], cameraOn: false, now: at(5), muted: ["us.zoom.xos"])
            == [.ended(id: CallDetector.activityID("us.zoom.xos"))])
    }
}

@Suite struct MirroredSourceTests {
    @Test func eachAppHasItsOwnSource() {
        #expect(MenuBarLiveActivities.source(for: "Uber") == "live-activity:uber")
        #expect(MenuBarLiveActivities.source(for: "Uber Eats") == "live-activity:uber-eats")
        #expect(MenuBarLiveActivities.source(for: "Live Activity") == "live-activity:live-activity")
        #expect(MenuBarLiveActivities.source(for: "  ") == "live-activity")
        #expect(MenuBarLiveActivities.isMirroredSource("live-activity:uber"))
        #expect(MenuBarLiveActivities.isMirroredSource("live-activity"))
        #expect(!MenuBarLiveActivities.isMirroredSource("live-activityx"))
        #expect(!MenuBarLiveActivities.isMirroredSource("live"))
    }

    @Test func mutingOneAppLeavesTheOthers() {
        var s = IsletSettings()
        s.mutedSources = ["live-activity:uber"]
        #expect(s.isMuted(source: "live-activity:uber"))
        #expect(!s.isMuted(source: "live-activity:deliveroo"))
        // Muted in an older version, when every mirrored activity shared one source.
        s.mutedSources = ["live-activity"]
        #expect(s.isMuted(source: "live-activity:deliveroo"))
        #expect(!s.isMuted(source: "github-actions"))
    }

    @Test func mutedSourcesReadAsNames() {
        let names = ["com.tinyspeck.slackmacgap": "Slack"]
        func name(_ s: String) -> String { MutedSources.displayName(s) { names[$0] } }
        #expect(name("live-activity:uber-eats") == "Uber Eats (Live Activity)")
        #expect(name("live-activity") == "Live Activities")
        #expect(name("com.tinyspeck.slackmacgap") == "Slack")
        #expect(name("com.example.gone") == "com.example.gone")
        #expect(name("github-actions") == "github-actions")
    }

    @Test func scriptsCantUseAnAppsMirroredSource() throws {
        #expect(throws: URLCommand.ParseError.invalid("source", "live-activity:uber")) {
            try URLCommand.parse(URL(string: "islet://notify?title=x&source=live-activity:uber")!)
        }
    }
}

@Suite struct MirrorTrackerTests {
    let uber = MirroredLiveActivity(key: "k1", appName: "Uber", detail: "4 min")
    func at(_ s: TimeInterval) -> Date { t0.addingTimeInterval(s) }

    @Test func aDismissedItemStaysHiddenUntilItLeavesTheMenuBar() {
        var t = MirrorTracker()
        #expect(t.sync([uber], now: at(0)).show == [uber])
        t.dismiss(key: "k1")
        var moved = uber
        moved.detail = "2 min"
        #expect(t.sync([moved], now: at(60)).show.isEmpty)
        // Gone from the menu bar, then back (a new ride): it shows.
        #expect(t.sync([], now: at(120)).gone == ["k1"])
        #expect(t.sync([uber], now: at(180)).show == [uber])
    }

    @Test func anItemWhoseTextStopsChangingDims() {
        var t = MirrorTracker()
        _ = t.sync([uber], now: at(0))
        #expect(t.staleAt(key: "k1") == at(MirrorTracker.staleAfter))
        // The same text again doesn't move it on.
        _ = t.sync([uber], now: at(600))
        #expect(t.staleAt(key: "k1") == at(MirrorTracker.staleAfter))
        var moved = uber
        moved.detail = "3 min"
        _ = t.sync([moved], now: at(900))
        #expect(t.staleAt(key: "k1") == at(900 + MirrorTracker.staleAfter))
        #expect(t.staleAt(key: "other") == nil)
    }

    @Test func theSpecCarriesTheStaleMoment() throws {
        let spec = MenuBarLiveActivities.activity(for: uber, look: nil, isNew: false, staleAt: at(1800))
        #expect(spec.staleAt == at(1800))
        var c = ActivityCenter()
        let a = try c.apply(spec, now: at(0))
        #expect(!a.isStale(at: at(1799)) && a.isStale(at: at(1800)))
    }
}

@Suite struct BrowserListTests {
    @Test func diaAndOtherBrowsersCountAsBrowsers() {
        #expect(Browsers.browser(for: "company.thebrowser.dia")?.name == "Dia")
        #expect(Browsers.browser(for: "com.google.Chrome.beta.helper")?.name == "Chrome Beta")
        #expect(Browsers.browser(for: "com.google.Chrome.helper.renderer")?.name == "Chrome")
        #expect(Browsers.browser(for: "com.spotify.client") == nil)
        // A call held in Dia is a browser call, and so is one in Safari's GPU process.
        #expect(CallDetector.classify("company.thebrowser.dia.helper")?.app == CallDetector.App(name: "Dia", isBrowser: true))
        #expect(CallDetector.classify("com.apple.WebKit.GPU")?.app.name == "Safari")
        #expect(ClipboardHistory.browsers.contains("company.thebrowser.dia"))
    }
}

@Suite struct MediaFilterTests {
    func at(_ s: TimeInterval) -> Date { t0.addingTimeInterval(s) }
    func clip(_ bundle: String = "com.example.chat", artist: String? = nil, playing: Bool = true, at t: TimeInterval) -> NowPlaying {
        NowPlaying(source: .system, bundleID: bundle, title: "Voice message", artist: artist, isPlaying: playing, duration: 4, elapsed: 0, timestamp: at(t))
    }

    @Test func aHiddenAppNeverShows() {
        var m = MediaArbiter()
        m.hidden = ["com.apple.TV"]
        m.updateFromBridge(NowPlaying(source: .system, bundleID: "com.apple.TV", title: "Trailer", artist: "Apple", isPlaying: true, timestamp: at(0)))
        #expect(m.current(now: at(1)) == nil)
        #expect(m.available(now: at(1)).isEmpty)
        // Spotify, through its own integration, still shows.
        m.update(NowPlaying(source: .spotify, bundleID: "com.spotify.client", title: "Song", artist: "Band", isPlaying: true, timestamp: at(0)))
        #expect(m.current(now: at(1))?.title == "Song")
    }

    @Test func aBareClipFromAnUnknownAppWaitsBeforeShowing() {
        var m = MediaArbiter()
        m.updateFromBridge(clip(at: 0))
        #expect(m.current(now: at(1)) == nil)
        #expect(m.nextDeadline(now: at(1)) == at(MediaArbiter.settle))
        // Still playing after 3 seconds: it shows, and stays once paused.
        #expect(m.current(now: at(3))?.title == "Voice message")
        m.updateFromBridge(clip(playing: false, at: 5))
        #expect(m.current(now: at(6))?.title == "Voice message")
    }

    @Test func aShortClipNeverTakesOver() {
        var m = MediaArbiter()
        m.update(NowPlaying(source: .appleMusic, bundleID: "com.apple.Music", title: "Album track", artist: "Band", isPlaying: false, timestamp: at(-10)))
        m.updateFromBridge(clip(at: 0))
        m.updateFromBridge(clip(playing: false, at: 2))
        #expect(m.current(now: at(4))?.title == "Album track")
    }

    @Test func knownPlayersAndClipsWithDetailsShowAtOnce() {
        var m = MediaArbiter()
        m.updateFromBridge(clip("com.apple.podcasts", artist: "A podcast", at: 0))
        #expect(m.current(now: at(0.5))?.title == "Voice message")
        var b = MediaArbiter()
        b.updateFromBridge(NowPlaying(source: .browser, bundleID: "com.google.Chrome", title: "A video", isPlaying: true, timestamp: at(0)))
        #expect(b.current(now: at(0.5))?.title == "A video")
        #expect(MediaArbiter.needsSettling(clip(at: 0)))
        #expect(!MediaArbiter.needsSettling(NowPlaying(source: .system, bundleID: "com.apple.Music", title: "x", isPlaying: true, timestamp: at(0))))
    }
}

@Suite struct HelperRestartTests {
    @Test func fiveQuickExitsGiveUpUntilAskedAgain() {
        var r = HelperRestarts()
        var delays: [TimeInterval?] = []
        for _ in 1...6 { delays.append(r.exited(ranFor: 1)) }
        #expect(delays == [1, 4, 9, 16, 25, nil])
        #expect(r.gaveUp)
        r.reset()
        let first = r.exited(ranFor: 1)
        #expect(!r.gaveUp && first == 1)
    }

    @Test func aHelperThatRanAWhileStartsAfresh() {
        var r = HelperRestarts()
        for _ in 1...4 { _ = r.exited(ranFor: 1) }
        let next = r.exited(ranFor: HelperRestarts.healthyRun + 1)
        #expect(next == 1)
        #expect(!r.gaveUp)
    }
}

@Suite struct SwipeUnderHUDTests {
    @Test func aSidewaysSwipeOverAVolumeHUDChangesTrack() {
        var center = ActivityCenter()
        center.showHUD(.volume, value: 0.4, now: t0)
        let np = NowPlaying(source: .spotify, title: "Song", artist: "Band", isPlaying: true, timestamp: t0)
        var inputs = PresenterInputs(now: t0, center: center, nowPlaying: np)
        if case .hud = Presenter.present(inputs) {} else { Issue.record("expected the HUD") }
        inputs.ignoresHUD = true
        let under = Presenter.present(inputs)
        #expect(under == .compact(.nowPlaying(np)))
        let surface = GestureSurface.from(under, homeShowsMedia: false)
        #expect(GestureMap.action(for: .left, on: surface!, settings: IsletSettings()) == .nextTrack)
        // Nothing under it: a sideways swipe does nothing, down still opens.
        let bare = Presenter.present(PresenterInputs(now: t0, center: center))
        if case .hud = bare {} else { Issue.record("expected the HUD") }
        var empty = PresenterInputs(now: t0, center: center)
        empty.ignoresHUD = true
        #expect(Presenter.present(empty) == .idle)
        #expect(GestureMap.action(for: .down, on: .closed, settings: IsletSettings()) == .expand)
    }
}

@Suite struct IslandHoldTests {
    @Test func onlyNothingHoldingLetsItClose() {
        #expect(IslandHold().allowsClose)
        let holds: [IslandHold] = [IslandHold(pinned: true), IslandHold(draggingIn: true), IslandHold(draggingOut: true),
                                   IslandHold(control: true), IslandHold(menu: true), IslandHold(typing: true)]
        for h in holds { #expect(!h.allowsClose, "\(h)") }
    }

    @Test func closingOnTheNotchBlocksReopeningThere() {
        #expect(HoverIntent.blocksReopen(wasOpen: true, isOpen: false, pointerOnNotch: true))
        // Closed because the pointer left: it isn't on the notch.
        #expect(!HoverIntent.blocksReopen(wasOpen: true, isOpen: false, pointerOnNotch: false))
        #expect(!HoverIntent.blocksReopen(wasOpen: false, isOpen: false, pointerOnNotch: true))
        #expect(!HoverIntent.blocksReopen(wasOpen: true, isOpen: true, pointerOnNotch: true))
    }
}

@Suite struct PeekPointerGuardTests {
    /// Feeds the guard in order; what it said each time.
    func run(_ g: inout PeekPointerGuard, _ steps: [(String?, Bool)]) -> [Bool] {
        steps.map { g.update(peek: $0.0, pointerInBody: $0.1) }
    }

    @Test func aPeekUnderThePointerIsIgnoredUntilThePointerLeaves() {
        var g = PeekPointerGuard()
        // Under the pointer, still there, left the body, back again: only then does it count.
        let said = run(&g, [("sneak-a", true), ("sneak-a", true), ("sneak-a", false), ("sneak-a", true)])
        #expect(said == [false, false, true, true])
    }

    @Test func aPeekAwayFromThePointerCountsAtOnce() {
        var g = PeekPointerGuard()
        // A new peek arriving under a pointer already resting there is ignored again.
        let said = run(&g, [("song-peek", false), ("song-peek", true), ("sneak-b", true), (nil, false)])
        #expect(said == [true, true, false, false])
        #expect(g.ignoring == nil)
    }
}

@Suite struct LoopTests {
    @Test func loopsHoldStillForLessMotionLowPowerAndStaleContent() {
        #expect(!IslandLoops.holdStill(reduceMotion: false, animationOff: false, lowPower: false))
        #expect(IslandLoops.holdStill(reduceMotion: false, animationOff: false, lowPower: true))
        #expect(IslandLoops.holdStill(reduceMotion: true, animationOff: false, lowPower: false))
        #expect(IslandLoops.holdStill(reduceMotion: false, animationOff: true, lowPower: false))
        #expect(IslandLoops.holdStill(reduceMotion: false, animationOff: false, lowPower: false, stale: true))
    }
}

@Suite struct ApprovalBackToTerminalTests {
    @Test func theAgentsStatusSaysWhereToAnswer() {
        let claude = ApprovalRequest(provider: .claude, hook: .permissionRequest, sessionID: "ABC-123-def-456-xyz", toolName: "Bash")
        let expired = claude.statusUpdate(backToTerminal: .expired)
        #expect(expired.id == "claude-abc-123-def")
        #expect(expired.subtitle == "Answer in the terminal")
        #expect(expired.state == .waiting && expired.sneak == false)
        // It only changes the agent's own activity: with none, nothing new appears.
        #expect(expired.title == nil)
        var center = ActivityCenter()
        #expect(throws: ActivityError.self) { try center.apply(expired, now: t0) }
        let cursor = ApprovalRequest(provider: .cursor, hook: .beforeShellExecution, sessionID: "conv-9", toolName: "shell")
        #expect(cursor.statusUpdate(backToTerminal: .jumpFailed).id == "cursor-conv-9")
        #expect(cursor.statusUpdate(backToTerminal: .jumpFailed).subtitle?.hasPrefix("Couldn't bring the terminal forward") == true)
    }
}
