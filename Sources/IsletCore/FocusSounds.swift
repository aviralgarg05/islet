import Foundation

/// What plays while a Pomodoro focus round runs.
public enum FocusSound: String, Codable, Sendable, CaseIterable {
    case off
    /// Deep, soft rumble (Islet makes it; no files, nothing downloaded).
    case brownNoise
    /// Brighter, like steady rain.
    case pinkNoise
    /// Brown noise that slowly swells and falls, like waves on a shore.
    case waves
    /// Whatever the user's music player has: it plays when focus starts and pauses for breaks.
    case music

    public var title: String {
        switch self {
        case .off: return "None"
        case .brownNoise: return "Brown noise"
        case .pinkNoise: return "Rain"
        case .waves: return "Waves"
        case .music: return "Your music"
        }
    }

    /// Made by Islet, as opposed to the user's own music.
    public var isGenerated: Bool { self == .brownNoise || self == .pinkNoise || self == .waves }
}

/// The noise for a focus sound, one sample at a time. Pure and deterministic for a seed, so the
/// tests can listen to it; the audio thread asks for a buffer at a time.
public struct NoiseGenerator: Sendable {
    public let sound: FocusSound
    public let sampleRate: Double
    private var state: UInt64
    private var brown: Double = 0
    private var b0 = 0.0, b1 = 0.0, b2 = 0.0
    private var phase = 0.0

    /// Seconds for one wave to come in and go out.
    public static let wavePeriod: Double = 9

    public init(sound: FocusSound, sampleRate: Double = 44_100, seed: UInt64 = 0x9E37_79B9_7F4A_7C15) {
        self.sound = sound
        self.sampleRate = max(8_000, sampleRate)
        state = seed == 0 ? 0x9E37_79B9_7F4A_7C15 : seed
    }

    /// White noise in -1...1 (xorshift64*).
    private mutating func white() -> Double {
        state ^= state >> 12
        state ^= state << 25
        state ^= state >> 27
        let x = state &* 0x2545_F491_4F6C_DD1D
        return Double(x >> 11) / Double(1 << 53) * 2 - 1
    }

    /// The next sample, in -1...1. Silence for sounds that aren't generated.
    public mutating func next() -> Float {
        let value: Double
        switch sound {
        case .brownNoise:
            value = nextBrown()
        case .pinkNoise:
            // Paul Kellet's economy filter: three poles approximate -3 dB per octave.
            let w = white()
            b0 = 0.99765 * b0 + w * 0.0990460
            b1 = 0.96300 * b1 + w * 0.2965164
            b2 = 0.57000 * b2 + w * 1.0526913
            value = (b0 + b1 + b2 + w * 0.1848) * 0.2
        case .waves:
            phase += 1 / (sampleRate * Self.wavePeriod)
            if phase >= 1 { phase -= 1 }
            // A swell that rises slowly and never quite falls to silence.
            let swell = 0.5 - 0.5 * cos(2 * .pi * phase)
            value = nextBrown() * (0.25 + 0.75 * swell * swell)
        case .off, .music:
            value = 0
        }
        return Float(min(1, max(-1, value)))
    }

    private mutating func nextBrown() -> Double {
        // Integrated white noise with a slight leak, so it never wanders off to one side.
        brown = (brown + 0.02 * white()) / 1.02
        return brown * 3.5
    }

    /// Fills a buffer with the next samples.
    public mutating func fill(_ buffer: UnsafeMutableBufferPointer<Float>) {
        for i in buffer.indices { buffer[i] = next() }
    }
}

/// Decides what the focus sound does as the Pomodoro moves between focus and breaks. It only
/// pauses music it started itself, so music that was already playing is left alone.
public struct FocusSoundDirector: Equatable, Sendable {
    public enum Action: Equatable, Sendable {
        case startNoise(FocusSound)
        case stopNoise
        case playMusic
        case pauseMusic
    }

    /// The generated sound playing now.
    public private(set) var noise: FocusSound?
    /// Islet pressed play on the user's music for this focus round.
    public private(set) var startedMusic = false
    /// A focus round with "Your music" is under way.
    private var musicRound = false

    public init() {}

    /// What to do now. `focusing`: a Pomodoro focus round is running (not paused, not a break).
    public mutating func update(sound: FocusSound, focusing: Bool, musicPlaying: Bool) -> [Action] {
        var actions: [Action] = []
        let wantNoise: FocusSound? = focusing && sound.isGenerated ? sound : nil
        if wantNoise != noise {
            if noise != nil { actions.append(.stopNoise) }
            if let wantNoise { actions.append(.startNoise(wantNoise)) }
            noise = wantNoise
        }
        let wantMusic = focusing && sound == .music
        if wantMusic && !musicRound {
            // Focus has just begun: play, unless it already is.
            musicRound = true
            if !musicPlaying {
                actions.append(.playMusic)
                startedMusic = true
            }
        } else if !wantMusic && musicRound {
            // A break, a pause or the end: pause the music only if Islet started it.
            musicRound = false
            if startedMusic && musicPlaying { actions.append(.pauseMusic) }
            startedMusic = false
        }
        return actions
    }

    /// Everything stops (the feature was switched off, or Islet is quitting).
    public mutating func stopAll(musicPlaying: Bool) -> [Action] {
        update(sound: .off, focusing: false, musicPlaying: musicPlaying)
    }
}

/// Ready-made Pomodoro lengths. The long break is three short breaks, after every four rounds.
public struct PomodoroPreset: Equatable, Sendable, Identifiable {
    public var focus: Double
    public var shortBreak: Double

    public var id: String { "\(Int(focus))/\(Int(shortBreak))" }
    public var longBreak: Double { shortBreak * 3 }

    public static let classic = PomodoroPreset(focus: 25, shortBreak: 5)
    public static let long = PomodoroPreset(focus: 50, shortBreak: 10)
    public static let deep = PomodoroPreset(focus: 90, shortBreak: 20)
    public static let all: [PomodoroPreset] = [classic, long, deep]

    /// "25 min focus, 5 min break".
    public var title: String { "\(Int(focus)) min focus, \(Int(shortBreak)) min break" }
    /// "25 / 5".
    public var shortTitle: String { "\(Int(focus)) / \(Int(shortBreak))" }

    /// `schedule` with this preset's lengths; how often the long break comes stays the user's.
    public func applied(to schedule: PomodoroSchedule) -> PomodoroSchedule {
        PomodoroSchedule(focusMinutes: focus, shortBreakMinutes: shortBreak, longBreakMinutes: longBreak,
                         longBreakEvery: schedule.longBreakEvery).sanitized()
    }

    /// The preset these lengths are, or nil for lengths of the user's own.
    public static func matching(_ schedule: PomodoroSchedule) -> PomodoroPreset? {
        let s = schedule.sanitized()
        return all.first { $0.focus == s.focusMinutes && $0.shortBreak == s.shortBreakMinutes && $0.longBreak == s.longBreakMinutes }
    }
}

extension TimerEngine {
    /// A Pomodoro focus round is counting down (not paused, not a break).
    public var isFocusing: Bool {
        guard let p = pomodoro else { return false }
        return p.phase == .focus && p.status == .running
    }
}
