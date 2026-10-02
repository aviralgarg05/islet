import Foundation
import Testing
@testable import IsletCore

private func track(elapsed: Double? = 60, duration: Double? = 200, playing: Bool = true, at time: Date = t0) -> NowPlaying {
    NowPlaying(source: .system, title: "Song", artist: "Band", isPlaying: playing, duration: duration, elapsed: elapsed, timestamp: time)
}

@Suite struct MediaSeekTests {
    @Test func relativeJumpsStayInsideTheTrack() {
        #expect(MediaSeek.target(from: 60, by: 15, duration: 200) == 75)
        #expect(MediaSeek.target(from: 10, by: -15, duration: 200) == 0)
        // Never past the last second, so +15 near the end doesn't skip the track.
        #expect(MediaSeek.target(from: 195, by: 15, duration: 200) == 199)
        #expect(MediaSeek.target(from: 60, by: 15, duration: nil) == 75)
        #expect(MediaSeek.target(from: nil, by: 15, duration: 200) == nil)
    }

    @Test func scrubberGeometry() {
        #expect(MediaSeek.fraction(x: 50, width: 200) == 0.25)
        #expect(MediaSeek.fraction(x: -10, width: 200) == 0)
        #expect(MediaSeek.fraction(x: 500, width: 200) == 1)
        #expect(MediaSeek.fraction(x: 10, width: 0) == 0)
        #expect(MediaSeek.position(fraction: 0.5, duration: 240) == 120)
        #expect(MediaSeek.position(fraction: 1.4, duration: 240) == 240)
        #expect(MediaSeek.position(fraction: 0.5, duration: 0) == 0)
    }

    @Test func hapticDetentOnlyWhenReachingAnEnd() {
        #expect(MediaSeek.reachedEnd(from: 0.5, to: 1))
        #expect(MediaSeek.reachedEnd(from: 0.3, to: 0))
        #expect(!MediaSeek.reachedEnd(from: 1, to: 1))       // resting at the end: once only
        #expect(!MediaSeek.reachedEnd(from: 0, to: 0))
        #expect(MediaSeek.reachedEnd(from: 0, to: 1))        // jumped across
        #expect(!MediaSeek.reachedEnd(from: 0.2, to: 0.6))
        #expect(MediaSeek.reachedEnd(from: nil, to: 0))       // pressed right at the start
    }

    @Test func trailingLabel() {
        #expect(MediaSeek.trailingLabel(position: 71, duration: 243, remaining: true) == "\u{2212}2:52")
        #expect(MediaSeek.trailingLabel(position: 71, duration: 243, remaining: false) == "4:03")
        #expect(MediaSeek.trailingLabel(position: 300, duration: 243, remaining: true) == "\u{2212}0:00")
    }
}

@Suite struct SeekGraceTests {
    @Test func holdsTheRequestedPositionUntilThePlayerCatchesUp() {
        let np = track(elapsed: 60, at: t0)   // stale: still reports 60 s after we seek to 150
        let grace = SeekGrace(target: 150, at: t0, track: np.trackKey)
        #expect(grace.position(for: np, now: t0) == 150)
        #expect(grace.position(for: np, now: t0.addingTimeInterval(1)) == 151)   // advances while playing
        // After the window the player's own position is used again.
        #expect(grace.position(for: np, now: t0.addingTimeInterval(2)) == 62)
    }

    @Test func pausedDoesNotAdvanceAndOtherTracksIgnoreIt() {
        let paused = track(elapsed: 60, playing: false)
        let grace = SeekGrace(target: 150, at: t0, track: paused.trackKey)
        #expect(grace.position(for: paused, now: t0.addingTimeInterval(1)) == 150)
        var other = paused
        other.title = "Next song"
        #expect(grace.position(for: other, now: t0.addingTimeInterval(1)) == 60)
        #expect(!grace.isActive(now: t0.addingTimeInterval(-1)))
    }

    @Test func clampsToTheDuration() {
        let np = track(elapsed: 0, duration: 100)
        let grace = SeekGrace(target: 99.5, at: t0, track: np.trackKey)
        #expect(grace.position(for: np, now: t0.addingTimeInterval(1.2)) == 100)
    }
}

