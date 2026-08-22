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

    public func register() throws {
        let schedule = DeviceActivitySchedule(
            intervalStart: DateComponents(hour: 0, minute: 0),
            intervalEnd: DateComponents(hour: 23, minute: 59),
            repeats: true
        )
        try startMonitoring(DeviceActivityName(DailyResetActivityName.value), schedule)
    }
}
