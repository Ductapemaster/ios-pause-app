import Foundation
import PauseCore

public protocol SessionScheduling: Sendable {
    func register(ruleID: UUID, startsAt: Date, expiresAt: Date) throws -> String
    func stop(activityName: String) throws
}

public protocol RuntimePersisting: Sendable {
    func reserve(ruleID: UUID, activityName: String, expiresAt: Date) throws
    func activate(ruleID: UUID) throws
    func rollBack(ruleID: UUID) throws
}

public protocol ShieldControlling: Sendable {
    func unshield(ruleID: UUID) throws
    func reconcile() throws
}

public protocol TargetLaunching: Sendable {
    func hasAutomaticRoute(ruleID: UUID) -> Bool
    func open(ruleID: UUID) async -> Bool
}

public enum GrantResult: Equatable, Sendable {
    case openedAutomatically(expiresAt: Date)
    case readyForManualReturn(expiresAt: Date)
}

public enum SessionGrantError: LocalizedError, Equatable, Sendable {
    case automaticLaunchFailed

    public var errorDescription: String? {
        switch self {
        case .automaticLaunchFailed:
            "Pause couldn't return to this app. The session was not charged, and the app remains blocked."
        }
    }
}

public struct SessionGrantFailure: LocalizedError, @unchecked Sendable {
    public let primaryError: any Error
    public let repairErrors: [any Error]

    public init(primaryError: any Error, repairErrors: [any Error] = []) {
        self.primaryError = primaryError
        self.repairErrors = repairErrors
    }

    public var errorDescription: String? {
        let primary = primaryError.localizedDescription
        guard !repairErrors.isEmpty else { return primary }
        let repairs = repairErrors.map(\.localizedDescription).joined(separator: " ")
        return "\(primary) Pause also couldn't finish repairing the failed grant: \(repairs)"
    }
}

public struct SessionGrantCoordinator: Sendable {
    private let scheduler: any SessionScheduling
    private let runtime: any RuntimePersisting
    private let shield: any ShieldControlling
    private let launcher: any TargetLaunching

    public init(
        scheduler: any SessionScheduling,
        runtime: any RuntimePersisting,
        shield: any ShieldControlling,
        launcher: any TargetLaunching
    ) {
        self.scheduler = scheduler
        self.runtime = runtime
        self.shield = shield
        self.launcher = launcher
    }

    public func grant(rule: AppRule, now: Date) async throws -> GrantResult {
        let expiresAt = now.addingTimeInterval(Double(rule.sessionLengthMinutes) * 60)
        let activityName: String

        do {
            activityName = try scheduler.register(
                ruleID: rule.id,
                startsAt: now,
                expiresAt: expiresAt
            )
        } catch {
            throw SessionGrantFailure(primaryError: error)
        }

        do {
            try runtime.reserve(
                ruleID: rule.id,
                activityName: activityName,
                expiresAt: expiresAt
            )
        } catch {
            throw SessionGrantFailure(
                primaryError: error,
                repairErrors: collectRepairErrors {
                    try scheduler.stop(activityName: activityName)
                }
            )
        }

        do {
            try shield.unshield(ruleID: rule.id)
        } catch {
            throw SessionGrantFailure(
                primaryError: error,
                repairErrors: repairFailedGrant(ruleID: rule.id, activityName: activityName)
            )
        }

        guard launcher.hasAutomaticRoute(ruleID: rule.id) else {
            do {
                try runtime.activate(ruleID: rule.id)
                return .readyForManualReturn(expiresAt: expiresAt)
            } catch {
                // The provisional session remains charged and recoverable. Rolling it back
                // here would grant untracked access after the shield has already moved.
                throw SessionGrantFailure(primaryError: error)
            }
        }

        guard await launcher.open(ruleID: rule.id) else {
            let primary = SessionGrantError.automaticLaunchFailed
            throw SessionGrantFailure(
                primaryError: primary,
                repairErrors: repairFailedGrant(ruleID: rule.id, activityName: activityName)
            )
        }

        do {
            try runtime.activate(ruleID: rule.id)
            return .openedAutomatically(expiresAt: expiresAt)
        } catch {
            // Opening succeeded. The provisional record is deliberately preserved so
            // launch recovery charges it instead of accidentally granting free access.
            throw SessionGrantFailure(primaryError: error)
        }
    }

    private func repairFailedGrant(ruleID: UUID, activityName: String) -> [any Error] {
        var errors: [any Error] = []
        errors.append(contentsOf: collectRepairErrors { try runtime.rollBack(ruleID: ruleID) })
        errors.append(contentsOf: collectRepairErrors { try scheduler.stop(activityName: activityName) })
        errors.append(contentsOf: collectRepairErrors { try shield.reconcile() })
        return errors
    }

    private func collectRepairErrors(_ operation: () throws -> Void) -> [any Error] {
        do {
            try operation()
            return []
        } catch {
            return [error]
        }
    }
}
