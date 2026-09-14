import Foundation
import IOKit.ps

struct BatterySnapshot: Equatable {
    let percent: Int
    let onAC: Bool
}

/// Thin IOKit wrapper over the system power sources. Emits a BatterySnapshot
/// whenever the power state changes (charge or AC/battery). Event-driven via
/// IOPSNotificationCreateRunLoopSource — no polling. Machines without a battery
/// report no snapshot.
final class BatteryMonitor {

    /// Called on the main run loop whenever the power state changes, and once
    /// immediately on `start()`.
    var onChange: ((BatterySnapshot) -> Void)?

    private var runLoopSource: CFRunLoopSource?

    func start() {
        guard runLoopSource == nil else { return }

        let context = Unmanaged.passUnretained(self).toOpaque()
        guard let source = IOPSNotificationCreateRunLoopSource({ ctx in
            guard let ctx else { return }
            let monitor = Unmanaged<BatteryMonitor>.fromOpaque(ctx).takeUnretainedValue()
            monitor.emit()
        }, context)?.takeRetainedValue() else {
            return
        }

        runLoopSource = source
        // Common modes, for the same reason every timer in the app uses them: in
        // the default mode alone the source stops being served while a menu is
        // tracking or an alert is up. IOKit reports power *changes*, not levels,
        // so a charger unplugged in that window is not delivered late — it is
        // never delivered at all.
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        emit()
    }

    func currentSnapshot() -> BatterySnapshot? {
        let blob = IOPSCopyPowerSourcesInfo().takeRetainedValue()
        let sources = IOPSCopyPowerSourcesList(blob).takeRetainedValue() as [CFTypeRef]

        for source in sources {
            guard let desc = IOPSGetPowerSourceDescription(blob, source)?
                .takeUnretainedValue() as? [String: Any] else { continue }
            guard let type = desc[kIOPSTypeKey] as? String,
                  type == kIOPSInternalBatteryType else { continue }
            guard let current = desc[kIOPSCurrentCapacityKey] as? Int,
                  let maximum = desc[kIOPSMaxCapacityKey] as? Int,
                  maximum > 0 else { continue }

            let state = desc[kIOPSPowerSourceStateKey] as? String
            let onAC = (state == kIOPSACPowerValue)
            let percent = Int((Double(current) / Double(maximum)) * 100.0)
            return BatterySnapshot(percent: percent, onAC: onAC)
        }
        return nil
    }

    private func emit() {
        if let snapshot = currentSnapshot() {
            onChange?(snapshot)
        }
    }
}
