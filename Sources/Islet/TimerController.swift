import AppKit
import IsletCore
import IsletSystem
import Observation
import os

/// Runs the timers. Keeps a `TimerEngine`, shows each timer as an activity, saves them so
/// they survive a relaunch, and wakes up once for the soonest end. The wake-up is a
/// wall-clock timer, so a Mac that sleeps through the end still rings on wake. With no
/// running timers nothing is scheduled at all.
@MainActor
@Observable
final class TimerController {
    private(set) var engine = TimerEngine()
    /// The Timer card's custom field is open.
    var isEntering = false

    private unowned let model: AppModel
    @ObservationIgnored private var wakeUp: DispatchSourceTimer?
    /// Where timers are saved; nil until `start()` (snapshots never touch the disk).
    @ObservationIgnored private var storeURL: URL?
    /// False when an unreadable timers.json couldn't be moved aside: then it is left alone.
    @ObservationIgnored private var canSave = true
    /// What each timer's activity currently looks like, so only real changes are re-applied.
    @ObservationIgnored private var shown: [String: ActivitySpec] = [:]
    @ObservationIgnored private var syncing = false
    /// The island was opened by a ringing timer; it may close again once that is dealt with.
    @ObservationIgnored private var openedForAlarm = false

    init(model: AppModel) {
        self.model = model
    }

    var timers: [TimerItem] { engine.ordered }
    var isPomodoroRunning: Bool { engine.pomodoro != nil }
    private var schedule: PomodoroSchedule { model.settings.pomodoro }

    /// Whether an activity is one of these timers (the Timer card shows those itself).
    func owns(_ activity: Activity) -> Bool {
        activity.source == TimerEngine.source && engine.timers.contains { $0.id == activity.id }
    }

    /// Restores saved timers and catches up on any that ended while Islet wasn't running.
    func start() {
        let url = IsletPaths.supportDirectory.appendingPathComponent("timers.json")
        storeURL = url
        // A timers.json that doesn't parse is moved aside rather than saved over.
        let restored = TimerEngine.start(from: url)
        if let saved = restored.value { engine = saved }
        canSave = restored.canSave
        if let moved = restored.setAside { Log.files.error("timers.json couldn't be read; kept as \(moved.lastPathComponent, privacy: .public)") }
        fire()
    }

    // MARK: Commands

    /// Runs a command from the API, the URL scheme or the island. New timers started from
    /// elsewhere pop out briefly; ones started in the island itself don't need to.
    @discardableResult
    func perform(_ command: TimerCommand, announce: Bool = true) throws -> TimerItem? {
        let before = Set(engine.timers.map(\.id))
        let result = try engine.perform(command, now: Date(), schedule: schedule)
        var fresh: Set<String> = []
        if announce, let result, !before.contains(result.id) || command.isStart { fresh.insert(result.id) }
        changed(announce: fresh)
        return result
    }

    /// Starts a timer from text such as "tea 4m" or "at 18:30"; false when it can't be read.
    @discardableResult
    func start(text: String) -> Bool {
        guard let parsed = try? DurationParser.parse(text) else { return false }
        return (try? perform(.start(seconds: parsed.seconds, title: parsed.title, id: nil), announce: false)) != nil
    }

    func start(minutes: Double) {
        _ = try? perform(.start(seconds: minutes * 60, title: nil, id: nil), announce: false)
    }

    func control(_ action: TimerAction, _ timer: TimerItem, seconds: TimeInterval? = nil) {
        Haptics.play(.tap)
        _ = try? perform(.control(action, id: timer.id, seconds: seconds), announce: false)
    }

    /// The Timer card's chip, which gives its own haptic.
    func togglePomodoro() {
        _ = try? perform(.pomodoro(.toggle), announce: false)
    }

    /// Someone dismissed a timer's activity (the island's close button, a script, the API):
    /// that stops the timer too.
    func activityRemoved(_ id: String) {
        guard !syncing, shown[id] != nil else { return }
        shown[id] = nil
        _ = try? engine.stop(id)
        changed()
    }

    /// Show every timer's activity afresh: unmuted, the running countdowns come back at once
    /// rather than when a timer is next paused or rings.
    func resync() {
        shown = [:]
        sync(announce: [])
    }

    /// Every activity from the "timer" source was removed (`isletctl clear --source timer`).
    func activitiesRemoved(source: String) {
        guard !syncing, source == TimerEngine.source, !engine.timers.isEmpty else { return }
        shown = [:]
        engine.removeAll()
        changed()
    }

    // MARK: Time

