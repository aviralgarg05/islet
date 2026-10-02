import Foundation
import Testing
@testable import IsletCore

private func decode(_ json: String) -> IsletSettings { IsletSettings.decodeLenient(Data(json.utf8)) }

@Suite struct HUDDefaultTests {
    @Test func newConfigsLeaveVolumeAndBrightnessToMacOS() {
        let s = IsletSettings()
        #expect(!s.hudEnabled && !s.brightnessHUDEnabled)
        #expect(s.hudOverlap.isEmpty)
        // The output card keeps its own switch, on in a new setup.
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
        #expect(decode("{}").outputChangeCard)
    }

    @Test func theOutputCardFollowsAnOlderFilesVolumeHUD() {
        // The card used to come with the volume HUD: someone who switched that off gets no cards now.
        #expect(!decode(#"{"hudEnabled": false}"#).outputChangeCard)
        #expect(decode(#"{"hudEnabled": true}"#).outputChangeCard)
        #expect(decode(#"{"theme": "black"}"#).outputChangeCard)
        // Once the file has its own answer, that is the one.
        #expect(decode(#"{"hudEnabled": false, "outputChangeCard": true}"#).outputChangeCard)
        #expect(!decode(#"{"hudEnabled": true, "outputChangeCard": false}"#).outputChangeCard)
        var s = IsletSettings()
        s.hudEnabled = false
        s.outputChangeCard = true
        #expect(IsletSettings.decodeLenient(try! JSONEncoder().encode(s)).outputChangeCard)
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

    /// The note under the Replace switch names the display that shows twice.
    @Test func overlapNoteNamesTheDisplay() {
        var s = IsletSettings()
        #expect(s.hudOverlapNote == nil)
        s.hudEnabled = true
        #expect(s.hudOverlapNote?.hasPrefix("macOS shows its own volume display too") == true)
        s.brightnessHUDEnabled = true
        #expect(s.hudOverlapNote?.contains("volume and brightness displays") == true)
        s.hudEnabled = false
        #expect(s.hudOverlapNote?.contains("own brightness display") == true)
        s.replaceSystemHUD = true
        #expect(s.hudOverlapNote == nil)
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

    @Test func safarisAppRuleMutesACallHeldByItsGPUProcess() {
        // Safari's web calls hold the microphone through WebKit's GPU process; the Apps page
        // rule is Safari's own bundle id.
        var d = CallDetector()
        let muted: Set<String> = ["com.apple.Safari"]
        _ = d.update(micUsers: ["com.apple.WebKit.GPU"], cameraOn: false, now: at(0), muted: muted)
        #expect(d.update(micUsers: ["com.apple.WebKit.GPU"], cameraOn: true, now: at(10), muted: muted).isEmpty)
        // Not muted: Safari's call, under Safari's id.
        var e = CallDetector()
        _ = e.update(micUsers: ["com.apple.WebKit.GPU"], cameraOn: true, now: at(0))
        let call = e.update(micUsers: ["com.apple.WebKit.GPU"], cameraOn: true, now: at(4))
        guard case .started(let s) = call.first else { Issue.record("expected a call: \(call)"); return }
        #expect(s.source == "com.apple.Safari" && s.title == "Call in Safari")
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
        #expect(name("github-actions") == "Github actions (from a script)")
        #expect(name("my_backup-job") == "My backup job (from a script)")
        #expect(name(TimerEngine.source) == "Timers")
        #expect(name(MeetingReminders.source) == "Meeting reminders")
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
        #expect(CallDetector.classify("com.apple.WebKit.GPU")?.bundleID == "com.apple.Safari")
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

    @Test func thePointerIsFollowedOnlyWhileABodyIsIgnored() {
        var g = PeekPointerGuard()
        #expect(!g.followsPointer)
        g.update(peek: "sneak-a", pointerInBody: true)
        // Nothing near the pointer takes it, so only following it shows when it leaves.
        #expect(g.followsPointer)
        g.update(peek: "sneak-a", pointerInBody: false)
        #expect(!g.followsPointer)
        // A peek that ends while ignored lets go too.
        g.update(peek: "sneak-b", pointerInBody: true)
        g.update(peek: nil, pointerInBody: true)
        #expect(!g.followsPointer)
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
    @Test func loopsHoldStillForLessMotionAndStaleContent() {
        #expect(!IslandLoops.holdStill(reduceMotion: false, animationOff: false))
        #expect(IslandLoops.holdStill(reduceMotion: true, animationOff: false))
        #expect(IslandLoops.holdStill(reduceMotion: false, animationOff: true))
        #expect(IslandLoops.holdStill(reduceMotion: false, animationOff: false, stale: true))
    }

    /// Low Power Mode slows the loops down instead of stopping them: a still playing indicator
    /// looks broken.
    @Test func lowPowerModeHalvesTheFrameRate() {
        #expect(IslandLoops.frameRate(lowPower: false) == 30)
        #expect(IslandLoops.frameRate(lowPower: true) == 15)
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
        #expect(cursor.statusUpdate(backToTerminal: .jumpFailed).subtitle?.hasPrefix("Couldn’t bring the terminal forward") == true)
    }
}

@Suite struct FullscreenCoverageTests {
    // Two displays side by side, in the window list's coordinates (y down).
    let builtIn = DisplayArea(id: 1, bounds: CGRect(x: 0, y: 0, width: 1512, height: 982))
    let external = DisplayArea(id: 2, bounds: CGRect(x: 1512, y: 0, width: 2560, height: 1440))
    let menuLevel = 24
    func menuBar(on d: DisplayArea) -> ScreenWindow { ScreenWindow(bounds: CGRect(x: d.bounds.minX, y: 0, width: d.bounds.width, height: 33), layer: menuLevel, pid: 1) }

    @Test func aVideoInFullScreenStaysCoveredWhileYouWorkOnTheOtherDisplay() {
        // The editor on the external display is in front; the video app's window still fills the built-in one.
        let windows = [
            menuBar(on: external),
            ScreenWindow(bounds: CGRect(x: 1700, y: 100, width: 1200, height: 900), layer: 0, pid: 20),
            ScreenWindow(bounds: builtIn.bounds, layer: 0, pid: 10),
        ]
        #expect(FullscreenCoverage.coveringApps(windows: windows, displays: [builtIn, external], menuLevel: menuLevel,
                                                menuBarAutoHides: false) == [1: 10])
    }

    @Test func aDisplayWithItsMenuBarIsNeverCovered() {
        let windows = [menuBar(on: builtIn), ScreenWindow(bounds: builtIn.bounds, layer: 0, pid: 10)]
        #expect(FullscreenCoverage.coveringApps(windows: windows, displays: [builtIn], menuLevel: menuLevel, menuBarAutoHides: false).isEmpty)
    }

    @Test func aLargeWindowUnderAnAutoHiddenMenuBarDoesntCountUnlessConfirmed() {
        let windows = [ScreenWindow(bounds: builtIn.bounds, layer: 0, pid: 10)]
        let unconfirmed = FullscreenCoverage.coveringApps(windows: windows, displays: [builtIn], menuLevel: menuLevel, menuBarAutoHides: true)
        #expect(unconfirmed.isEmpty)
        let confirmed = FullscreenCoverage.coveringApps(windows: windows, displays: [builtIn], menuLevel: menuLevel, menuBarAutoHides: true) { _, _ in true }
        #expect(confirmed == [1: 10])
        // Accessibility saying "not in full screen" wins over the shape of the window.
        let zoomed = FullscreenCoverage.coveringApps(windows: windows, displays: [builtIn], menuLevel: menuLevel, menuBarAutoHides: false) { _, _ in false }
        #expect(zoomed.isEmpty)
    }

    @Test func anotherAppsWindowInFrontMeansItIsntFullScreen() {
        // Another app's smaller window in front of a large one: a desktop, not full screen.
        let windows = [ScreenWindow(bounds: CGRect(x: 100, y: 100, width: 600, height: 400), layer: 0, pid: 30),
                       ScreenWindow(bounds: builtIn.bounds, layer: 0, pid: 10)]
        #expect(FullscreenCoverage.coveringApps(windows: windows, displays: [builtIn], menuLevel: menuLevel, menuBarAutoHides: false).isEmpty)
        // The same app's own small windows in front (a browser's "Press Esc to exit full screen"
        // bubble at the top, its link preview at the bottom): still full screen.
        let video = [ScreenWindow(bounds: CGRect(x: 606, y: 40, width: 300, height: 44), layer: 0, pid: 10),
                     ScreenWindow(bounds: CGRect(x: 0, y: 950, width: 400, height: 24), layer: 0, pid: 10),
                     ScreenWindow(bounds: builtIn.bounds, layer: 0, pid: 10)]
        #expect(FullscreenCoverage.coveringApps(windows: video, displays: [builtIn], menuLevel: menuLevel, menuBarAutoHides: false) == [1: 10])
        // A window on the other display in front changes nothing here.
        let elsewhere = [ScreenWindow(bounds: CGRect(x: 1700, y: 100, width: 600, height: 400), layer: 0, pid: 30),
                         ScreenWindow(bounds: builtIn.bounds, layer: 0, pid: 10)]
        #expect(FullscreenCoverage.coveringApps(windows: elsewhere, displays: [builtIn, external], menuLevel: menuLevel,
                                                menuBarAutoHides: false) == [1: 10])
        // Content placed below the camera housing still counts.
        let notched = [ScreenWindow(bounds: CGRect(x: 0, y: 32, width: 1512, height: 950), layer: 0, pid: 10)]
        #expect(FullscreenCoverage.coveringApps(windows: notched, displays: [builtIn], menuLevel: menuLevel, menuBarAutoHides: false) == [1: 10])
        #expect(FullscreenCoverage.followUpLooks == [0.6, 2])
    }
}

