import AppKit
import CoreAudio
import CoreMediaIO
import Darwin
import Foundation
import IsletCore

// MARK: - Clipboard

/// Watches the general pasteboard. macOS has no change notification, so this polls
/// `changeCount` (a cheap integer read) with a tolerant timer, and only while enabled.
public final class ClipboardMonitor {
    public var onCopy: ((_ text: String, _ types: [String], _ sourceBundleID: String?) -> Void)?
    private var timer: Timer?
    private var lastChange = NSPasteboard.general.changeCount

    public init() {}
    deinit { stop() }

    public func start(interval: TimeInterval = 0.75) {
        guard timer == nil else { return }
        lastChange = NSPasteboard.general.changeCount
        let t = Timer(timeInterval: interval, repeats: true) { [weak self] _ in self?.poll() }
        t.tolerance = interval / 2
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    public func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func poll() {
        let pb = NSPasteboard.general
        guard pb.changeCount != lastChange else { return }
        lastChange = pb.changeCount
        let types = (pb.types ?? []).map(\.rawValue)
        guard let text = pb.string(forType: .string) else { return }
        onCopy?(text, types, NSWorkspace.shared.frontmostApplication?.bundleIdentifier)
    }

    /// Put text back on the pasteboard (marked so our own monitor skips it).
    public func copy(_ text: String) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)
        lastChange = pb.changeCount
    }
}

// MARK: - Camera in use

/// Reports whether any camera is streaming, via CoreMediaIO property listeners.
/// Reading device state does not require camera permission.
public final class CameraMonitor {
    public var onChange: ((Bool) -> Void)?
    private var devices: [CMIOObjectID] = []
    private var listeners: [(CMIOObjectID, CMIOObjectPropertyListenerBlock)] = []
    private var last: Bool?

    public init() {}
    deinit { stop() }

    static func address(_ selector: Int) -> CMIOObjectPropertyAddress {
        CMIOObjectPropertyAddress(
            mSelector: CMIOObjectPropertySelector(selector),
            mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
            mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain)
        )
    }

    static func allDevices() -> [CMIOObjectID] {
        var addr = address(kCMIOHardwarePropertyDevices)
        var size: UInt32 = 0
        guard CMIOObjectGetPropertyDataSize(CMIOObjectID(kCMIOObjectSystemObject), &addr, 0, nil, &size) == 0, size > 0 else { return [] }
        let count = Int(size) / MemoryLayout<CMIOObjectID>.size
        var ids = [CMIOObjectID](repeating: 0, count: count)
        var used: UInt32 = 0
        guard CMIOObjectGetPropertyData(CMIOObjectID(kCMIOObjectSystemObject), &addr, 0, nil, size, &used, &ids) == 0 else { return [] }
        return ids
    }

    static func isRunning(_ device: CMIOObjectID) -> Bool {
        var addr = address(kCMIODevicePropertyDeviceIsRunningSomewhere)
        var value: UInt32 = 0
        var used: UInt32 = 0
        guard CMIOObjectGetPropertyData(device, &addr, 0, nil, UInt32(MemoryLayout<UInt32>.size), &used, &value) == 0 else { return false }
        return value != 0
    }

    public func start() {
        stop()
        devices = Self.allDevices()
        for d in devices {
            var addr = Self.address(kCMIODevicePropertyDeviceIsRunningSomewhere)
            let block: CMIOObjectPropertyListenerBlock = { [weak self] _, _ in self?.emit() }
            if CMIOObjectAddPropertyListenerBlock(d, &addr, DispatchQueue.main, block) == 0 {
                listeners.append((d, block))
            }
        }
        emit()
    }

    public func stop() {
        for (d, block) in listeners {
            var addr = Self.address(kCMIODevicePropertyDeviceIsRunningSomewhere)
            CMIOObjectRemovePropertyListenerBlock(d, &addr, DispatchQueue.main, block)
        }
        listeners.removeAll()
    }

    private func emit() {
        let running = devices.contains(where: Self.isRunning)
        guard running != last else { return }
        last = running
        onChange?(running)
    }
}

// MARK: - System stats

/// Samples CPU and memory. Only runs while a stats view is on screen.
public final class SystemStatsSampler {
    public var onSample: ((SystemStats) -> Void)?
    private var timer: Timer?
    private var previous: [CPUTicks]?

    public init() {}
    deinit { stop() }

    public func start(interval: TimeInterval = 2) {
        guard timer == nil else { return }
        previous = Self.cpuTicks()
        sample()
        let t = Timer(timeInterval: interval, repeats: true) { [weak self] _ in self?.sample() }
        t.tolerance = interval / 4
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    public func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func sample() {
        let now = Self.cpuTicks()
        let cpu = previous.map { SystemStats.cpuUsage(previous: $0, current: now) } ?? 0
        previous = now
        let (used, total) = Self.memory()
        onSample?(SystemStats(cpu: cpu, memoryUsed: used, memoryTotal: total))
    }

    public static func cpuTicks() -> [CPUTicks] {
        var count: natural_t = 0
        var info: processor_info_array_t?
        var infoCount: mach_msg_type_number_t = 0
        guard host_processor_info(mach_host_self(), PROCESSOR_CPU_LOAD_INFO, &count, &info, &infoCount) == KERN_SUCCESS,
              let info else { return [] }
        defer {
            vm_deallocate(mach_task_self_, vm_address_t(bitPattern: info), vm_size_t(Int(infoCount) * MemoryLayout<integer_t>.stride))
        }
        var result: [CPUTicks] = []
        for i in 0..<Int(count) {
            let base = Int(CPU_STATE_MAX) * i
            result.append(CPUTicks(
                user: UInt64(UInt32(bitPattern: info[base + Int(CPU_STATE_USER)])),
                system: UInt64(UInt32(bitPattern: info[base + Int(CPU_STATE_SYSTEM)])),
                idle: UInt64(UInt32(bitPattern: info[base + Int(CPU_STATE_IDLE)])),
                nice: UInt64(UInt32(bitPattern: info[base + Int(CPU_STATE_NICE)]))
            ))
        }
        return result
    }

    /// (used, total) bytes. "Used" follows Activity Monitor: app + wired + compressed.
    public static func memory() -> (UInt64, UInt64) {
        let total = ProcessInfo.processInfo.physicalMemory
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)
        let kr = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard kr == KERN_SUCCESS else { return (0, total) }
        let page = UInt64(vm_kernel_page_size)
        let app = UInt64(stats.internal_page_count) &- UInt64(stats.purgeable_count)
        let used = (app + UInt64(stats.wire_count) + UInt64(stats.compressor_page_count)) * page
        return (min(used, total), total)
    }
}

// MARK: - Audio route

public extension AudioMonitor {
    /// Whether an output device is Bluetooth (AirPods, headphones, speakers).
    static func isBluetooth(_ device: AudioObjectID) -> Bool {
        var transport = UInt32(0)
        var size = UInt32(MemoryLayout<UInt32>.size)
        var addr = address(kAudioDevicePropertyTransportType)
        guard AudioObjectGetPropertyData(device, &addr, 0, nil, &size, &transport) == noErr else { return false }
        return transport == kAudioDeviceTransportTypeBluetooth || transport == kAudioDeviceTransportTypeBluetoothLE
    }
}
