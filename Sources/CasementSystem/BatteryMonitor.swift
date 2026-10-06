import Foundation
import IOKit.ps
import CasementCore

/// Battery state from IOKit power-source notifications (no polling, no permissions).
public final class BatteryMonitor {
    public var onChange: ((BatteryState) -> Void)?
    private var runLoopSource: CFRunLoopSource?
    private var lowPowerObserver: NSObjectProtocol?

    public init() {}

    deinit { stop() }

    public func start() {
        guard runLoopSource == nil else { return }
        let context = Unmanaged.passUnretained(self).toOpaque()
        if let source = IOPSNotificationCreateRunLoopSource({ ctx in
            guard let ctx else { return }
            let monitor = Unmanaged<BatteryMonitor>.fromOpaque(ctx).takeUnretainedValue()
            monitor.emit()
        }, context)?.takeRetainedValue() {
            runLoopSource = source
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .defaultMode)
        }
        lowPowerObserver = NotificationCenter.default.addObserver(
            forName: .NSProcessInfoPowerStateDidChange, object: nil, queue: .main
        ) { [weak self] _ in self?.emit() }
        emit()
    }

    public func stop() {
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .defaultMode)
            runLoopSource = nil
        }
        if let o = lowPowerObserver {
            NotificationCenter.default.removeObserver(o)
            lowPowerObserver = nil
        }
    }

    private func emit() {
        guard let state = Self.read() else { return }
        onChange?(state)
    }

    /// Current internal battery state, or nil on machines without a battery.
    public static func read() -> BatteryState? {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else { return nil }
        for ps in list {
            guard let desc = IOPSGetPowerSourceDescription(info, ps)?.takeUnretainedValue() as? [String: Any],
                  var s = parse(desc, lowPowerMode: ProcessInfo.processInfo.isLowPowerModeEnabled) else { continue }
            if s.isPluggedIn {
                s.adapterWatts = (IOPSCopyExternalPowerAdapterDetails()?.takeRetainedValue() as? [String: Any]).flatMap(adapterWatts)
            } else if s.minutesRemaining == nil {
                // The description sometimes lacks an estimate that the system-wide one has.
                let estimate = IOPSGetTimeRemainingEstimate()
                if estimate > 0 { s.minutesRemaining = Int((estimate / 60).rounded()) }
            }
            return s
        }
        return nil
    }

    /// Rated watts from `IOPSCopyExternalPowerAdapterDetails()`. Pure, for tests.
    public static func adapterWatts(_ details: [String: Any]) -> Int? {
        let raw = details[kIOPSPowerAdapterWattsKey]
        let watts = (raw as? Int) ?? (raw as? NSNumber)?.intValue
        guard let watts, watts > 0 else { return nil }
        return watts
    }

    /// Convert an IOPS power-source description into `BatteryState`. Pure, for tests.
    public static func parse(_ d: [String: Any], lowPowerMode: Bool = false) -> BatteryState? {
        guard (d[kIOPSTypeKey] as? String) == kIOPSInternalBatteryType else { return nil }
        guard let current = d[kIOPSCurrentCapacityKey] as? Int else { return nil }
        let max = (d[kIOPSMaxCapacityKey] as? Int).flatMap { $0 > 0 ? $0 : nil } ?? 100
        let level = Int((Double(current) / Double(max) * 100).rounded())
        let plugged = (d[kIOPSPowerSourceStateKey] as? String) == kIOPSACPowerValue
        let charging = (d[kIOPSIsChargingKey] as? Bool) ?? false
        // -1 means "still calculating".
        let minutes: Int? = {
            let key = charging ? kIOPSTimeToFullChargeKey : kIOPSTimeToEmptyKey
            guard let v = d[key] as? Int, v > 0 else { return nil }
            return v
        }()
        return BatteryState(level: level, isCharging: charging, isPluggedIn: plugged, minutesRemaining: minutes, lowPowerMode: lowPowerMode)
    }
}