@Suite struct MediaModesTests {
    @Test func mediaRemoteValues() {
        #expect(MediaModes.shuffle(mediaRemote: nil) == nil)
        #expect(MediaModes.shuffle(mediaRemote: 0) == nil)
        #expect(MediaModes.shuffle(mediaRemote: 1) == false)
        #expect(MediaModes.shuffle(mediaRemote: 2) == true)
        #expect(MediaModes.shuffle(mediaRemote: 3) == true)
        #expect(MediaModes.mediaRemoteShuffle(true) == 3)
        #expect(MediaModes.mediaRemoteShuffle(false) == 1)
        #expect(MediaModes.repeatMode(mediaRemote: 0) == nil)
        for mode in RepeatMode.allCases {
            #expect(MediaModes.repeatMode(mediaRemote: MediaModes.mediaRemoteRepeat(mode)) == mode)
        }
    }

    @Test func repeatCyclesLikeMusic() {
        #expect(MediaModes.next(after: .off) == .all)
        #expect(MediaModes.next(after: .all) == .one)
        #expect(MediaModes.next(after: .one) == .off)
    }

    @Test func arbiterFillsModesFromTheSameTrack() {
        var arbiter = MediaArbiter()
        var system = track()
        system.shuffle = true
        system.repeatMode = .all
        var spotify = track(at: t0.addingTimeInterval(1))
        spotify.source = .spotify
        arbiter.update(system)
        arbiter.update(spotify)
        let current = arbiter.current(now: t0.addingTimeInterval(2))
        #expect(current?.source == .spotify)
        #expect(current?.shuffle == true)
        #expect(current?.repeatMode == .all)
    }

    @Test func newCommandsDecodeFromTheAPI() throws {
        for name in ["skipForward", "skipBackward", "toggleShuffle", "toggleRepeat"] {
            let c = try JSONDecoder().decode(PlaybackCommand.self, from: Data("\"\(name)\"".utf8))
            #expect(c.rawValue == name)
        }
    }
}

@Suite struct SwipeRecognizerTests {
    /// A trackpad gesture: began, then changes 16 ms apart, then ended.
    func gesture(_ steps: [(Double, Double)], inverted: Bool = true, start: TimeInterval = 100, step: TimeInterval = 0.016) -> [ScrollSample] {
        var out = [ScrollSample(dx: 0, dy: 0, phase: .began, inverted: inverted, time: start)]
        for (i, d) in steps.enumerated() {
            out.append(ScrollSample(dx: d.0, dy: d.1, phase: .changed, inverted: inverted, time: start + Double(i + 1) * step))
        }
        out.append(ScrollSample(dx: 0, dy: 0, phase: .ended, inverted: inverted, time: start + Double(steps.count + 1) * step))
        return out
    }

    func run(_ samples: [ScrollSample], _ r: inout SwipeRecognizer) -> [SwipeDirection] {
        samples.compactMap { r.feed($0) }
    }

    @Test func quickSwipeFiresOnce() {
        var r = SwipeRecognizer()
        // Natural scrolling: fingers moving down report positive deltas.
        #expect(run(gesture(Array(repeating: (0, 8), count: 10)), &r) == [.down])
        #expect(run(gesture(Array(repeating: (0, -8), count: 10), start: 200), &r) == [.up])
    }

    @Test func traditionalScrollingIsNormalised() {
        var r = SwipeRecognizer()
        // Without natural scrolling the same finger movement reports the opposite sign.
        #expect(run(gesture(Array(repeating: (0, -8), count: 6), inverted: false), &r) == [.down])
        #expect(run(gesture(Array(repeating: (8, 0), count: 6), inverted: false, start: 200), &r) == [.left])
    }

    @Test func horizontalSwipes() {
        var r = SwipeRecognizer()
        #expect(run(gesture(Array(repeating: (-9, 1), count: 5)), &r) == [.left])
        #expect(run(gesture(Array(repeating: (9, -1), count: 5), start: 200), &r) == [.right])
    }

    @Test func slowScrollingNeverFires() {
        var r = SwipeRecognizer()
        // 2 pt every 50 ms: 40 pt in total, but never 24 pt within 250 ms.
        #expect(run(gesture(Array(repeating: (0, 2), count: 20), step: 0.05), &r).isEmpty)
    }

