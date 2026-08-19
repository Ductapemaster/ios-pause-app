import Foundation
import PauseCore

@MainActor
public protocol SessionScheduling {
    func register(ruleID: UUID, startsAt: Date, expiresAt: Date) throws -> String
    func stop(activityName: String) throws
}

@MainActor
public protocol RuntimePersisting {
    func reserve(ruleID: UUID, activityName: String, expiresAt: Date) throws
    func activate(ruleID: UUID) throws
    func rollBack(ruleID: UUID) throws
}

@MainActor
public protocol ShieldControlling {
    func unshield(ruleID: UUID) throws
    func shield(ruleID: UUID) throws
    func forceShieldForFailedGrant(ruleID: UUID) throws -> ForceShieldOutcome
}

@MainActor
public protocol TargetLaunching {
    func hasAutomaticRoute(ruleID: UUID) -> Bool
    func open(ruleID: UUID) async -> Bool
}

@MainActor
public protocol SessionGrantLocking {
    func withLock<T>(_ operation: () throws -> T) throws -> T
}

public enum GrantResult: Equatable {
    case openedAutomatically(expiresAt: Date)
    case readyForManualReturn(expiresAt: Date)
}

public enum SessionGrantError: LocalizedError, Equatable {
    case automaticLaunchFailed

    public var errorDescription: String? {
        switch self {
        case .automaticLaunchFailed:
            "Pause couldn't return to this app."
        }
    }
}

public enum SessionChargeState: Equatable, Sendable {
    case notCharged
    case charged
    case unknown
}

public enum GrantShieldState: Equatable, Sendable {
    case blocked
    case blockedDurabilityUnknown
    case unblocked
    case unknown
}

public enum ForceShieldOutcome {
    case durable
    case immediateOnly(any Error)

    public var isDurable: Bool {
        if case .durable = self { return true }
        return false
    }

    public var persistenceError: (any Error)? {
        if case let .immediateOnly(error) = self { return error }
        return nil
    }
}

public enum SessionGrantRepairStep: String, Equatable, Sendable {
    case acquireStateLock
    case rollBackRuntime
    case stopMonitoring
    case persistFailedGrantBlock
    case forceShield

    fileprivate var description: String {
        switch self {
        case .acquireStateLock: "lock shared app state"
        case .rollBackRuntime: "roll back session state"
        case .stopMonitoring: "stop expiry monitoring"
        case .persistFailedGrantBlock: "save the failed-session block"
        case .forceShield: "block the app again"
        }
    }
}

public struct SessionGrantRepairFailure: Sendable {
    public let step: SessionGrantRepairStep
    public let underlyingError: any Error

    public init(step: SessionGrantRepairStep, underlyingError: any Error) {
        self.step = step
        self.underlyingError = underlyingError
    }
}

public struct SessionGrantFailure: LocalizedError {
    public let primaryError: any Error
    public let repairErrors: [SessionGrantRepairFailure]
    public let chargeState: SessionChargeState
    public let shieldState: GrantShieldState

    public init(
        primaryError: any Error,
        repairErrors: [SessionGrantRepairFailure] = [],
        chargeState: SessionChargeState,
        shieldState: GrantShieldState
    ) {
        self.primaryError = primaryError
        self.repairErrors = repairErrors
        self.chargeState = chargeState
        self.shieldState = shieldState
    }

    public var errorDescription: String? {
        var parts = [primaryError.localizedDescription, stateDescription]
        if !repairErrors.isEmpty {
            let repairs = repairErrors.map { failure in
                "Pause couldn't \(failure.step.description): \(failure.underlyingError.localizedDescription)"
            }
            parts.append(repairs.joined(separator: " "))
        }
        return parts.joined(separator: " ")
    }

    private var stateDescription: String {
        let charge: String
        switch chargeState {
        case .notCharged: charge = "The session was not charged."
        case .charged: charge = "The provisional session remains charged."
        case .unknown: charge = "Pause couldn't confirm whether the session was charged."
        }

        let shield: String
        switch shieldState {
        case .blocked: shield = "The app is blocked."
        case .blockedDurabilityUnknown:
            shield = "The app is blocked now, but Pause couldn't guarantee that future reconciliation will keep it blocked."
        case .unblocked: shield = "The app remains available until the recorded expiry."
        case .unknown: shield = "Pause couldn't confirm whether the app was blocked."
        }
        return "\(charge) \(shield)"
    }
}

@MainActor
public struct SessionGrantCoordinator {
    private let scheduler: any SessionScheduling
    private let runtime: any RuntimePersisting
    private let shield: any ShieldControlling
    private let launcher: any TargetLaunching
    private let lock: (any SessionGrantLocking)?

    public init(
        scheduler: any SessionScheduling,
        runtime: any RuntimePersisting,
        shield: any ShieldControlling,
        launcher: any TargetLaunching,
        lock: (any SessionGrantLocking)? = nil
    ) {
        self.scheduler = scheduler
        self.runtime = runtime
        self.shield = shield
        self.launcher = launcher
        self.lock = lock
    }

