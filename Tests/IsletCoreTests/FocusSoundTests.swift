import Foundation
import Testing
@testable import IsletCore

@Suite struct NoiseGeneratorTests {
    func samples(_ sound: FocusSound, count: Int = 44_100, seed: UInt64 = 7) -> [Float] {
        var g = NoiseGenerator(sound: sound, sampleRate: 44_100, seed: seed)
        return (0..<count).map { _ in g.next() }
    }

    /// How often the signal crosses zero, per sample: high for hiss, low for rumble.
    func crossings(_ s: [Float]) -> Double {
        Double(zip(s, s.dropFirst()).filter { ($0 < 0) != ($1 < 0) }.count) / Double(s.count)
    }

    func rms(_ s: [Float]) -> Double {
        (s.reduce(0) { $0 + Double($1 * $1) } / Double(s.count)).squareRoot()
    }

    @Test(arguments: [FocusSound.brownNoise, .pinkNoise, .waves])
    func staysInRangeAndIsAudible(_ sound: FocusSound) {
        let s = samples(sound)
        #expect(s.allSatisfy { $0 >= -1 && $0 <= 1 })
        #expect(rms(s) > 0.02, "\(sound) is too quiet")
        #expect(rms(s) < 0.7, "\(sound) is too loud")
        // No lasting lean to one side.
        let mean = s.reduce(0) { $0 + Double($1) } / Double(s.count)
        #expect(abs(mean) < 0.2)
    }

    @Test func sameSeedSameSound() {
        #expect(samples(.pinkNoise, count: 500, seed: 3) == samples(.pinkNoise, count: 500, seed: 3))
        #expect(samples(.pinkNoise, count: 500, seed: 3) != samples(.pinkNoise, count: 500, seed: 4))
    }

    @Test func brownIsDeeperThanPink() {
        #expect(crossings(samples(.brownNoise)) < crossings(samples(.pinkNoise)))
    }

    @Test func wavesSwellAndFall() {
        // Loudness over two-second windows across one wave changes clearly.
        let s = samples(.waves, count: 44_100 * 9)
        let windows = stride(from: 0, to: s.count - 88_200, by: 88_200).map { rms(Array(s[$0..<$0 + 88_200])) }
        #expect((windows.max() ?? 0) > 2 * (windows.min() ?? 1))
    }

    @Test func otherChoicesAreSilent() {
        #expect(samples(.music, count: 100).allSatisfy { $0 == 0 })
        #expect(samples(.off, count: 100).allSatisfy { $0 == 0 })
    }

    @Test func fillsABuffer() {
        var g = NoiseGenerator(sound: .brownNoise, seed: 9)
        var a = [Float](repeating: 0, count: 64)
        a.withUnsafeMutableBufferPointer { g.fill($0) }
        var h = NoiseGenerator(sound: .brownNoise, seed: 9)
        #expect(a == (0..<64).map { _ in h.next() })
    }
}

@Suite struct FocusSoundDirectorTests {
    @Test func noisePlaysOnlyDuringFocus() {
        var d = FocusSoundDirector()
        #expect(d.update(sound: .waves, focusing: false, musicPlaying: false).isEmpty)
        #expect(d.update(sound: .waves, focusing: true, musicPlaying: false) == [.startNoise(.waves)])
        #expect(d.update(sound: .waves, focusing: true, musicPlaying: false).isEmpty, "nothing twice")
        #expect(d.update(sound: .waves, focusing: false, musicPlaying: false) == [.stopNoise])
        #expect(d.noise == nil)
    }

    @Test func changingTheSoundMidRoundSwapsIt() {
        var d = FocusSoundDirector()
        _ = d.update(sound: .brownNoise, focusing: true, musicPlaying: false)
        #expect(d.update(sound: .pinkNoise, focusing: true, musicPlaying: false) == [.stopNoise, .startNoise(.pinkNoise)])
        #expect(d.update(sound: .off, focusing: true, musicPlaying: false) == [.stopNoise])
    }

