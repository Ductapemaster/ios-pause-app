import Foundation
import PauseCore

public final class RepositoryRuntimePersistence: RuntimePersisting, @unchecked Sendable {
    private let repository: RuntimeRepository
    private let logicalDay: CalendarDay
    private let now: Date

    public init(
        repository: RuntimeRepository,
        now: Date,
        calendar: Calendar = .current
    ) {
        self.repository = repository
        self.now = now
        logicalDay = CalendarDay(date: now, calendar: calendar)
    }

    public func reserve(ruleID: UUID, activityName: String, expiresAt: Date) throws {
        _ = try repository.update(ruleID: ruleID) { runtime in
            runtime.rollOver(to: logicalDay)
            runtime.clearExpiredSession(at: now)
            try runtime.reserve(activityName: activityName, expiresAt: expiresAt)
        }
    }

    public func activate(ruleID: UUID) throws {
        _ = try repository.update(ruleID: ruleID) { runtime in
            try runtime.activateReservedSession()
        }
    }

    public func rollBack(ruleID: UUID) throws {
        _ = try repository.update(ruleID: ruleID) { runtime in
            try runtime.rollBackReservedSession()
        }
    }
}

public final class ConfigurationShieldController: ShieldControlling, @unchecked Sendable {
    private let configuration: ConfigurationDocument
    private let runtimeRepository: RuntimeRepository
    private let reconciler: ShieldReconciler
    private let now: Date

    public init(
        configuration: ConfigurationDocument,
        runtimeRepository: RuntimeRepository,
        reconciler: ShieldReconciler,
        now: Date
    ) {
        self.configuration = configuration
        self.runtimeRepository = runtimeRepository
        self.reconciler = reconciler
        self.now = now
    }

    public func unshield(ruleID: UUID) throws {
        try reconciler.unshield(ruleID: ruleID, configuration: configuration)
    }

    public func reconcile() throws {
        try reconciler.reconcile(
            configuration: configuration,
            runtimeRepository: runtimeRepository,
            now: now
        )
    }
}
