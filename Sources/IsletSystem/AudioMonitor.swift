import AudioToolbox
import CoreAudio
import Foundation

/// Observes the default output device's volume and mute state via CoreAudio property
/// listeners (event-driven, no permissions), and the default input device's in-use state
/// for the microphone privacy indicator.
public final class AudioMonitor {
    public struct Output: Equatable {
        public var volume: Double
        public var muted: Bool
        public var deviceName: String?
    }

    public var onOutputChange: ((Output) -> Void)?
    public var onMicrophoneInUse: ((Bool) -> Void)?

    private let queue = DispatchQueue.main
    private var outputDevice: AudioObjectID = 0
    private var inputDevice: AudioObjectID = 0
    private var outputListeners: [(AudioObjectPropertyAddress, AudioObjectPropertyListenerBlock)] = []
    private var inputListener: AudioObjectPropertyListenerBlock?
    private var defaultOutputListener: AudioObjectPropertyListenerBlock?
    private var defaultInputListener: AudioObjectPropertyListenerBlock?
    private var last: Output?

    public init() {}
    deinit { stop() }

    static func address(_ selector: AudioObjectPropertySelector, _ scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal,
                        _ element: AudioObjectPropertyElement = kAudioObjectPropertyElementMain) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: element)
    }

    public static func defaultDevice(input: Bool) -> AudioObjectID {
        var id = AudioObjectID(0)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        var addr = address(input ? kAudioHardwarePropertyDefaultInputDevice : kAudioHardwarePropertyDefaultOutputDevice)
        AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &id)
        return id
    }

    static func deviceName(_ id: AudioObjectID) -> String? {
        var name: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        var addr = address(kAudioObjectPropertyName)
        guard AudioObjectGetPropertyData(id, &addr, 0, nil, &size, &name) == noErr, let n = name else { return nil }
        return n.takeRetainedValue() as String
    }

    /// Read the current output volume (0...1) and mute state.
    public static func readOutput(device: AudioObjectID = defaultDevice(input: false)) -> Output? {
        guard device != 0 else { return nil }
        var volume = Float32(0)
        var size = UInt32(MemoryLayout<Float32>.size)
        var vAddr = address(kAudioHardwareServiceDeviceProperty_VirtualMainVolume, kAudioDevicePropertyScopeOutput)
        var status = AudioObjectGetPropertyData(device, &vAddr, 0, nil, &size, &volume)
        if status != noErr {
            // Some devices only expose per-channel volume.
            var cAddr = address(kAudioDevicePropertyVolumeScalar, kAudioDevicePropertyScopeOutput, 1)
            status = AudioObjectGetPropertyData(device, &cAddr, 0, nil, &size, &volume)
            if status != noErr { volume = 1 }
        }
        var muted = UInt32(0)
        size = UInt32(MemoryLayout<UInt32>.size)
        var mAddr = address(kAudioDevicePropertyMute, kAudioDevicePropertyScopeOutput)
        AudioObjectGetPropertyData(device, &mAddr, 0, nil, &size, &muted)
        return Output(volume: Double(volume), muted: muted != 0, deviceName: deviceName(device))
    }

    /// Set the output volume (used by the HUD slider and scroll-to-change-volume).
    @discardableResult
    public static func setOutputVolume(_ value: Double, device: AudioObjectID = defaultDevice(input: false)) -> Bool {
        var v = Float32(min(1, max(0, value)))
        var addr = address(kAudioHardwareServiceDeviceProperty_VirtualMainVolume, kAudioDevicePropertyScopeOutput)
        let ok = AudioObjectSetPropertyData(device, &addr, 0, nil, UInt32(MemoryLayout<Float32>.size), &v) == noErr
        if ok, v > 0 {
            var mute = UInt32(0)
            var mAddr = address(kAudioDevicePropertyMute, kAudioDevicePropertyScopeOutput)
            AudioObjectSetPropertyData(device, &mAddr, 0, nil, UInt32(MemoryLayout<UInt32>.size), &mute)
        }
        return ok
    }

    @discardableResult
    public static func setMuted(_ muted: Bool, device: AudioObjectID = defaultDevice(input: false)) -> Bool {
        var m = UInt32(muted ? 1 : 0)
        var addr = address(kAudioDevicePropertyMute, kAudioDevicePropertyScopeOutput)
        return AudioObjectSetPropertyData(device, &addr, 0, nil, UInt32(MemoryLayout<UInt32>.size), &m) == noErr
    }

    public static func isRunningSomewhere(_ device: AudioObjectID) -> Bool {
        guard device != 0 else { return false }
        var running = UInt32(0)
        var size = UInt32(MemoryLayout<UInt32>.size)
        var addr = address(kAudioDevicePropertyDeviceIsRunningSomewhere)
        AudioObjectGetPropertyData(device, &addr, 0, nil, &size, &running)
        return running != 0
    }

    public func start() {
        attachOutput()
        attachInput()
        let outBlock: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            self?.attachOutput()
            self?.emitOutput(force: true)
        }
        var outAddr = Self.address(kAudioHardwarePropertyDefaultOutputDevice)
        AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &outAddr, queue, outBlock)
        defaultOutputListener = outBlock

        let inBlock: AudioObjectPropertyListenerBlock = { [weak self] _, _ in self?.attachInput() }
        var inAddr = Self.address(kAudioHardwarePropertyDefaultInputDevice)
        AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &inAddr, queue, inBlock)
        defaultInputListener = inBlock
        last = Self.readOutput(device: outputDevice)
    }

    public func stop() {
        detachOutput()
        detachInput()
        if let b = defaultOutputListener {
            var a = Self.address(kAudioHardwarePropertyDefaultOutputDevice)
            AudioObjectRemovePropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &a, queue, b)
            defaultOutputListener = nil
        }
        if let b = defaultInputListener {
            var a = Self.address(kAudioHardwarePropertyDefaultInputDevice)
            AudioObjectRemovePropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &a, queue, b)
            defaultInputListener = nil
        }
    }

    private func attachOutput() {
        detachOutput()
        outputDevice = Self.defaultDevice(input: false)
        guard outputDevice != 0 else { return }
        let selectors: [(AudioObjectPropertySelector, AudioObjectPropertyElement)] = [
            (kAudioHardwareServiceDeviceProperty_VirtualMainVolume, kAudioObjectPropertyElementMain),
            (kAudioDevicePropertyVolumeScalar, kAudioObjectPropertyElementMain),
            (kAudioDevicePropertyVolumeScalar, 1),
            (kAudioDevicePropertyMute, kAudioObjectPropertyElementMain),
        ]
        for (sel, el) in selectors {
            var addr = Self.address(sel, kAudioDevicePropertyScopeOutput, el)
            let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in self?.emitOutput(force: false) }
            if AudioObjectAddPropertyListenerBlock(outputDevice, &addr, queue, block) == noErr {
                outputListeners.append((addr, block))
            }
        }
    }

    private func detachOutput() {
        for (addr, block) in outputListeners {
            var a = addr
            AudioObjectRemovePropertyListenerBlock(outputDevice, &a, queue, block)
        }
        outputListeners.removeAll()
    }

    private func attachInput() {
        detachInput()
        inputDevice = Self.defaultDevice(input: true)
        guard inputDevice != 0 else { return }
        var addr = Self.address(kAudioDevicePropertyDeviceIsRunningSomewhere)
        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            guard let self else { return }
            self.onMicrophoneInUse?(Self.isRunningSomewhere(self.inputDevice))
        }
        if AudioObjectAddPropertyListenerBlock(inputDevice, &addr, queue, block) == noErr {
            inputListener = block
        }
        onMicrophoneInUse?(Self.isRunningSomewhere(inputDevice))
    }

    private func detachInput() {
        if let b = inputListener {
            var a = Self.address(kAudioDevicePropertyDeviceIsRunningSomewhere)
            AudioObjectRemovePropertyListenerBlock(inputDevice, &a, queue, b)
            inputListener = nil
        }
    }

    private func emitOutput(force: Bool) {
        guard let out = Self.readOutput(device: outputDevice) else { return }
        // Several listeners fire for one key press (virtual + per-channel); report once.
        if !force, let last, abs(last.volume - out.volume) < 0.001, last.muted == out.muted { return }
        last = out
        onOutputChange?(out)
    }
}