    @Test func musicPlaysForFocusAndPausesForTheBreak() {
        var d = FocusSoundDirector()
        #expect(d.update(sound: .music, focusing: true, musicPlaying: false) == [.playMusic])
        #expect(d.startedMusic)
        #expect(d.update(sound: .music, focusing: true, musicPlaying: true).isEmpty)
        #expect(d.update(sound: .music, focusing: false, musicPlaying: true) == [.pauseMusic])
        #expect(d.update(sound: .music, focusing: true, musicPlaying: false) == [.playMusic], "the next round plays again")
    }

    @Test func musicThatWasAlreadyPlayingIsLeftAlone() {
        var d = FocusSoundDirector()
        #expect(d.update(sound: .music, focusing: true, musicPlaying: true).isEmpty)
        #expect(!d.startedMusic)
        #expect(d.update(sound: .music, focusing: false, musicPlaying: true).isEmpty, "not Islet's to pause")
    }

    @Test func musicTheUserPausedStaysPaused() {
        var d = FocusSoundDirector()
        _ = d.update(sound: .music, focusing: true, musicPlaying: false)
        // Paused by hand during focus: still focusing, so no new play.
        #expect(d.update(sound: .music, focusing: true, musicPlaying: false).isEmpty)
        #expect(d.update(sound: .music, focusing: false, musicPlaying: false).isEmpty)
    }

    @Test func stopAllStopsWhatIsletStarted() {
        var d = FocusSoundDirector()
        _ = d.update(sound: .brownNoise, focusing: true, musicPlaying: false)
        #expect(d.stopAll(musicPlaying: false) == [.stopNoise])
        var m = FocusSoundDirector()
        _ = m.update(sound: .music, focusing: true, musicPlaying: false)
        #expect(m.stopAll(musicPlaying: true) == [.pauseMusic])
    }

    @Test func focusingMeansARunningFocusRound() throws {
        let t = Date(timeIntervalSince1970: 0)
        var e = TimerEngine()
        #expect(!e.isFocusing)
        try e.startPomodoro(now: t)
        #expect(e.isFocusing)
        try e.pause(TimerEngine.pomodoroID, now: t.addingTimeInterval(60))
        #expect(!e.isFocusing)
        try e.resume(TimerEngine.pomodoroID, now: t.addingTimeInterval(120))
        _ = e.advance(now: t.addingTimeInterval(120 + 25 * 60))
        #expect(e.pomodoro?.phase == .shortBreak)
        #expect(!e.isFocusing)
        var plain = TimerEngine()
        try plain.start(seconds: 60, now: t)
        #expect(!plain.isFocusing)
    }

    @Test func focusSoundStartsOffAndVolumeIsClamped() {
        #expect(IsletSettings().focusSound == .off)
        let s = IsletSettings.decodeLenient(Data(#"{"focusSound": "waves", "focusSoundVolume": 7}"#.utf8))
        #expect(s.focusSound == .waves)
        #expect(s.focusSoundVolume == 1)
    }
}

@Suite struct PomodoroPresetTests {
    @Test func threePresetsWithLongBreaksOfThreeShortOnes() {
        #expect(PomodoroPreset.all.map(\.shortTitle) == ["25 / 5", "50 / 10", "90 / 20"])
        #expect(PomodoroPreset.all.map(\.longBreak) == [15, 30, 60])
        #expect(PomodoroPreset.classic.title == "25 min focus, 5 min break")
    }

    @Test func applyingKeepsHowOftenTheLongBreakComes() {
        let mine = PomodoroSchedule(focusMinutes: 30, shortBreakMinutes: 6, longBreakMinutes: 20, longBreakEvery: 3)
        let s = PomodoroPreset.long.applied(to: mine)
        #expect(s == PomodoroSchedule(focusMinutes: 50, shortBreakMinutes: 10, longBreakMinutes: 30, longBreakEvery: 3))
        #expect(PomodoroPreset.matching(s) == .long)
        #expect(PomodoroPreset.matching(mine) == nil)
    }

    @Test func theDefaultScheduleIsTheClassicPreset() {
        #expect(PomodoroPreset.matching(PomodoroSchedule()) == .classic)
    }
}