    @Test func diagonalMovementIsIgnored() {
        var r = SwipeRecognizer()
        #expect(run(gesture(Array(repeating: (7, 7), count: 8)), &r).isEmpty)
    }

    @Test func momentumNeverFires() {
        var r = SwipeRecognizer()
        let inertia = (0..<20).map { i in
            ScrollSample(dx: 0, dy: 12, phase: .none, momentum: i == 0 ? .began : .changed, time: 100 + Double(i) * 0.016)
        }
        #expect(run(inertia, &r).isEmpty)
    }

    @Test func midGestureEventsWithoutABeginningAreIgnored() {
        var r = SwipeRecognizer()
        // A gesture that started over another window: only its later events arrive here.
        let tail = (0..<10).map { ScrollSample(dx: 0, dy: 10, phase: .changed, time: 100 + Double($0) * 0.016) }
        #expect(run(tail, &r).isEmpty)
    }

    @Test func mouseWheelUsesLinesAndPauses() {
        var r = SwipeRecognizer()
        func notch(_ t: TimeInterval, _ lines: Double) -> ScrollSample {
            ScrollSample(dx: 0, dy: lines, precise: false, inverted: false, time: t)
        }
        // One notch (8 pt) is not a swipe; three quick ones are.
        #expect(r.feed(notch(0, -1)) == nil)
        #expect(r.feed(notch(0.05, -1)) == nil)
        #expect(r.feed(notch(0.1, -1)) == .down)
        // Keep spinning: quiet until the wheel pauses.
        #expect(r.feed(notch(0.15, -1)) == nil)
        #expect(r.feed(notch(0.2, -1)) == nil)
        #expect(r.feed(notch(0.25, -1)) == nil)
        #expect(r.feed(notch(0.3, -1)) == nil)
        // After a pause, a new flick fires again.
        #expect(r.feed(notch(1.0, 3)) == .up)
    }
}

@Suite struct GestureMapTests {
    func map(_ d: SwipeDirection, _ surface: GestureSurface, _ s: IsletSettings = IsletSettings()) -> GestureAction? {
        GestureMap.action(for: d, on: surface, settings: s)
    }

    @Test func grammar() {
        #expect(map(.down, .closed) == .expand)
        #expect(map(.down, .compactMedia) == .expand)
        #expect(map(.down, .sneak) == .expand)
        #expect(map(.down, .expanded(media: true)) == nil)
        #expect(map(.up, .expanded(media: false)) == .collapse)
        #expect(map(.up, .closed) == nil)
        #expect(map(.left, .compactMedia) == .nextTrack)
        #expect(map(.right, .compactMedia) == .previousTrack)
        #expect(map(.left, .expanded(media: true)) == .nextTrack)
        #expect(map(.left, .expanded(media: false)) == nil)
        #expect(map(.left, .compactActivity) == .cycle(forward: true))
        #expect(map(.right, .compactActivity) == .cycle(forward: false))
        #expect(map(.left, .closed) == nil)
    }

    @Test func settingsSwitchGesturesOff() {
        var s = IsletSettings()
        s.swipeMediaAction = .seek
        #expect(map(.left, .compactMedia, s) == .seek(10))
        #expect(map(.right, .compactMedia, s) == .seek(-10))
        s.swipeMedia = false
        s.swipeCyclesActivities = false
        s.swipeDownToOpen = false
        #expect(map(.left, .compactMedia, s) == nil)
        #expect(map(.left, .compactActivity, s) == nil)
        #expect(map(.down, .closed, s) == nil)
        #expect(map(.up, .expanded(media: false), s) == .collapse)
        s.gesturesEnabled = false
        #expect(map(.up, .expanded(media: false), s) == nil)
    }

