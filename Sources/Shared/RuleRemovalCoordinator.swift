import Foundation

public struct StagedRuntimeRemoval: Equatable {
    public let ruleID: UUID
    public let wasPresent: Bool

    public init(ruleID: UUID, wasPresent: Bool) {
        self.ruleID = ruleID
        self.wasPresent = wasPresent
    }
}

public struct RuleRemovalFailure: LocalizedError {
    public let primaryError: Error
    public let repairErrors: [Error]

    public init(primaryError: Error, repairErrors: [Error]) {
        self.primaryError = primaryError
        self.repairErrors = repairErrors
    }

    public func addingRepairErrors(_ additionalErrors: [Error]) -> RuleRemovalFailure {
        RuleRemovalFailure(
            primaryError: primaryError,
            repairErrors: repairErrors + additionalErrors
        )
    }

    public var errorDescription: String? {
        let primary = "The app removal failed (\(primaryError.localizedDescription))."
        guard !repairErrors.isEmpty else { return primary }
        let repairs = repairErrors.map(\.localizedDescription).joined(separator: "; ")
        return "\(primary) Repair also failed: \(repairs)."
    }
}

public struct RuleRemovalOutcome {
    public let cleanupErrors: [Error]

    public init(cleanupErrors: [Error]) {
        self.cleanupErrors = cleanupErrors
    }
}

public struct RuleRemovalCleanupError: LocalizedError {
    public let errors: [Error]

    public init(errors: [Error]) {
        self.errors = errors
    }

    public var errorDescription: String? {
        let details = errors.map(\.localizedDescription).joined(separator: "; ")
        return "The app was removed, but cleanup failed: \(details)."
    }
}

public struct RuleRemovalCoordinator {
    public init() {}

    public func remove(
        ruleIDs: [UUID],
        stageRuntime: (UUID) throws -> StagedRuntimeRemoval,
        restoreRuntime: (StagedRuntimeRemoval) throws -> Void,
        finalizeRuntime: (StagedRuntimeRemoval) throws -> Void,
        unshield: (UUID) throws -> Void,
        restoreShields: (Set<UUID>) throws -> Void,
        commitConfiguration: () throws -> Void,
        clearFailedGrantBlock: (UUID) throws -> Void = { _ in },
        stopMonitoring: ([UUID]) -> Void
    ) throws -> RuleRemovalOutcome {
        var stages: [StagedRuntimeRemoval] = []

        do {
            for ruleID in ruleIDs {
                stages.append(try stageRuntime(ruleID))
            }
            for ruleID in ruleIDs {
                try unshield(ruleID)
            }
            try commitConfiguration()
        } catch let primaryError {
            var repairErrors: [Error] = []
            var failedRuntimeRestores = Set<UUID>()
            for stage in stages.reversed() {
                do {
                    try restoreRuntime(stage)
                } catch {
                    repairErrors.append(error)
                    failedRuntimeRestores.insert(stage.ruleID)
                }
            }
            if !stages.isEmpty {
                do {
                    try restoreShields(failedRuntimeRestores)
                } catch {
                    repairErrors.append(error)
                }
            }
            throw RuleRemovalFailure(
                primaryError: primaryError,
                repairErrors: repairErrors
            )
        }

        var cleanupErrors: [Error] = []
        for ruleID in ruleIDs {
            do {
                try clearFailedGrantBlock(ruleID)
            } catch {
                cleanupErrors.append(error)
            }
        }

        stopMonitoring(ruleIDs)

        for stage in stages {
            do {
                try finalizeRuntime(stage)
            } catch {
                cleanupErrors.append(error)
            }
        }
        return RuleRemovalOutcome(cleanupErrors: cleanupErrors)
    }
}