@Suite struct SessionWorkTests {
    @Test func aGrantRestartsOnlyWhatUsesIt() {
        var s = IsletSettings()
        s.closedLayout = .wings
        s.mirrorMenuBarActivities = false
        // Nothing uses Accessibility: nothing to restart.
        #expect(!SessionWork.restartsOnTrustChange(wasTrusted: false, isTrusted: true, settings: s))
        s.mirrorMenuBarActivities = true
        #expect(SessionWork.restartsOnTrustChange(wasTrusted: false, isTrusted: true, settings: s))
        // Taken away: what used it stops.
        #expect(SessionWork.restartsOnTrustChange(wasTrusted: true, isTrusted: false, settings: s))
        // No change, or nothing known before: nothing to do.
        #expect(!SessionWork.restartsOnTrustChange(wasTrusted: true, isTrusted: true, settings: s))
        #expect(!SessionWork.restartsOnTrustChange(wasTrusted: nil, isTrusted: true, settings: s))
        #expect(SessionWork.runs(sessionActive: true) && !SessionWork.runs(sessionActive: false))
    }
}

@Suite struct DisplayPolicyTests {
    let lid = ScreenDescriptor(id: 1, name: "Built-in", frame: CGRect(x: 0, y: 0, width: 1512, height: 982), safeAreaTop: 32,
                               auxiliaryLeftWidth: 664, auxiliaryRightWidth: 664, isBuiltIn: true)
    let monitor = ScreenDescriptor(id: 7, name: "Studio Display", frame: CGRect(x: 1512, y: 0, width: 2560, height: 1440), safeAreaTop: 0)