    @Test func surfaces() throws {
        var c = ActivityCenter()
        let a = try c.apply(ActivitySpec(id: "a", title: "A"), now: t0)
        let battery = BatteryEvent(kind: .pluggedIn, state: BatteryState(level: 50, isCharging: true, isPluggedIn: true), until: t0)
        #expect(GestureSurface.from(.hidden, homeShowsMedia: true) == nil)
        #expect(GestureSurface.from(.idle, homeShowsMedia: false) == .closed)
        #expect(GestureSurface.from(.compact(.battery(battery)), homeShowsMedia: false) == .closed)
        #expect(GestureSurface.from(.sneak(a), homeShowsMedia: false) == .sneak)
        #expect(GestureSurface.from(.compact(.nowPlaying(track())), homeShowsMedia: false) == .compactMedia)
        #expect(GestureSurface.from(.compact(.activity(a, others: 0)), homeShowsMedia: false) == .compactActivity)
        #expect(GestureSurface.from(.expanded, homeShowsMedia: true) == .expanded(media: true))
    }
}

@Suite struct CompactCycleTests {
    @Test func cyclesThroughActivitiesInOrder() throws {
        var c = ActivityCenter()
        for id in ["a", "b", "c"] { try c.apply(ActivitySpec(id: id, title: id), now: t0) }
        let ordered = c.ordered(now: t0)
        let ids = ordered.map(\.id)
        #expect(CompactCycle.next(after: ids[0], in: ordered, forward: true) == ids[1])
        #expect(CompactCycle.next(after: ids[2], in: ordered, forward: true) == ids[0])
        #expect(CompactCycle.next(after: ids[0], in: ordered, forward: false) == ids[2])
        #expect(CompactCycle.next(after: "gone", in: ordered, forward: true) == ids[0])
        #expect(CompactCycle.next(after: ids[0], in: Array(ordered.prefix(1)), forward: true) == nil)
    }

    @Test func presenterHonoursTheSwipedActivity() throws {
        var c = ActivityCenter()
        try c.apply(ActivitySpec(id: "agent", title: "Agent", priority: .high, sneak: false), now: t0)
        try c.apply(ActivitySpec(id: "build", title: "Build", sneak: false), now: t0)
        let playing = track()
        var inputs = PresenterInputs(now: t0, center: c, nowPlaying: playing)
        guard case .compact(.activity(let top, _)) = Presenter.present(inputs) else { Issue.record("expected activity"); return }
        #expect(top.id == "agent")
        inputs.focusedActivityID = "build"
        guard case .compact(.activity(let focused, let others)) = Presenter.present(inputs) else { Issue.record("expected focus"); return }
        #expect(focused.id == "build")
        #expect(others == 1)
        // A focus on something that has gone falls back to the usual order.
        inputs.focusedActivityID = "gone"
        guard case .compact(.activity(let back, _)) = Presenter.present(inputs) else { Issue.record("expected fallback"); return }
        #expect(back.id == "agent")
        // Expanded, HUD and sneak still win.
        inputs.focusedActivityID = "build"
        inputs.isExpanded = true
        #expect(Presenter.present(inputs) == .expanded)
    }

    @Test func aCriticalActivityIsNotHiddenByTheSwipedOne() throws {
        var c = ActivityCenter()
        try c.apply(ActivitySpec(id: "build", title: "Build", sneak: false), now: t0)
        try c.apply(ActivitySpec(id: "battery-low", title: "Battery at 4%", priority: .critical, sneak: false), now: t0)
        let inputs = PresenterInputs(now: t0, center: c, focusedActivityID: "build")
        guard case .compact(.activity(let shown, _)) = Presenter.present(inputs) else { Issue.record("expected activity"); return }
        #expect(shown.id == "battery-low")
    }
}

@Suite struct KeepAwakeTests {
    @Test func parsesDurations() {
        #expect(KeepAwake.parse("15m") == .start(minutes: 15))
        #expect(KeepAwake.parse("1h") == .start(minutes: 60))
        #expect(KeepAwake.parse("1h30m") == .start(minutes: 90))
        #expect(KeepAwake.parse("2.5h") == .start(minutes: 150))
        #expect(KeepAwake.parse("90s") == .start(minutes: 1.5))
        #expect(KeepAwake.parse("45") == .start(minutes: 45))
        #expect(KeepAwake.parse("") == .start(minutes: nil))
        #expect(KeepAwake.parse("on") == .start(minutes: nil))
        #expect(KeepAwake.parse("forever") == .start(minutes: nil))
        #expect(KeepAwake.parse("OFF") == .stop)
        #expect(KeepAwake.parse("0") == .stop)
        #expect(KeepAwake.parse("25h") == nil)
        #expect(KeepAwake.parse("-5m") == nil)
        #expect(KeepAwake.parse("soon") == nil)
        #expect(KeepAwake.parse("5x") == nil)
        #expect(KeepAwake.parse("h") == nil)
        #expect(KeepAwake.parse("1h5") == nil)
    }

