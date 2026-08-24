import Foundation
import PauseCore

public enum SessionReconciliationOperation: Equatable, Sendable {
    case loadConfiguration
    case acquireStateLock
    case findRule
    case loadRuntime
    case saveRuntime
    case loadFailedGrantBlocks
    case clearFailedGrantBlock
    case applyShields
    case stopMonitoring
}

public struct SessionReconciliationIssue: LocalizedError {
    public let ruleID: UUID?
    public let operation: SessionReconciliationOperation
    public let underlyingError: Error

    public var errorDescription: String? {
        let action: String
        switch operation {
        case .loadConfiguration: action = "read saved app rules"
        case .acquireStateLock: action = "lock shared app state"
        case .findRule: action = "match the expiry activity to a rule"
        case .loadRuntime: action = "read session data"
        case .saveRuntime: action = "save repaired session data"
        case .loadFailedGrantBlocks: action = "read failed-session block data"
        case .clearFailedGrantBlock: action = "clear the failed-session block"
        case .applyShields: action = "restore app shields"
        case .stopMonitoring: action = "stop expiry monitoring"
        }
        return "Pause couldn't \(action): \(underlyingError.localizedDescription)"
    }
}

public enum SessionReconciliationServiceError: LocalizedError {
    case configurationMissing

    public var errorDescription: String? {
        "Pause cannot find its saved app rules. Existing apps remain blocked."
    }
}

public struct SessionReconciliationResult: LocalizedError {
    public var repairRuleIDs: Set<UUID> = []
    public var issues: [SessionReconciliationIssue] = []
    /// The expiry activity this pass finished with, which its caller must stop.
    /// Reported rather than stopped so the stop happens outside the state lock.
    public var pendingStopActivityName: String?

    public var errorDescription: String? {
        guard !issues.isEmpty else { return nil }
        return issues.compactMap(\.errorDescription).joined(separator: "\n")
    }
}

public enum SessionReconciliationTrigger: Equatable, Sendable {
    case appActivation
    case dailyReset
    case intervalDidEnd(ruleID: UUID)
    case intervalWillEndWarning(ruleID: UUID, activityName: String)

    var selectedRuleID: UUID? {
        switch self {
        case .appActivation: nil
        case .dailyReset: nil
        case let .intervalDidEnd(ruleID): ruleID
        case let .intervalWillEndWarning(ruleID, _): ruleID
        }
    }
}

/// Coordinates one synchronous reconciliation pass. The caller owns framework
/// isolation; this type only orders storage and shield operations, and reports
/// the expiry activity the caller still has to stop.
public struct SessionReconciliationCoordinator {
    private let loadFailedGrantBlocks: () throws -> Set<UUID>

    public init(loadFailedGrantBlocks: @escaping () throws -> Set<UUID>) {
        self.loadFailedGrantBlocks = loadFailedGrantBlocks
    }

