import Foundation
import IOKit.ps

/// Watches the battery and reports plug/unplug events and low-battery moments.
/// Public IOKit API throughout; no extra permission needed.
@MainActor
final class BatteryMonitor: ObservableObject {
    struct Snapshot: Equatable {
        var percent: Int
        var isCharging: Bool
        var isPlugged: Bool
        /// Minutes remaining, 0 when unknown.
        var minutes: Int
    }

    @Published private(set) var snapshot: Snapshot?

    /// Charger connected or disconnected, or the battery got critically low.
    var onEvent: ((Snapshot) -> Void)?

    private var source: CFRunLoopSource?
    private var lastPlugged: Bool?
    private var lowBatteryAnnounced = false

    func start() {
        refresh()
        let context = Unmanaged.passUnretained(self).toOpaque()
        guard let source = IOPSNotificationCreateRunLoopSource({ pointer in
            guard let pointer else { return }
            let monitor = Unmanaged<BatteryMonitor>.fromOpaque(pointer).takeUnretainedValue()
            MainActor.assumeIsolated { monitor.refresh() }
        }, context)?.takeRetainedValue() else { return }
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .defaultMode)
        self.source = source
    }

    private func refresh() {
        guard let current = read() else { return }
        let previous = snapshot
        snapshot = current

        // Don't alert on the first read; just record the starting state.
        guard let wasPlugged = lastPlugged else {
            lastPlugged = current.isPlugged
            return
        }
        lastPlugged = current.isPlugged

        if wasPlugged != current.isPlugged {
            lowBatteryAnnounced = current.isPlugged ? false : lowBatteryAnnounced
            onEvent?(current)
            return
        }

        // Warn once when it drops below 20%.
        if !current.isPlugged, current.percent <= 20, !lowBatteryAnnounced {
            lowBatteryAnnounced = true
            onEvent?(current)
        } else if current.percent > 25 {
            lowBatteryAnnounced = false
        }
        _ = previous
    }

    /// One-shot read for diagnostics.
    func probe() -> Snapshot? { read() }

    private func read() -> Snapshot? {
        guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef]
        else { return nil }

        for item in list {
            guard let info = IOPSGetPowerSourceDescription(blob, item)?.takeUnretainedValue() as? [String: Any],
                  let capacity = info[kIOPSCurrentCapacityKey] as? Int,
                  let maximum = info[kIOPSMaxCapacityKey] as? Int, maximum > 0
            else { continue }

            let charging = info[kIOPSIsChargingKey] as? Bool ?? false
            let plugged = (info[kIOPSPowerSourceStateKey] as? String) == kIOPSACPowerValue
            let remaining = (charging ? info[kIOPSTimeToFullChargeKey] : info[kIOPSTimeToEmptyKey]) as? Int ?? -1

            return Snapshot(
                percent: Int((Double(capacity) / Double(maximum) * 100).rounded()),
                isCharging: charging,
                isPlugged: plugged,
                minutes: max(0, remaining)
            )
        }
        return nil
    }
}
