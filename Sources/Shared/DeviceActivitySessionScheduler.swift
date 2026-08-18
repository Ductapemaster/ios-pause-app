import DeviceActivity
import Foundation
import PauseCore

public enum SessionSchedulingError: LocalizedError, Equatable {
    case unrepresentableExpiry

    public var errorDescription: String? {
        switch self {
        case .unrepresentableExpiry:
            "iOS couldn't represent this session's exact expiry. The app remains blocked, and the session was not charged."
        }
    }
}

@MainActor
public final class DeviceActivitySessionScheduler: SessionScheduling {
    typealias CallbackResolver = (DeviceActivitySchedule, Bool) -> Date?
    typealias StartMonitoring = (DeviceActivityName, DeviceActivitySchedule) throws -> Void
    typealias StopMonitoring = (DeviceActivityName) throws -> Void

    private let calendar: Calendar
    private let resolvedCallbackDate: CallbackResolver
    private let startMonitoring: StartMonitoring
    private let stopMonitoring: StopMonitoring

    public convenience init(
        center: DeviceActivityCenter = DeviceActivityCenter(),
        calendar: Calendar = .current
    ) {
        self.init(
            calendar: calendar,
            startMonitoring: { name, schedule in
                try center.startMonitoring(name, during: schedule)
            },
            stopMonitoring: { name in
                center.stopMonitoring([name])
            }
        )
    }

    init(
        calendar: Calendar,
        resolvedCallbackDate: CallbackResolver? = nil,
        startMonitoring: @escaping StartMonitoring,
        stopMonitoring: @escaping StopMonitoring
    ) {
        self.calendar = calendar
        self.resolvedCallbackDate = resolvedCallbackDate ?? Self.defaultCallbackDate
        self.startMonitoring = startMonitoring
        self.stopMonitoring = stopMonitoring
    }

    public func register(ruleID: UUID, startsAt: Date, expiresAt: Date) throws -> String {
        let duration = expiresAt.timeIntervalSince(startsAt)
        guard duration > 0 else {
            throw SessionSchedulingError.unrepresentableExpiry
        }

        let isShortSession = duration < 15 * 60
        let warningMinutes: Int? = isShortSession
            ? 15 - Int((duration / 60).rounded())
            : nil
        let scheduleEnd = warningMinutes.map {
            expiresAt.addingTimeInterval(TimeInterval($0 * 60))
        } ?? expiresAt
        let schedule = DeviceActivitySchedule(
            intervalStart: absoluteComponents(from: startsAt),
            intervalEnd: absoluteComponents(from: scheduleEnd),
            repeats: false,
            warningTime: warningMinutes.map { DateComponents(minute: $0) }
        )

        guard let representedExpiry = resolvedCallbackDate(schedule, isShortSession) else {
            throw SessionSchedulingError.unrepresentableExpiry
        }
        let lateness = representedExpiry.timeIntervalSince(expiresAt)
        guard lateness >= 0, lateness <= 5 else {
            throw SessionSchedulingError.unrepresentableExpiry
        }

        let activityName = SessionActivityName.sessionActivityName(for: ruleID)
        try startMonitoring(DeviceActivityName(activityName), schedule)
        return activityName
    }

    public func stop(activityName: String) throws {
        try stopMonitoring(DeviceActivityName(activityName))
    }

    private func absoluteComponents(from date: Date) -> DateComponents {
        calendar.dateComponents(
            [.calendar, .timeZone, .era, .year, .month, .day, .hour, .minute, .second],
            from: date
        )
    }

    private static func defaultCallbackDate(
        schedule: DeviceActivitySchedule,
        isShortSession: Bool
    ) -> Date? {
        guard let interval = schedule.nextInterval else { return nil }
        if isShortSession, let warningTime = schedule.warningTime {
            let warningSeconds = TimeInterval((warningTime.minute ?? 0) * 60)
            return interval.end.addingTimeInterval(-warningSeconds)
        }
        return interval.end
    }
}