    @Test func releasesOnLowBatteryOnlyWhenUnplugged() {
        #expect(KeepAwake.shouldRelease(BatteryState(level: 19, isCharging: false, isPluggedIn: false)))
        #expect(!KeepAwake.shouldRelease(BatteryState(level: 20, isCharging: false, isPluggedIn: false)))
        #expect(!KeepAwake.shouldRelease(BatteryState(level: 5, isCharging: true, isPluggedIn: true)))
        #expect(!KeepAwake.shouldRelease(BatteryState(level: 5, isCharging: false, isPluggedIn: true)))
        #expect(!KeepAwake.shouldRelease(nil))
    }

    @Test func status() {
        #expect(KeepAwake.status(nil, now: t0) == KeepAwakeStatus(active: false))
        let timed = KeepAwakeSession(since: t0, until: t0.addingTimeInterval(3600))
        let s = KeepAwake.status(timed, now: t0.addingTimeInterval(61))
        #expect(s.active)
        #expect(s.minutesLeft == 59)
        let open = KeepAwake.status(KeepAwakeSession(since: t0), now: t0)
        #expect(open.active && open.until == nil && open.minutesLeft == nil)
    }

    @Test func activityCountsDownOrSaysOn() throws {
        var c = ActivityCenter()
        let timed = KeepAwakeSession(since: t0, until: t0.addingTimeInterval(900))
        let a = try c.apply(KeepAwake.activity(for: timed, sneak: false) { _ in "10:15" }, now: t0)
        #expect(a.id == KeepAwake.activityID)
        #expect(a.icon == .symbol("cup.and.saucer.fill"))
        #expect(a.trailingText(now: t0) == "15:00")
        #expect(a.subtitle == "Display stays on until 10:15")
        #expect(a.actions.first?.url?.absoluteString == "islet://awake/off")
        #expect(a.expiresAt == nil)
        var d = ActivityCenter()
        let open = try d.apply(KeepAwake.activity(for: KeepAwakeSession(since: t0), sneak: false) { _ in "" }, now: t0)
        #expect(open.trailingText(now: t0) == "On")
    }

    @Test func urlCommands() throws {
        #expect(try URLCommand.parse(URL(string: "islet://awake?for=1h")!) == .awake(.start(minutes: 60)))
        #expect(try URLCommand.parse(URL(string: "islet://awake?minutes=20")!) == .awake(.start(minutes: 20)))
        #expect(try URLCommand.parse(URL(string: "islet://awake")!) == .awake(.start(minutes: nil)))
        #expect(try URLCommand.parse(URL(string: "islet://awake/off")!) == .awake(.stop))
        #expect(try URLCommand.parse(URL(string: "islet://awake?for=off")!) == .awake(.stop))
        #expect(throws: URLCommand.ParseError.invalid("for", "lots")) { try URLCommand.parse(URL(string: "islet://awake?for=lots")!) }
        #expect(try URLCommand.parse(URL(string: "islet://media/shuffle")!) == .media(.toggleShuffle))
        #expect(try URLCommand.parse(URL(string: "islet://media/repeat")!) == .media(.toggleRepeat))
        #expect(try URLCommand.parse(URL(string: "islet://media/forward")!) == .media(.skipForward))
        #expect(try URLCommand.parse(URL(string: "islet://media/rewind")!) == .media(.skipBackward))
        #expect(try URLCommand.parse(URL(string: "islet://media/back")!) == .media(.previous))
    }
}

@Suite struct AwakeAPITests {
    func request(_ method: String, _ path: String, body: String? = nil) -> HTTPRequest {
        let raw = "\(method) \(path) HTTP/1.1\r\nAuthorization: Bearer tok\r\nContent-Length: \(body?.utf8.count ?? 0)\r\n\r\n" + (body ?? "")
        guard case .complete(let r) = HTTPParser.parse(Data(raw.utf8)) else { fatalError("bad test request") }
        return r
    }