    @Test func panelsAreRemadeWhenTheDisplaysChangeOrAfterWaking() {
        #expect(!DisplayPolicy.needsRebuild(current: [lid, monitor], wanted: [lid, monitor], force: false))
        // Lid closed: only the monitor.
        #expect(DisplayPolicy.needsRebuild(current: [lid, monitor], wanted: [monitor], force: false))
        // Back from sleep with a new id for the same monitor.
        var renamed = monitor
        renamed.id = 8
        #expect(DisplayPolicy.needsRebuild(current: [lid, monitor], wanted: [lid, renamed], force: false))
        // A resolution change.
        var scaled = lid
        scaled.frame.size = CGSize(width: 1352, height: 878)
        #expect(DisplayPolicy.needsRebuild(current: [lid], wanted: [scaled], force: false))
        // Notch areas that settled after waking.
        var settled = lid
        settled.auxiliaryLeftWidth = nil
        #expect(DisplayPolicy.needsRebuild(current: [settled], wanted: [lid], force: false))
        // After waking, always, then a second look that rebuilds only if something changed.
        #expect(DisplayPolicy.needsRebuild(current: [lid], wanted: [lid], force: true))
        #expect(DisplayPolicy.wakeLooks.map(\.force) == [true, false])
        #expect(DisplayPolicy.wakeLooks.map(\.delay) == [1, 2.5])
    }
}

