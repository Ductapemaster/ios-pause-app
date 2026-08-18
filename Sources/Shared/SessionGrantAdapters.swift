import Foundation
import PauseCore

@MainActor
public final class RepositoryRuntimePersistence: RuntimePersisting {
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

@MainActor
public final class ConfigurationShieldController: ShieldControlling {
    private let configuration: ConfigurationDocument
    private let reconciler: ShieldReconciler
    private let failedGrantBlockStore: any FailedGrantBlockStoring

    public init(
        configuration: ConfigurationDocument,
        reconciler: ShieldReconciler,
        failedGrantBlockStore: any FailedGrantBlockStoring
    ) {
        self.configuration = configuration
        self.reconciler = reconciler
        self.failedGrantBlockStore = failedGrantBlockStore
    }

    public func unshield(ruleID: UUID) throws {
        try reconciler.unshield(ruleID: ruleID, configuration: configuration)
    }

    public func forceShield(ruleID: UUID) throws -> ForceShieldOutcome {
        try reconciler.forceShield(ruleID: ruleID, configuration: configuration)
        do {
            try failedGrantBlockStore.add(ruleID: ruleID)
            return .durable
        } catch {
            return .immediateOnly(error)
        }
    }
}