    @Test func startReadAndStop() async throws {
        let b = FakeBackend(now: t0)
        let rt = APIRouter(token: "tok", version: "t", backend: b, clock: { t0 })
        let started = await rt.handle(request("POST", "/v1/awake", body: #"{"minutes": 60}"#))
        #expect(started.status == 200)
        let s = try APIJSON.decoder.decode(KeepAwakeStatus.self, from: started.body)
        #expect(s.active && s.minutesLeft == 60 && s.until == t0.addingTimeInterval(3600))

        let read = try APIJSON.decoder.decode(KeepAwakeStatus.self, from: await rt.handle(request("GET", "/v1/awake")).body)
        #expect(read == s)

        let open = try APIJSON.decoder.decode(KeepAwakeStatus.self, from: await rt.handle(request("POST", "/v1/awake")).body)
        #expect(open.active && open.until == nil)
        let zero = try APIJSON.decoder.decode(KeepAwakeStatus.self, from: await rt.handle(request("PUT", "/v1/awake", body: #"{"minutes": 0}"#)).body)
        #expect(zero.until == nil)

        let stopped = await rt.handle(request("DELETE", "/v1/awake"))
        #expect(stopped.status == 200)
        #expect(try APIJSON.decoder.decode(KeepAwakeStatus.self, from: stopped.body).active == false)
        #expect(await b.awake == nil)
    }

    @Test func rejectsBadInput() async {
        let rt = APIRouter(token: "tok", version: "t", backend: FakeBackend(now: t0), clock: { t0 })
        #expect(await rt.handle(request("POST", "/v1/awake", body: #"{"minutes": -5}"#)).status == 422)
        #expect(await rt.handle(request("POST", "/v1/awake", body: #"{"minutes": 5000}"#)).status == 422)
        #expect(await rt.handle(request("POST", "/v1/awake", body: #"{"minutes": "soon"}"#)).status == 422)
        #expect(await rt.handle(request("PATCH", "/v1/awake", body: "{}")).status == 405)
        #expect(await rt.handle(request("GET", "/v1/awake/extra")).status == 404)
    }

    @Test func newMediaCommandsReachTheBackend() async {
        let b = FakeBackend(now: t0)
        let rt = APIRouter(token: "tok", version: "t", backend: b, clock: { t0 })
        _ = await rt.handle(request("POST", "/v1/media", body: #"{"title":"Song"}"#))
        for c in ["skipForward", "skipBackward", "toggleShuffle", "toggleRepeat"] {
            #expect(await rt.handle(request("POST", "/v1/media/command", body: "{\"command\":\"\(c)\"}")).status == 204)
        }
        #expect(await b.commands == [.skipForward, .skipBackward, .toggleShuffle, .toggleRepeat])
        #expect(await rt.handle(request("POST", "/v1/media/command", body: #"{"command":"louder"}"#)).status == 422)
    }
}

@Suite struct BatteryAlertTests {
    func state(_ level: Int, plugged: Bool = false, charging: Bool = false) -> BatteryState {
        BatteryState(level: level, isCharging: charging, isPluggedIn: plugged)
    }

    @Test func thresholdsComeFromSettings() {
        var s = IsletSettings()
        s.batteryLowThreshold = 30
        s.batteryCriticalThreshold = 15
        var d = BatteryEventDetector()
        d.configure(with: s)
        _ = d.ingest(state(35), now: t0)
        #expect(d.ingest(state(30), now: t0)?.kind == .low)
        #expect(d.ingest(state(20), now: t0) == nil)
        #expect(d.ingest(state(15), now: t0)?.kind == .critical)
    }

    @Test func chargedAlertFiresOnceAtTheLevel() {
        var s = IsletSettings()
        s.batteryChargedAlert = 80
        var d = BatteryEventDetector()
        d.configure(with: s)
        _ = d.ingest(state(78, plugged: true, charging: true), now: t0)
        #expect(d.ingest(state(79, plugged: true, charging: true), now: t0) == nil)
        #expect(d.ingest(state(80, plugged: true, charging: true), now: t0)?.kind == .charged)
        #expect(d.ingest(state(81, plugged: true, charging: true), now: t0) == nil)
        // Off by default.
        var plain = BatteryEventDetector()
        plain.configure(with: IsletSettings())
        _ = plain.ingest(state(79, plugged: true, charging: true), now: t0)
        #expect(plain.ingest(state(80, plugged: true, charging: true), now: t0) == nil)
    }

    @Test func detailLine() {
        var charging = BatteryState(level: 76, isCharging: true, isPluggedIn: true, minutesRemaining: 48, adapterWatts: 96)
        #expect(charging.detail == "full in 48 min · 96 W")
        charging.minutesRemaining = nil
        #expect(charging.detail == "96 W")
        #expect(BatteryState(level: 80, isCharging: false, isPluggedIn: true, adapterWatts: 67).detail == "On hold · 67 W")
        #expect(BatteryState(level: 100, isCharging: false, isPluggedIn: true).detail == "Charged")
        #expect(BatteryState(level: 40, isCharging: false, isPluggedIn: false, minutesRemaining: 125, adapterWatts: 96).detail == "2 h 5 min left")
        #expect(BatteryState(level: 40, isCharging: false, isPluggedIn: false).detail == nil)
    }

    @Test func wattsSurviveTheAPI() throws {
        let b = BatteryState(level: 50, isCharging: true, isPluggedIn: true, adapterWatts: 140)
        let back = try APIJSON.decoder.decode(BatteryState.self, from: APIJSON.encoder.encode(b))
        #expect(back.adapterWatts == 140)
        let old = try JSONDecoder().decode(BatteryState.self, from: Data(#"{"level":5,"isCharging":false,"isPluggedIn":false,"lowPowerMode":false}"#.utf8))
        #expect(old.adapterWatts == nil)
    }
}

@Suite struct ControlsSettingsTests {
    @Test func oldHapticsSwitchIsMigrated() {
        #expect(IsletSettings.decodeLenient(Data(#"{"hapticFeedback": false}"#.utf8)).hapticsMode == .off)
        #expect(IsletSettings.decodeLenient(Data(#"{"hapticFeedback": true}"#.utf8)).hapticsMode == .direct)
        // Configs saved by older versions carry both keys; the old switch turned haptics off whatever the mode said.
        #expect(IsletSettings.decodeLenient(Data(#"{"hapticFeedback": false, "hapticsMode": "direct"}"#.utf8)).hapticsMode == .off)
        #expect(IsletSettings.decodeLenient(Data(#"{"hapticFeedback": true, "hapticsMode": "all"}"#.utf8)).hapticsMode == .all)
        // The old key is not written back.
        let saved = String(decoding: (try? JSONEncoder().encode(IsletSettings())) ?? Data(), as: UTF8.self)
        #expect(!saved.contains("hapticFeedback"))
    }

    @Test func newSettingsDecodeAndClamp() {
        let json = #"{"swipeMediaAction": "seek", "swipeUpToClose": false, "batteryLowThreshold": 90, "batteryCriticalThreshold": 70, "batteryChargedAlert": 20, "mediaShowsRemainingTime": false}"#
        let s = IsletSettings.decodeLenient(Data(json.utf8))
        #expect(s.swipeMediaAction == .seek)
        #expect(s.swipeUpToClose == false)
        #expect(s.mediaShowsRemainingTime == false)
        #expect(s.batteryLowThreshold == 50)
        #expect(s.batteryCriticalThreshold == 49)
        #expect(s.batteryChargedAlert == 50)
        let bad = IsletSettings.decodeLenient(Data(#"{"swipeMediaAction": "fling", "batteryChargedAlert": 0}"#.utf8))
        #expect(bad.swipeMediaAction == .track)
        #expect(bad.batteryChargedAlert == 0)
        let d = IsletSettings()
        #expect(d.gesturesEnabled && d.swipeDownToOpen && d.swipeUpToClose && d.swipeMedia && d.swipeCyclesActivities)
        #expect(d.batteryLowThreshold == 20 && d.batteryCriticalThreshold == 10 && d.batteryChargedAlert == 0)
    }
}
