import AppKit
import Foundation
import IsletCore
import IsletSystem

// Now Playing controls, swipe gestures, keep awake and the extra battery alerts.
extension AppModel {
    // MARK: Media controls

    /// Routes the commands that need more than a pass-through: ±15 s become a seek from the
    /// shown position, and shuffle/repeat are set explicitly when the state is known.
    /// Returns nil to let `send` handle the command as before.
    func sendControl(_ command: PlaybackCommand, position: Double?) -> Bool? {
        switch command {
        case .skipForward, .skipBackward:
            let delta = command == .skipForward ? MediaSeek.skipInterval : -MediaSeek.skipInterval
            // Position unknown: fall back to the player's own skip command.
            return skip(by: delta) ? true : nil
        case .toggleShuffle:
            guard systemMedia.isRunning, let on = nowPlaying?.shuffle else { return nil }
            return systemMedia.setShuffle(!on)
        case .toggleRepeat:
            guard systemMedia.isRunning, let mode = nowPlaying?.repeatMode else { return nil }
            return systemMedia.setRepeat(MediaModes.next(after: mode))
        default:
            return nil
        }
    }

    /// Jump relative to the position on screen. False when the position is unknown.
    @discardableResult
    func skip(by delta: Double) -> Bool {
        guard let np = nowPlaying,
              let target = MediaSeek.target(from: displayPosition(np, now: Date()), by: delta, duration: np.duration) else { return false }
        return seek(to: target)
    }

    /// Seek and hold the scrubber at the new position until the player reports it.
    @discardableResult
    func seek(to position: Double) -> Bool {
        guard let np = nowPlaying else { return false }
        controls.seekGrace = SeekGrace(target: position, at: Date(), track: np.trackKey)
        let ok = send(.seek, position: position)
        if !ok { controls.seekGrace = nil }
        return ok
    }

    /// Position to show for `np`, bridging the moment after a seek.
    func displayPosition(_ np: NowPlaying, now: Date) -> Double? {
        controls.seekGrace?.position(for: np, now: now) ?? np.position(at: now)
    }

    func toggleRemainingTime() {
        settings.mediaShowsRemainingTime.toggle()
        saveSettings()
    }

    // MARK: Volume and output

    func soundControlsAppeared() {
        controls.soundViewers += 1
        refreshSound()
        guard controls.soundViewers == 1 else { return }
        controls.outputWatcher.onChange = { [weak self] in self?.refreshSound() }
        controls.outputWatcher.start()
    }

    func soundControlsDisappeared() {
        controls.soundViewers = max(0, controls.soundViewers - 1)
        if controls.soundViewers == 0 { controls.outputWatcher.stop() }
    }

    func refreshSound() {
        let list = AudioOutputs.all()
        if list != controls.outputs { controls.outputs = list }
        let id = AudioOutputs.defaultID()
        if id != controls.defaultOutputID { controls.defaultOutputID = id }
        if let out = AudioMonitor.readOutput() {
            if abs(out.volume - controls.volume) > 0.001 { controls.volume = out.volume }
            if out.muted != controls.muted { controls.muted = out.muted }
        }
    }

    func setVolume(_ value: Double) {
        let v = min(1, max(0, value))
        guard AudioMonitor.setOutputVolume(v) else { return }
        controls.volume = v
        if v > 0 { controls.muted = false }
    }

    func toggleMute() {
        if AudioMonitor.setMuted(!controls.muted) { controls.muted.toggle() }
    }

    func selectOutput(_ id: UInt32) {
        guard AudioOutputs.setDefault(id) else { return }
        controls.defaultOutputID = id
        refreshSound()
    }

    var currentOutput: AudioOutputDevice? {
        controls.outputs.first { $0.id == controls.defaultOutputID }
    }

    // MARK: Gestures

