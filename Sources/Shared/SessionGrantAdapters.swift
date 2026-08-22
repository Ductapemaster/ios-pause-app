import Foundation
import PauseCore

extension AppGroupFileLock: SessionGrantLocking {}

/// Charges a reserved session to the allowance day the file defines.
///
/// It takes the configuration file rather than a day so that the day cannot be
/// supplied wrongly: a session reserved at 02:00 under a 06:00 reset belongs to
/// the day that began at yesterday's reset, and the civil date would renew the
/// count four hours early.
@MainActor
public final class RepositoryRuntimePersistence: RuntimePersisting {
    private let repository: RuntimeRepository
    private let logicalDay: CalendarDay
    private let now: Date

    public init(
        repository: RuntimeRepository,
        configurationFile: ConfigurationFile,
        now: Date,
        calendar: Calendar = .current
    ) {
        self.repository = repository
        self.now = now
        logicalDay = configurationFile.logicalDay(at: now, calendar: calendar)
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
    private let stateLock: AppGroupFileLock?

    public init(
        configuration: ConfigurationDocument,
        reconciler: ShieldReconciler,
        failedGrantBlockStore: any FailedGrantBlockStoring,
        stateLock: AppGroupFileLock? = nil
    ) {
        self.configuration = configuration
        self.reconciler = reconciler
        self.failedGrantBlockStore = failedGrantBlockStore
        self.stateLock = stateLock
    }

    public func unshield(ruleID: UUID) throws {
        try reconciler.unshield(ruleID: ruleID, configuration: configuration)
    }

    public func shield(ruleID: UUID) throws {
        try reconciler.forceShield(ruleID: ruleID, configuration: configuration)
    }

    public func forceShieldForFailedGrant(ruleID: UUID) throws -> ForceShieldOutcome {
        if let stateLock {
            return try stateLock.withLock { try forceShieldForFailedGrantUnlocked(ruleID: ruleID) }
        }
        return try forceShieldForFailedGrantUnlocked(ruleID: ruleID)
    }

    private func forceShieldForFailedGrantUnlocked(ruleID: UUID) throws -> ForceShieldOutcome {
        let applicationToken = try reconciler.applicationToken(
            ruleID: ruleID,
            configuration: configuration
        )
        var persistenceError: (any Error)?
        do {
            try failedGrantBlockStore.add(ruleID: ruleID)
        } catch {
            persistenceError = error
        }
        try reconciler.forceShield(applicationToken: applicationToken)
        if let persistenceError {
            return .immediateOnly(persistenceError)
        }
        return .durable
    }
}
