import AppKit
import AVFoundation
import Foundation
import IsletCore
import IsletSystem
import Observation
import os

/// The teleprompter page: the script, where it is, and whether it is moving. The page draws the
/// text at `playback`'s position and, while playing, hands the rest of the way to one linear
/// animation; the app's deadline timer stops it at the end (`endsAt`).
@MainActor
@Observable
final class TeleprompterController {
    private(set) var script = ""
    private(set) var playback = TeleprompterPlayback()
    /// The script's height as laid out, and the page's, measured by the page.
    private(set) var textHeight: Double = 0
    private(set) var viewport: Double = 0
    /// From one line of the script to the next, as the page sets it. Pausing and playing
    /// settle the position on a whole line of it.
    @ObservationIgnored var linePitch: Double = 0

    @ObservationIgnored private(set) var settings = TeleprompterSettings()
    /// Where the script is kept; nil in snapshots, which read and write nothing.
    @ObservationIgnored let file: TeleprompterScriptFile?
    /// The deadline may have moved.
    @ObservationIgnored var onChange: (() -> Void)?
    @ObservationIgnored private var loaded = false
    @ObservationIgnored private var pendingSave: DispatchWorkItem?

    init(file: TeleprompterScriptFile?) { self.file = file }

    /// Reads the saved script the first time it is needed.
    func load() {
        guard !loaded else { return }
        loaded = true
        script = file?.read() ?? script
        reconfigure()
    }

    var words: Int { Teleprompter.wordCount(script) }
    var isPlaying: Bool { playback.isPlaying }

    /// Saved half a second after the last change, so typing in Settings writes once.
    func setScript(_ text: String) {
        loaded = true
        guard text != script else { return }
        script = text
        reconfigure()
        guard let file else { return }
        pendingSave?.cancel()
        let work = DispatchWorkItem { [text] in
            do { try file.write(text) } catch { Log.files.error("couldn't save the teleprompter script: \(error.localizedDescription, privacy: .public)") }
        }
        pendingSave = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: work)
    }

    func apply(_ s: TeleprompterSettings) {
        guard s != settings else { return }
        settings = s
        if !s.enabled { playback.pause(now: Date()) }
        reconfigure()
    }

    func layout(textHeight: Double, viewport: Double) {
        guard abs(textHeight - self.textHeight) > 0.5 || abs(viewport - self.viewport) > 0.5 else { return }
        self.textHeight = textHeight
        self.viewport = viewport
        reconfigure()
    }

    /// The last line stops a little under the top, where the eye already is.
    private func reconfigure(now: Date = Date()) {
        let travel = Teleprompter.travel(textHeight: textHeight, lead: viewport * 0.4)
        let speed = Teleprompter.speed(travel: travel, words: words, wordsPerMinute: settings.wordsPerMinute)
        playback.configure(speed: speed, end: travel, now: now)
        onChange?()
    }

    /// Pausing rests the script on a whole line; playing starts from the line the page shows.
    func togglePlay(now: Date = Date()) {
        if playback.isPlaying {
            playback.pause(now: now)
            playback.settle(pitch: linePitch)
        } else {
            playback.settle(pitch: linePitch)
            playback.play(now: now)
        }
        onChange?()
    }

    func pause(now: Date = Date()) {
        guard playback.isPlaying else { return }
        playback.pause(now: now)
        playback.settle(pitch: linePitch)
        onChange?()
    }

    func restart() {
        playback.restart()
        onChange?()
    }

    /// A scroll by hand stops it and moves the script.
    func scroll(by delta: Double, now: Date = Date()) {
        playback.scroll(by: delta, now: now)
        onChange?()
    }

    func endsAt(now: Date) -> Date? { playback.endsAt(now: now) }

    func advance(now: Date) {
        if playback.advance(now: now) { onChange?() }
    }

    /// A script and a position for offline snapshots.
    func showDemo(_ text: String, at position: Double) {
        loaded = true
        script = text
        playback = TeleprompterPlayback()
        textHeight = 1000
        viewport = 100
        reconfigure()
        playback.scroll(by: position, now: Date())
    }
}

/// The Mirror page's camera: on while the page shows, off as soon as it doesn't, and off while
/// the screen is locked or asleep even if the page was left open.
@MainActor
@Observable
final class MirrorModel {
    private(set) var state: CameraMirror.State = .off
    private(set) var access: PermissionStatus = .notDetermined

    @ObservationIgnored private var showing = false
    /// The screen is locked, or asleep: nobody is looking, so the camera stays off. Waking
    /// to the lock screen keeps it off until the Mac is unlocked.
    @ObservationIgnored private var locked = false
    @ObservationIgnored private var asleep = false
    private var away: Bool { locked || asleep }
    /// Watched only while the page shows.
    @ObservationIgnored private let lockMonitor = UnlockMonitor()
    @ObservationIgnored private var sleepObservers: [NSObjectProtocol] = []
    /// Made the first time the page shows, so an Islet that never opens it never loads the camera.
    @ObservationIgnored private var made: CameraMirror?

    var session: AVCaptureSession { camera.session }

    private var camera: CameraMirror {
        if let made { return made }
        let c = CameraMirror()
        c.onChange = { [weak self] s in self?.state = s }
        made = c
        return c
    }

    func show() {
        showing = true
        watchAway(true)
        access = CameraMirror.access
        if access != .granted {
            state = .needsAccess
        } else if !away {
            camera.start()
        }
    }

    func hide() {
        showing = false
        watchAway(false)
        made?.stop()
        if state == .needsAccess { state = .off }
    }

    /// The screen locked or slept, or came back, while the page shows.
    private func setAway(locked: Bool? = nil, asleep: Bool? = nil) {
        if let locked { self.locked = locked }
        if let asleep { self.asleep = asleep }
        guard showing else { return }
        if away {
            made?.stop()
        } else if CameraMirror.access == .granted {
            camera.start()
        }
    }

    private func watchAway(_ on: Bool) {
        guard on else {
            lockMonitor.stop()
            sleepObservers.forEach(NSWorkspace.shared.notificationCenter.removeObserver)
            sleepObservers = []
            locked = false
            asleep = false
            return
        }
        lockMonitor.onLock = { [weak self] in self?.setAway(locked: true) }
        lockMonitor.onUnlock = { [weak self] in self?.setAway(locked: false) }
        lockMonitor.start()
        guard sleepObservers.isEmpty else { return }
        let center = NSWorkspace.shared.notificationCenter
        for (name, value) in [(NSWorkspace.screensDidSleepNotification, true), (NSWorkspace.screensDidWakeNotification, false)] {
            sleepObservers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.setAway(asleep: value) }
            })
        }
    }

    /// "Allow camera": macOS asks the first time; after a no, System Settings opens at Camera.
    func allow() {
        if CameraMirror.access == .notDetermined {
            CameraMirror.requestAccess { [weak self] status in
                guard let self else { return }
                self.access = status
                if status == .granted, self.showing { self.camera.start() }
            }
        } else {
            NSWorkspace.shared.open(PermissionKind.camera.settingsURL)
        }
    }

    /// A state for offline snapshots (no camera is touched).
    func showDemo(_ state: CameraMirror.State, access: PermissionStatus) {
        self.state = state
        self.access = access
    }
}