    /// Moves on whatever has ended, then rings: a sound, the island opened on Home (unless the
    /// island is hidden for a fullscreen app or the app in front), and the ringing activity
    /// itself, which is critical so it shows even over fullscreen and taps the trackpad in the
    /// "all" haptics mode.
    private func fire() {
        let events = engine.advance(now: Date(), schedule: schedule)
        var fresh: Set<String> = []
        var rang = false
        for event in events {
            switch event {
            case .finished(let t):
                fresh.insert(t.id)
                rang = true
            case .phaseChanged(_, let t):
                fresh.insert(t.id)
            case .missed(let t):
                _ = try? model.applyLocal(TimerEngine.missedNotice(for: t))
            }
        }
        changed(announce: fresh)
        if !fresh.isEmpty { playSound() }
        if rang { openForAlarm() }
    }

    private func changed(announce: Set<String> = []) {
        sync(announce: announce)
        if openedForAlarm, !engine.isRinging { alarmHandled() }
        if let storeURL, canSave { try? engine.save(to: storeURL) }
        scheduleWakeUp()
        // A focus round starting, pausing or giving way to a break moves the focus sound.
        if storeURL != nil { model.tools.focus.update() }
    }

    private func scheduleWakeUp() {
        wakeUp?.cancel()
        wakeUp = nil
        guard storeURL != nil, let next = engine.nextDeadline() else { return }
        let t = DispatchSource.makeTimerSource(queue: .main)
        t.schedule(wallDeadline: .now() + max(0, next.timeIntervalSinceNow) + 0.01, leeway: .milliseconds(50))
        t.setEventHandler { [weak self] in
            MainActor.assumeIsolated { self?.fire() }
        }
        t.resume()
        wakeUp = t
    }

    /// Mirrors the engine into activities. A spec can't clear a countdown once set, so a
    /// changed timer is removed and shown again rather than updated in place (this also
    /// replaces any other activity that happened to use the same id).
    private func sync(announce: Set<String>) {
        let ordered = engine.ordered
        let wanted = Dictionary(ordered.map { ($0.id, engine.spec(for: $0, schedule: schedule)) }, uniquingKeysWith: { a, _ in a })
        syncing = true
        defer { syncing = false }
        for id in shown.keys where wanted[id] == nil { model.remove(activityID: id) }
        // Soonest last, so it is the most recent and leads among equal priorities.
        for t in ordered.reversed() {
            guard let spec = wanted[t.id], spec != shown[t.id] || announce.contains(t.id) else { continue }
            model.remove(activityID: t.id)
            var s = spec
            s.sneak = announce.contains(t.id)
            _ = try? model.applyLocal(s)
        }
        shown = wanted
    }

    // MARK: Alarm

    private func openForAlarm() {
        guard model.expandedScreen == nil, let display = alarmDisplay, !islandHidden(on: display) else { return }
        model.select(tab: .home)
        model.pinned = true
        model.setExpanded(display)
        openedForAlarm = true
    }

    /// The main screen when it has an island, else a display that does (with "Show island on:
    /// the notched screen", the main screen can be an external display with no island).
    private var alarmDisplay: CGDirectDisplayID? {
        let islands = NSApp.windows.filter { $0 is IslandPanel && $0.isVisible }.compactMap { $0.screen?.displayID }
        if let main = NSScreen.main?.displayID, islands.isEmpty || islands.contains(main) { return main }
        return islands.first
    }

    /// The same rules as the presentation: hidden for the app in front, or over a full screen
    /// app when "In full screen" hides everything and the app's rule doesn't keep the island.
    private func islandHidden(on display: CGDirectDisplayID) -> Bool {
        model.isSuppressed(display)
    }

    /// Nothing rings any more: let the island close normally when the pointer leaves.
    private func alarmHandled() {
        openedForAlarm = false
        if model.expandedScreen != nil { model.pinned = false }
    }

    private func playSound() {
        let name = model.settings.timerSound.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty, name.lowercased() != "none" else { return }
        NSSound(named: NSSound.Name(name))?.play()
    }

    // MARK: Snapshots

    /// Replace the timers with a fixed set for `--snapshot`. Nothing is saved or scheduled.
    func showForSnapshot(_ engine: TimerEngine) {
        self.engine = engine
        sync(announce: [])
    }
}

private extension TimerCommand {
    var isStart: Bool {
        if case .start = self { return true }
        return false
    }
}

// MARK: - Local API

extension AppModel {
    nonisolated func listTimers() async -> [TimerItem] {
        await MainActor.run { self.timers.timers }
    }

    nonisolated func timerCommand(_ command: TimerCommand) async throws -> TimerItem? {
        try await MainActor.run { try self.timers.perform(command) }
    }
}
