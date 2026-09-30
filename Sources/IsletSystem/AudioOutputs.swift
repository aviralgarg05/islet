import AudioToolbox
import CoreAudio
import Foundation

/// How an audio device is connected, from `kAudioDevicePropertyTransportType`.
public enum AudioTransport: String, Sendable, CaseIterable {
    case builtIn, bluetooth, usb, hdmi, displayPort, airPlay, thunderbolt, virtual, aggregate, other

    public init(code: UInt32) {
        switch code {
        case kAudioDeviceTransportTypeBuiltIn: self = .builtIn
        case kAudioDeviceTransportTypeBluetooth, kAudioDeviceTransportTypeBluetoothLE: self = .bluetooth
        case kAudioDeviceTransportTypeUSB: self = .usb
        case kAudioDeviceTransportTypeHDMI: self = .hdmi
        case kAudioDeviceTransportTypeDisplayPort: self = .displayPort
        case kAudioDeviceTransportTypeAirPlay: self = .airPlay
        case kAudioDeviceTransportTypeThunderbolt: self = .thunderbolt
        case kAudioDeviceTransportTypeVirtual: self = .virtual
        case kAudioDeviceTransportTypeAggregate, kAudioDeviceTransportTypeAutoAggregate: self = .aggregate
        default: self = .other
        }
    }
}

/// An output device the user can pick.
public struct AudioOutputDevice: Identifiable, Equatable, Sendable {
    public var id: UInt32
    public var uid: String
    public var name: String
    public var transport: AudioTransport

    public init(id: UInt32, uid: String, name: String, transport: AudioTransport) {
        self.id = id
        self.uid = uid
        self.name = name
        self.transport = transport
    }
}

/// Lists output devices and switches the default output, with public CoreAudio calls
/// (no permission needed).
public enum AudioOutputs {
    private static func address(_ selector: AudioObjectPropertySelector, _ scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
    }

    /// Devices that can play sound and can be the default output, in the system's order.
    public static func all() -> [AudioOutputDevice] {
        var addr = address(kAudioHardwarePropertyDevices)
        var size: UInt32 = 0
        let system = AudioObjectID(kAudioObjectSystemObject)
        guard AudioObjectGetPropertyDataSize(system, &addr, 0, nil, &size) == noErr, size > 0 else { return [] }
        var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(system, &addr, 0, nil, &size, &ids) == noErr else { return [] }
        return ids.compactMap(device)
    }

    static func device(_ id: AudioObjectID) -> AudioOutputDevice? {
        guard hasOutput(id), uint32(id, kAudioDevicePropertyIsHidden) != 1,
              uint32(id, kAudioDevicePropertyDeviceCanBeDefaultDevice, kAudioDevicePropertyScopeOutput) != 0,
              let name = string(id, kAudioObjectPropertyName) else { return nil }
        return AudioOutputDevice(
            id: id, uid: string(id, kAudioDevicePropertyDeviceUID) ?? name, name: name,
            transport: AudioTransport(code: uint32(id, kAudioDevicePropertyTransportType) ?? 0)
        )
    }

    public static func defaultID() -> UInt32 {
        var id = AudioObjectID(0)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        var addr = address(kAudioHardwarePropertyDefaultOutputDevice)
        AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &id)
        return id
    }

    /// Make `id` the default output (what Sound settings and the menu bar's Sound menu change).
    @discardableResult
    public static func setDefault(_ id: UInt32) -> Bool {
        var device = AudioObjectID(id)
        var addr = address(kAudioHardwarePropertyDefaultOutputDevice)
        return AudioObjectSetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil,
                                          UInt32(MemoryLayout<AudioObjectID>.size), &device) == noErr
    }

    private static func hasOutput(_ id: AudioObjectID) -> Bool {
        var addr = address(kAudioDevicePropertyStreams, kAudioDevicePropertyScopeOutput)
        var size: UInt32 = 0
        return AudioObjectGetPropertyDataSize(id, &addr, 0, nil, &size) == noErr && size > 0
    }

    private static func uint32(_ id: AudioObjectID, _ selector: AudioObjectPropertySelector,
                               _ scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> UInt32? {
        var addr = address(selector, scope)
        guard AudioObjectHasProperty(id, &addr) else { return nil }
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(id, &addr, 0, nil, &size, &value) == noErr else { return nil }
        return value
    }

    private static func string(_ id: AudioObjectID, _ selector: AudioObjectPropertySelector) -> String? {
        var addr = address(selector)
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(id, &addr, 0, nil, &size, &value) == noErr, let v = value else { return nil }
        return v.takeRetainedValue() as String
    }
}

/// Reports changes to the device list, the default output and its volume or mute state.
/// Run it only while something on screen shows them (listeners, no polling).
public final class AudioOutputWatcher {
    public var onChange: (() -> Void)?
    private var systemListeners: [(AudioObjectPropertyAddress, AudioObjectPropertyListenerBlock)] = []
    private var deviceListeners: [(AudioObjectPropertyAddress, AudioObjectPropertyListenerBlock)] = []
    private var device: AudioObjectID = 0

    public init() {}
    deinit { stop() }

    public var isRunning: Bool { !systemListeners.isEmpty }

    public func start() {
        guard systemListeners.isEmpty else { return }
        for selector in [kAudioHardwarePropertyDevices, kAudioHardwarePropertyDefaultOutputDevice] {
            var addr = AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
            let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
                self?.attachDevice()
                self?.onChange?()
            }
            if AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &addr, .main, block) == noErr {
                systemListeners.append((addr, block))
            }
        }
        attachDevice()
    }

    public func stop() {
        detachDevice()
        for (addr, block) in systemListeners {
            var a = addr
            AudioObjectRemovePropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &a, .main, block)
        }
        systemListeners.removeAll()
    }

    private func attachDevice() {
        detachDevice()
        device = AudioOutputs.defaultID()
        guard device != 0 else { return }
        for selector in [kAudioHardwareServiceDeviceProperty_VirtualMainVolume, kAudioDevicePropertyMute] {
            var addr = AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioDevicePropertyScopeOutput, mElement: kAudioObjectPropertyElementMain)
            let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in self?.onChange?() }
            if AudioObjectAddPropertyListenerBlock(device, &addr, .main, block) == noErr {
                deviceListeners.append((addr, block))
            }
        }
    }

    private func detachDevice() {
        for (addr, block) in deviceListeners {
            var a = addr
            AudioObjectRemovePropertyListenerBlock(device, &a, .main, block)
        }
        deviceListeners.removeAll()
    }
}