@Suite struct BannerDeduperTests {
    func at(_ s: TimeInterval) -> Date { t0.addingTimeInterval(s) }

    @Test func eachBannerOnceAndRepeatsWithTheSameWordsToo() {
        var d = BannerDeduper<Int>()
        var said: [Bool] = []
        // Banner 1 seen twice while up, then a second banner with the same words (element 2).
        for (banner, t) in [(1, 0.0), (1, 5.0), (2, 20.0)] { said.append(d.isNew(banner, now: at(t))) }
        #expect(said == [true, false, true])
        // Seen again a minute later, when Notification Center redraws: still not news.
        let again = d.isNew(1, now: at(65))
        #expect(!again)
        // Remembered for ten minutes after it was last seen.
        let much = d.isNew(1, now: at(65 + BannerDeduper<Int>.keepFor))
        #expect(much)
    }

    @Test func aBannerReadBeforeItsWordsArriveIsReadAgain() {
        var d = BannerDeduper<Int>()
        // Notification Center has made banner 7 but not filled in its text yet.
        var text: [Int: String] = [:]
        #expect(d.news(in: [7], now: at(0)) { text[$0] }.isEmpty)
        // A moment later it has words: mirrored then, and once.
        text[7] = "Deploy is green"
        #expect(d.news(in: [7], now: at(0.3)) { text[$0] } == ["Deploy is green"])
        #expect(d.news(in: [7], now: at(0.6)) { text[$0] }.isEmpty)
    }

    @Test func anAlertLeftUpIsntMirroredAgain() {
        var d = BannerDeduper<Int>()
        let read: (Int) -> String? = { "banner \($0)" }
        #expect(d.news(in: [1], now: at(0), read: read) == ["banner 1"])
        // Still on screen at each look, long past the ten minutes.
        for minute in 1...30 {
            #expect(d.news(in: [1], now: at(Double(minute) * 60), read: read).isEmpty)
        }
        // Gone, then a new banner: news.
        #expect(d.news(in: [2], now: at(1900), read: read) == ["banner 2"])
    }

    @Test func bannersAlreadyUpWhenMirroringStartsArentNews() {
        var d = BannerDeduper<Int>()
        d.prime([3, 4], now: at(0))
        let old = d.isNew(3, now: at(1))
        let fresh = d.isNew(5, now: at(1))
        #expect(!old && fresh)
        // The same through `news`, which the mirror uses.
        var e = BannerDeduper<Int>()
        e.prime([3, 4], now: at(0))
        #expect(e.news(in: [3, 4, 6], now: at(1)) { "banner \($0)" } == ["banner 6"])
    }
}

@Suite struct ShelfCheckTests {
    @Test func aFileOnAMissingVolumeStaysAndOneGoneFromAMountedVolumeGoes() {
        let mounted: Set<String> = ["/Volumes/Backup", "/Volumes/Backup/a.pdf"]
        #expect(ShelfCheck.check(path: "/Volumes/Backup/a.pdf", exists: mounted.contains) == .present)
        #expect(ShelfCheck.check(path: "/Volumes/Backup/b.pdf", exists: mounted.contains) == .gone)
        #expect(ShelfCheck.check(path: "/Volumes/Share/c.pdf", exists: mounted.contains) == .unreachable)
        #expect(Shelf.isOnStartupDisk(ShelfItem(path: "/Users/a/c.pdf", addedAt: t0)))
        #expect(!Shelf.isOnStartupDisk(ShelfItem(path: "/Volumes/Share/c.pdf", addedAt: t0)))
    }