    public func grant(rule: AppRule, now: Date) async throws -> GrantResult {
        let rawExpiry = now.addingTimeInterval(Double(rule.sessionLengthMinutes) * 60)
        let expiresAt = Date(
            timeIntervalSinceReferenceDate: ceil(rawExpiry.timeIntervalSinceReferenceDate)
        )
        let activityName: String
        do {
            activityName = try withPreparationLock {
                let activityName: String
                do {
                    activityName = try scheduler.register(
                        ruleID: rule.id,
                        startsAt: now,
                        expiresAt: expiresAt
                    )
                } catch {
                    throw SessionGrantFailure(
                        primaryError: error,
                        chargeState: .notCharged,
                        shieldState: .blocked
                    )
                }

                do {
                    try runtime.reserve(
                        ruleID: rule.id,
                        activityName: activityName,
                        expiresAt: expiresAt
                    )
                } catch {
                    let repairErrors = collectRepairFailure(step: .stopMonitoring) {
                        try scheduler.stop(activityName: activityName)
                    }
                    throw SessionGrantFailure(
                        primaryError: error,
                        repairErrors: repairErrors,
                        chargeState: .notCharged,
                        shieldState: .blocked
                    )
                }

                do {
                    try shield.unshield(ruleID: rule.id)
                } catch {
                    throw repairedFailureUnlocked(
                        primaryError: error,
                        ruleID: rule.id,
                        activityName: activityName
                    )
                }
                return activityName
            }
        } catch let failure as SessionGrantFailure {
            throw failure
        } catch {
            throw SessionGrantFailure(
                primaryError: error,
                chargeState: .notCharged,
                shieldState: .blocked
            )
        }

        guard launcher.hasAutomaticRoute(ruleID: rule.id) else {
            do {
                try runtime.activate(ruleID: rule.id)
                return .readyForManualReturn(expiresAt: expiresAt)
            } catch {
                throw SessionGrantFailure(
                    primaryError: error,
                    chargeState: .charged,
                    shieldState: .unblocked
                )
            }
        }

        guard await launcher.open(ruleID: rule.id) else {
            throw repairedFailure(
                primaryError: SessionGrantError.automaticLaunchFailed,
                ruleID: rule.id,
                activityName: activityName
            )
        }

        do {
            try runtime.activate(ruleID: rule.id)
            return .openedAutomatically(expiresAt: expiresAt)
        } catch {
            throw SessionGrantFailure(
                primaryError: error,
                chargeState: .charged,
                shieldState: .unblocked
            )
        }
    }

    private func repairedFailure(
        primaryError: any Error,
        ruleID: UUID,
        activityName: String
    ) -> SessionGrantFailure {
        do {
            return try withPreparationLock {
                repairedFailureUnlocked(
                    primaryError: primaryError,
                    ruleID: ruleID,
                    activityName: activityName
                )
            }
        } catch {
            return SessionGrantFailure(
                primaryError: primaryError,
                repairErrors: [
                    SessionGrantRepairFailure(
                        step: .acquireStateLock,
                        underlyingError: error
                    )
                ],
                chargeState: .charged,
                shieldState: .unblocked
            )
        }
    }

    private func repairedFailureUnlocked(
        primaryError: any Error,
        ruleID: UUID,
        activityName: String
    ) -> SessionGrantFailure {
        var failures: [SessionGrantRepairFailure] = []
        let rollback = collectRepairFailure(step: .rollBackRuntime) {
            try runtime.rollBack(ruleID: ruleID)
        }
        failures.append(contentsOf: rollback)
        if rollback.isEmpty {
            failures.append(contentsOf: collectRepairFailure(step: .stopMonitoring) {
                try scheduler.stop(activityName: activityName)
            })
            let shieldRepair = collectRepairFailure(step: .forceShield) {
                try shield.shield(ruleID: ruleID)
            }
            failures.append(contentsOf: shieldRepair)
            return SessionGrantFailure(
                primaryError: primaryError,
                repairErrors: failures,
                chargeState: .notCharged,
                shieldState: shieldRepair.isEmpty ? .blocked : .unknown
            )
        } else {
            let shieldState: GrantShieldState
            do {
                switch try shield.forceShieldForFailedGrant(ruleID: ruleID) {
                case .durable:
                    shieldState = .blocked
                case let .immediateOnly(error):
                    failures.append(
                        SessionGrantRepairFailure(
                            step: .persistFailedGrantBlock,
                            underlyingError: error
                        )
                    )
                    shieldState = .blockedDurabilityUnknown
                }
            } catch {
                failures.append(
                    SessionGrantRepairFailure(step: .forceShield, underlyingError: error)
                )
                shieldState = .unknown
            }

            return SessionGrantFailure(
                primaryError: primaryError,
                repairErrors: failures,
                chargeState: .unknown,
                shieldState: shieldState
            )
        }
    }

    private func withPreparationLock<T>(_ operation: () throws -> T) throws -> T {
        if let lock {
            return try lock.withLock(operation)
        }
        return try operation()
    }

    private func collectRepairFailure(
        step: SessionGrantRepairStep,
        _ operation: () throws -> Void
    ) -> [SessionGrantRepairFailure] {
        do {
            try operation()
            return []
        } catch {
            return [SessionGrantRepairFailure(step: step, underlyingError: error)]
        }
    }
}