    /// A two-finger swipe on the island of `display`.
    func handleSwipe(_ direction: SwipeDirection, display: CGDirectDisplayID) {
        let p = presentation(for: display)
        let homeMedia = tab == .home && settings.mediaEnabled && nowPlaying != nil
        guard let surface = GestureSurface.from(p, homeShowsMedia: homeMedia),
              let action = GestureMap.action(for: direction, on: surface, settings: settings) else { return }
        if action != .expand { Haptics.play(.snap) }
        switch action {
        case .expand:
            setExpanded(display)
        case .collapse:
            pinned = false
            controls.hoverOpenBlocked = true
            setExpanded(nil)
        case .nextTrack:
            send(.next)
        case .previousTrack:
            send(.previous)
        case .seek(let delta):
            skip(by: delta)
        case .cycle(let forward):
            let current = focusedActivity(for: p)?.id
            if let next = CompactCycle.next(after: current, in: activities, forward: forward) {
                controls.focusedActivityID = next
            }
        }
    }

    // MARK: Keep awake

    func setKeepAwake(_ change: KeepAwakeChange, announce: Bool) {
        guard case .start(let minutes) = change else {
            stopKeepAwake(notice: nil)
            return
        }
        if KeepAwake.shouldRelease(battery ?? BatteryMonitor.read()) {
            _ = try? commit(KeepAwake.notice("Battery below \(KeepAwake.lowBatteryLevel)%. Plug in to keep your Mac awake."))
            return
        }
        guard controls.assertion.hold(reason: "Islet keep awake") else { return }
        let now = Date()
        let session = KeepAwakeSession(since: now, until: minutes.map { now.addingTimeInterval($0 * 60) })
        controls.awake = session
        controls.awakeTimer?.invalidate()
        controls.awakeTimer = nil
        if let until = session.until {
            let t = Timer(fire: until, interval: 0, repeats: false) { [weak self] _ in
                MainActor.assumeIsolated { self?.stopKeepAwake(notice: "Your Mac can sleep again.") }
            }
            t.tolerance = 1
            RunLoop.main.add(t, forMode: .common)
            controls.awakeTimer = t
        }
        // Its own watcher: the battery module's monitor only runs if the module was on at launch.
        if controls.awakeBattery == nil {
            let monitor = BatteryMonitor()
            monitor.onChange = { [weak self] s in self?.keepAwakeBatteryChanged(s) }
            monitor.start()
            controls.awakeBattery = monitor
        }
        // A fresh activity, so switching from a timed period to "until turned off" drops the countdown.
        remove(activityID: KeepAwake.activityID)
        _ = try? commit(KeepAwake.activity(for: session, sneak: announce) { $0.formatted(date: .omitted, time: .shortened) })
    }

    func stopKeepAwake(notice: String?) {
        controls.awakeTimer?.invalidate()
        controls.awakeTimer = nil
        controls.awakeBattery?.stop()
        controls.awakeBattery = nil
        controls.assertion.release()
        guard controls.awake != nil else { return }
        controls.awake = nil
        remove(activityID: KeepAwake.activityID)
        if let notice { _ = try? commit(KeepAwake.notice(notice)) }
    }

    /// Called with every battery reading: keep awake never runs the battery flat.
    func keepAwakeBatteryChanged(_ s: BatteryState) {
        guard controls.awake != nil, KeepAwake.shouldRelease(s) else { return }
        stopKeepAwake(notice: "Battery below \(KeepAwake.lowBatteryLevel)%. Your Mac can sleep again.")
    }

    /// Let the Mac sleep again when Islet quits.
    func releaseKeepAwake() {
        controls.awakeTimer?.invalidate()
        controls.assertion.release()
    }

    // MARK: Battery

    /// Charging reached the level set in Settings (for example 80%, to unplug early).
    func announceCharged(_ s: BatteryState) {
        _ = try? commit(ActivitySpec(
            id: "battery-charged", source: "battery", title: "Charged to \(s.level)%", subtitle: "You can unplug now",
            icon: .symbol("battery.100percent.bolt"), state: .success, tint: "green", priority: .normal, ttl: 6, sneak: true
        ))
    }
}

// MARK: - Local API

extension AppModel {
    nonisolated func keepAwake(_ change: KeepAwakeChange?) async -> KeepAwakeStatus {
        await MainActor.run {
            if let change { self.setKeepAwake(change, announce: true) }
            return KeepAwake.status(self.controls.awake, now: Date())
        }
    }
}