    @Test func aBookmarkMadeLaterIsKept() {
        var shelf = Shelf()
        shelf.add(paths: ["/Users/a/c.pdf"], now: t0)
        shelf.setBookmark(Data([1, 2]), forPath: "/Users/a/c.pdf")
        #expect(shelf.items.first?.bookmark == Data([1, 2]))
    }
}

@Suite struct NarrowDisplayWingTests {
    @Test func unmeasuredWingsAreIconOnlyOnANarrowDisplay() {
        func wing(_ width: CGFloat) -> CGFloat {
            MenuBarLayoutEngine.wingWidth(preference: .auto, notch: .zero, preferredWing: 58, occupancy: nil, hasMenuBar: true, displayWidth: width)
        }
        #expect(wing(1470) == MenuBarLayoutEngine.iconOnlyWing)
        #expect(wing(1512) == MenuBarLayoutEngine.unmeasuredWing)
        #expect(MenuBarLayoutEngine.wingWidth(preference: .auto, notch: .zero, preferredWing: 58, occupancy: nil, hasMenuBar: true)
            == MenuBarLayoutEngine.unmeasuredWing)
        // Always full width, or no menu bar: as before.
        #expect(MenuBarLayoutEngine.wingWidth(preference: .wings, notch: .zero, preferredWing: 58, occupancy: nil, hasMenuBar: true, displayWidth: 1300) == 58)
    }
}

@Suite struct MissedTimerTests {
    @Test func aTimerMissedWhileAsleepLeavesAQuietNote() throws {
        var engine = TimerEngine()
        let t = try engine.start(seconds: 600, title: "Tea", now: t0)
        let events = engine.advance(now: t0.addingTimeInterval(600 + TimerEngine.missedLimit + 1))
        #expect(events == [.missed(t)])
        let note = TimerEngine.missedNotice(for: t)
        #expect(note.title == "Tea" && note.subtitle == "Missed while the Mac was asleep")
        #expect(note.priority == .low && note.sneak == false && note.ttl == 3600)
        #expect(note.id != t.id && ActivityCenter.isValidID(note.id!))
        var center = ActivityCenter()
        #expect(try center.apply(note, now: t0).source == TimerEngine.source)
    }
}

@Suite struct VolumeChangeFilterTests {
    func at(_ s: TimeInterval) -> Date { t0.addingTimeInterval(s) }

    @Test func aNewOutputsOwnLevelShowsNoHUD() {
        var f = VolumeChangeFilter()
        #expect(f.shows(now: at(0), replacing: false))
        f.outputChanged(at: at(10))
        #expect(!f.shows(now: at(11), replacing: false))
        #expect(f.shows(now: at(12.5), replacing: false))
    }

    @Test func replacingTheSystemDisplayShowsOnlyChangesFromTheKeys() {
        var f = VolumeChangeFilter()
        // An app changing the volume.
        #expect(!f.shows(now: at(0), replacing: true))
        f.keyHandled(at: at(5))
        #expect(f.shows(now: at(5.2), replacing: true))
        #expect(!f.shows(now: at(6), replacing: true))
    }
}

@Suite struct SameTrackPositionTests {
    @Test func theNewestPositionOfATrackWins() {
        var m = MediaArbiter()
        // Spotify's own report, then the bridge's after a seek, for the same song.
        m.update(NowPlaying(source: .spotify, bundleID: "com.spotify.client", title: "Song", artist: "Band", isPlaying: true,
                            duration: 200, elapsed: 30, timestamp: t0))
        m.updateFromBridge(NowPlaying(source: .system, bundleID: "com.spotify.client", title: "Song", artist: "Band", isPlaying: true,
                                      duration: 200, elapsed: 120, timestamp: t0.addingTimeInterval(5)))
        let shown = m.current(now: t0.addingTimeInterval(6))
        // Still Spotify's own (its controls), at the bridge's newer position.
        #expect(shown?.source == .spotify)
        #expect(shown?.position(at: t0.addingTimeInterval(6)) == 121)
    }
}