    public func reconcile(
        ruleIDs: [UUID],
        now: Date,
        trigger: SessionReconciliationTrigger,
        loadRuntime: (UUID) throws -> RuleRuntime?,
        saveRuntime: (RuleRuntime, UUID) throws -> Void,
        clearFailedGrantBlock: (UUID) throws -> Void,
        applyShields: () throws -> Void
    ) -> SessionReconciliationResult {
        var result = SessionReconciliationResult()
        let markerIDs: Set<UUID>?
        do {
            markerIDs = try loadFailedGrantBlocks()
        } catch {
            markerIDs = nil
            result.repairRuleIDs.formUnion(ruleIDs)
            result.issues.append(
                SessionReconciliationIssue(
                    ruleID: nil,
                    operation: .loadFailedGrantBlocks,
                    underlyingError: error
                )
            )
        }

        let selectedRuleIDs: [UUID]
        if let selectedRuleID = trigger.selectedRuleID {
            guard ruleIDs.contains(selectedRuleID) else {
                result.repairRuleIDs.insert(selectedRuleID)
                result.issues.append(
                    SessionReconciliationIssue(
                        ruleID: selectedRuleID,
                        operation: .findRule,
                        underlyingError: RuleLookupError.ruleNotFound(selectedRuleID)
                    )
                )
                return result
            }
            selectedRuleIDs = [selectedRuleID]
        } else {
            selectedRuleIDs = ruleIDs
        }

        var selectedCallbackCanStop = false
        for ruleID in selectedRuleIDs {
            let runtime: RuleRuntime
            do {
                guard let loaded = try loadRuntime(ruleID) else {
                    throw RuleLookupError.runtimeNotFound(ruleID)
                }
                runtime = loaded
            } catch {
                result.repairRuleIDs.insert(ruleID)
                result.issues.append(
                    SessionReconciliationIssue(
                        ruleID: ruleID,
                        operation: .loadRuntime,
                        underlyingError: error
                    )
                )
                continue
            }

            let isMarked = markerIDs?.contains(ruleID) == true
            switch reconciliation(for: runtime, now: now) {
            case .keepOpen:
                if trigger == .appActivation, isMarked {
                    result.repairRuleIDs.insert(ruleID)
                }
                break
            case .activateProvisional:
                guard trigger == .appActivation else { continue }
                guard markerIDs != nil, !isMarked else {
                    result.repairRuleIDs.insert(ruleID)
                    continue
                }
                var activeRuntime = runtime
                do {
                    try activeRuntime.activateReservedSession()
                    try saveRuntime(activeRuntime, ruleID)
                } catch {
                    result.repairRuleIDs.insert(ruleID)
                    result.issues.append(
                        SessionReconciliationIssue(
                            ruleID: ruleID,
                            operation: .saveRuntime,
                            underlyingError: error
                        )
                    )
                }
            case .expire:
                var expiredRuntime = runtime
                expiredRuntime.clearExpiredSession(at: now)
                do {
                    try saveRuntime(expiredRuntime, ruleID)
                    selectedCallbackCanStop = true
                    if isMarked {
                        do {
                            try clearFailedGrantBlock(ruleID)
                        } catch {
                            result.repairRuleIDs.insert(ruleID)
                            result.issues.append(
                                SessionReconciliationIssue(
                                    ruleID: ruleID,
                                    operation: .clearFailedGrantBlock,
                                    underlyingError: error
                                )
                            )
                        }
                    }
                } catch {
                    result.repairRuleIDs.insert(ruleID)
                    result.issues.append(
                        SessionReconciliationIssue(
                            ruleID: ruleID,
                            operation: .saveRuntime,
                            underlyingError: error
                        )
                    )
                }
            case .noSession:
                selectedCallbackCanStop = true
                if isMarked {
                    do {
                        try clearFailedGrantBlock(ruleID)
                    } catch {
                        result.repairRuleIDs.insert(ruleID)
                        result.issues.append(
                            SessionReconciliationIssue(
                                ruleID: ruleID,
                                operation: .clearFailedGrantBlock,
                                underlyingError: error
                            )
                        )
                    }
                }
            }
        }

        let shouldApplyShields = trigger == .appActivation
            || trigger == .dailyReset
            || selectedCallbackCanStop
            || !result.issues.isEmpty
        var shieldsApplied = false
        if shouldApplyShields {
            do {
                try applyShields()
                shieldsApplied = true
            } catch {
                result.issues.append(
                    SessionReconciliationIssue(
                        ruleID: trigger.selectedRuleID,
                        operation: .applyShields,
                        underlyingError: error
                    )
                )
                if let selected = trigger.selectedRuleID { result.repairRuleIDs.insert(selected) }
            }
        }

        if case let .intervalWillEndWarning(_, activityName) = trigger,
           selectedCallbackCanStop,
           shieldsApplied {
            result.pendingStopActivityName = activityName
        }
        return result
    }

    public func resetRuntime(
        ruleID: UUID,
        logicalDay: CalendarDay,
        saveRuntime: (RuleRuntime, UUID) throws -> Void,
        clearFailedGrantBlock: (UUID) throws -> Void,
        applyShields: () throws -> Void
    ) -> SessionReconciliationResult {
        var result = SessionReconciliationResult()
        var runtimeSaved = false
        do {
            try saveRuntime(
                RuleRuntime(logicalDay: logicalDay, sessionsStarted: 0),
                ruleID
            )
            runtimeSaved = true
        } catch {
            result.repairRuleIDs.insert(ruleID)
            result.issues.append(
                SessionReconciliationIssue(
                    ruleID: ruleID,
                    operation: .saveRuntime,
                    underlyingError: error
                )
            )
        }

        if runtimeSaved {
            do {
                try clearFailedGrantBlock(ruleID)
            } catch {
                result.repairRuleIDs.insert(ruleID)
                result.issues.append(
                    SessionReconciliationIssue(
                        ruleID: ruleID,
                        operation: .clearFailedGrantBlock,
                        underlyingError: error
                    )
                )
            }
        }

        do {
            try applyShields()
        } catch {
            result.repairRuleIDs.insert(ruleID)
            result.issues.append(
                SessionReconciliationIssue(
                    ruleID: ruleID,
                    operation: .applyShields,
                    underlyingError: error
                )
            )
        }
        return result
    }
}
