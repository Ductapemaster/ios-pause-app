import DeviceActivity
import Foundation

/// Registers one repeating daily activity whose interval begins at the reset,
/// so the monitor gets a callback when a logical day turns over.
public struct DailyResetScheduler {
    private let startMonitoring: (DeviceActivityName, DeviceActivitySchedule) throws -> Void

    public init(center: DeviceActivityCenter = DeviceActivityCenter()) {
        startMonitoring = { name, schedule in
            try center.startMonitoring(name, during: schedule)
        }
    }

    init(startMonitoring: @escaping (DeviceActivityName, DeviceActivitySchedule) throws -> Void) {
        self.startMonitoring = startMonitoring
    }

    /// Registers a repeating interval that begins at the reset and ends one
    /// minute before it, so `nextInterval` covers the full day the reset
    /// opens. Measured in the simulator (see
    /// `docs/research/screen-time-platform-evidence.md`): a wrapping
    /// `intervalStart`/`intervalEnd` pair resolves to a ~24-hour
    /// `DateInterval` beginning at the configured start, so a reset away
    /// from midnight is safe to register directly rather than pinned to
    /// `23:59`.
    public func register(resetMinuteOfDay: Int) throws {
        let start = DateComponents(
            hour: resetMinuteOfDay / 60,
            minute: resetMinuteOfDay % 60
        )
        let endMinute = (resetMinuteOfDay + 24 * 60 - 1) % (24 * 60)
        let schedule = DeviceActivitySchedule(
            intervalStart: start,
            intervalEnd: DateComponents(hour: endMinute / 60, minute: endMinute % 60),
            repeats: true
        )
        try startMonitoring(DeviceActivityName(DailyResetActivityName.value), schedule)
    }
}