@Suite struct ClipboardSizeTests {
    @Test func longCopiesAreCappedByTotalSize() {
        var h = ClipboardHistory(limit: 500)
        _ = h.add("keep me", types: [], sourceBundleID: nil, now: t0)
        h.togglePin(id: h.entries[0].id)
        for i in 0..<60 {
            _ = h.add(String(repeating: Character(UnicodeScalar(65 + i % 26)!), count: 99_000) + "\(i)", types: [], sourceBundleID: nil,
                      now: t0.addingTimeInterval(Double(i)))
        }
        let total = h.entries.reduce(0) { $0 + $1.text.utf8.count }
        #expect(total <= ClipboardHistory.maxTotalBytes)
        #expect(h.entries.count < 60)
        // The newest copy and the pinned one stay.
        #expect(h.entries.first?.text.hasSuffix("59") == true)
        #expect(h.entries.contains { $0.text == "keep me" && $0.pinned })
    }
}

@Suite struct ShortcutClashTests {
    @Test func isletsTwoShortcutsCantShareKeys() {
        #expect(Hotkey.sameKeys("ctrl+option+i", "option+ctrl+i"))
        #expect(!Hotkey.sameKeys("ctrl+option+i", "ctrl+option+a"))
        #expect(!Hotkey.sameKeys("ctrl+option+i", ""))
        #expect(!Hotkey.sameKeys("", ""))
        #expect(!Hotkey.sameKeys(IsletSettings().hotkey, IsletSettings().askHotkey))
    }
}

@Suite struct PermissionNoteTests {
    @Test func accessibilitySaysWhatItReadsAndWhatMacOSCallsIt() throws {
        let on26 = try #require(PermissionKind.accessibility.note(osMajor: 26))
        #expect(on26.hasPrefix("Islet doesn't read what you type."))
        let on27 = try #require(PermissionKind.accessibility.note(osMajor: 27))
        #expect(on27.hasPrefix("Called Device Control and Data Access in System Settings."))
        #expect(PermissionKind.accessibility.note(osMajor: 27, status: .denied)?.contains("Remove Islet with the minus button") == true)
        #expect(PermissionKind.camera.note(osMajor: 27) == nil)
        // The setting it names is the one on the Notifications & HUDs page.
        #expect(on26.contains("Replace the system volume and brightness display"))
        // Full screen is confirmed through Accessibility too (`FullscreenDetector`).
        #expect(on26.contains("whether a window is in full screen"))
        #expect(!on26.contains("—"))
    }
}

@Suite struct AppLocationTests {
    @Test func onlyAnApplicationsFolderIsSettled() {
        let home = "/Users/a"
        #expect(AppLocation.isSettled(bundlePath: "/Applications/Islet.app", home: home))
        #expect(AppLocation.isSettled(bundlePath: "/Users/a/Applications/Islet.app", home: home))
        #expect(!AppLocation.isSettled(bundlePath: "/Users/a/Downloads/Islet.app", home: home))
        #expect(!AppLocation.isSettled(bundlePath: "/private/var/folders/x/T/AppTranslocation/ABC/d/Islet.app", home: home))
        #expect(!AppLocation.isSettled(bundlePath: "/Applications Old/Islet.app", home: home))
    }
}

@Suite struct HookPayloadTests {
    @Test func aToolsOutputIsntSent() throws {
        let big = String(repeating: "x", count: 2_000_000)
        let payload = try JSONSerialization.data(withJSONObject: [
            "hook_event_name": "PostToolUse", "session_id": "s1", "tool_name": "Bash",
            "tool_input": ["command": "ls"], "tool_response": ["stdout": big],
        ])
        let trimmed = AgentHooks.trimmed(payload)
        #expect(trimmed.count < 1000)
        let obj = try #require(try JSONSerialization.jsonObject(with: trimmed) as? [String: Any])
        #expect(obj["tool_response"] == nil)
        #expect((obj["tool_input"] as? [String: Any])?["command"] as? String == "ls")
        // Nothing to drop, or not an object: as it was.
        let plain = Data(#"{"agent":"x","event":"done"}"#.utf8)
        #expect(AgentHooks.trimmed(plain) == plain)
        #expect(AgentHooks.trimmed(Data("not json".utf8)) == Data("not json".utf8))
    }
}
