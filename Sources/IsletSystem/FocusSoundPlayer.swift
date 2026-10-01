import AVFoundation
import Foundation
import IsletCore

/// Plays the focus sounds Islet makes (brown noise, rain, waves). The audio engine runs only
/// while a sound plays; it fades in and out over about a second, then stops completely.
public final class FocusSoundPlayer {
    private var engine: AVAudioEngine?
    private var playing: FocusSound?
    private var fade: DispatchSourceTimer?
    /// Bumped on every start and stop, so a fade that finishes late doesn't stop a newer sound.
    private var generation = 0

    public init() {}

    public var isPlaying: Bool { playing != nil }

    /// Starts `sound` at `volume` (0...1), replacing whatever plays.
    public func play(_ sound: FocusSound, volume: Double) {
        guard sound.isGenerated else { return stop() }
        if playing == sound, let engine {
            ramp(engine, to: Float(volume), stopAfter: false)
            return
        }
        stopNow()
        let engine = AVAudioEngine()
        let rate = engine.outputNode.outputFormat(forBus: 0).sampleRate
        guard rate > 0, let format = AVAudioFormat(standardFormatWithSampleRate: rate, channels: 1) else { return }
        // The generator lives on the audio thread alone.
        let box = GeneratorBox(NoiseGenerator(sound: sound, sampleRate: rate, seed: UInt64.random(in: 1...UInt64.max)))
        let source = AVAudioSourceNode(format: format) { _, _, frames, buffers -> OSStatus in
            let list = UnsafeMutableAudioBufferListPointer(buffers)
            for buffer in list {
                guard let data = buffer.mData?.assumingMemoryBound(to: Float.self) else { continue }
                box.generator.fill(UnsafeMutableBufferPointer(start: data, count: Int(frames)))
            }
            return noErr
        }
        engine.attach(source)
        engine.connect(source, to: engine.mainMixerNode, format: format)
        engine.mainMixerNode.outputVolume = 0
        do {
            try engine.start()
        } catch {
            NSLog("Islet: focus sound could not start: %@", error.localizedDescription)
            return
        }
        self.engine = engine
        playing = sound
        generation += 1
        ramp(engine, to: Float(min(1, max(0, volume))), stopAfter: false)
    }

    /// Fades out, then stops the engine.
    public func stop() {
        guard let engine, playing != nil else { return }
        playing = nil
        ramp(engine, to: 0, stopAfter: true)
    }

    public func setVolume(_ volume: Double) {
        guard let engine, playing != nil else { return }
        ramp(engine, to: Float(min(1, max(0, volume))), stopAfter: false)
    }

    private func stopNow() {
        fade?.cancel()
        fade = nil
        engine?.stop()
        engine = nil
        playing = nil
    }

    /// About a second from the current volume to `target`, at 30 steps a second.
    private func ramp(_ engine: AVAudioEngine, to target: Float, stopAfter: Bool) {
        fade?.cancel()
        let start = engine.mainMixerNode.outputVolume
        let steps = 30
        var step = 0
        let mine = generation
        let t = DispatchSource.makeTimerSource(queue: .main)
        t.schedule(deadline: .now(), repeating: 1.0 / 30, leeway: .milliseconds(10))
        t.setEventHandler { [weak self] in
            step += 1
            let f = Float(step) / Float(steps)
            engine.mainMixerNode.outputVolume = start + (target - start) * f * f * (3 - 2 * f)
            guard step >= steps else { return }
            t.cancel()
            guard let self, self.generation == mine else { return }
            self.fade = nil
            if stopAfter {
                engine.stop()
                if self.engine === engine { self.engine = nil }
            }
        }
        t.resume()
        fade = t
    }
}

private final class GeneratorBox: @unchecked Sendable {
    var generator: NoiseGenerator
    init(_ generator: NoiseGenerator) { self.generator = generator }
}
