import CoreAudio
import Foundation

/// Which apps are using the microphone right now, from CoreAudio's per-process objects
/// (macOS 14+). No permission is needed and nothing is polled: listeners fire when the
/// process list changes or when any process starts or stops audio input.
public final class MicUsageMonitor {
    /// Called on the main queue with the bundle ids currently recording.
    public var onChange: ((Set<String>) -> Void)?
    private var processListener: AudioObjectPropertyListenerBlock?
    private var inputListeners: [AudioObjectID: AudioObjectPropertyListenerBlock] = [:]
    private var last: Set<String> = []

    public init() {}
    deinit { stop() }

    static func address(_ selector: AudioObjectPropertySelector) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
    }

    public static func processObjects() -> [AudioObjectID] {
        var a = address(kAudioHardwarePropertyProcessObjectList)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &a, 0, nil, &size) == noErr, size > 0 else { return [] }
        var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &a, 0, nil, &size, &ids) == noErr else { return [] }
        return ids
    }

    public static func bundleID(of process: AudioObjectID) -> String? {
        var a = address(kAudioProcessPropertyBundleID)
        var s: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(process, &a, 0, nil, &size, &s) == noErr, let s else { return nil }
        let v = s.takeRetainedValue() as String
        return v.isEmpty ? nil : v
    }

    public static func isRecording(_ process: AudioObjectID) -> Bool {
        var a = address(kAudioProcessPropertyIsRunningInput)
        var v: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        return AudioObjectGetPropertyData(process, &a, 0, nil, &size, &v) == noErr && v != 0
    }

    /// Bundle ids of every process currently capturing audio.
    public static func recordingApps() -> Set<String> {
        Set(processObjects().filter(isRecording).compactMap(bundleID(of:)))
    }

    public func start() {
        guard processListener == nil else { return }
        var a = Self.address(kAudioHardwarePropertyProcessObjectList)
        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            self?.attachProcessListeners()
            self?.emit()
        }
        AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &a, .main, block)
        processListener = block
        attachProcessListeners()
        emit(force: true)
    }

    public func stop() {
        if let block = processListener {
            var a = Self.address(kAudioHardwarePropertyProcessObjectList)
            AudioObjectRemovePropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &a, .main, block)
            processListener = nil
        }
        for (id, block) in inputListeners {
            var a = Self.address(kAudioProcessPropertyIsRunningInput)
            AudioObjectRemovePropertyListenerBlock(id, &a, .main, block)
        }
        inputListeners.removeAll()
    }

    private func attachProcessListeners() {
        let current = Set(Self.processObjects())
        for (id, block) in inputListeners where !current.contains(id) {
            var a = Self.address(kAudioProcessPropertyIsRunningInput)
            AudioObjectRemovePropertyListenerBlock(id, &a, .main, block)
            inputListeners[id] = nil
        }
        for id in current where inputListeners[id] == nil {
            var a = Self.address(kAudioProcessPropertyIsRunningInput)
            let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in self?.emit() }
            if AudioObjectAddPropertyListenerBlock(id, &a, .main, block) == noErr {
                inputListeners[id] = block
            }
        }
    }

    private func emit(force: Bool = false) {
        let now = Self.recordingApps()
        guard force || now != last else { return }
        last = now
        onChange?(now)
    }
}
