import DeviceActivity
import Foundation
import OSLog
import PauseCore

public final class SessionReconciliationService {
    private let configurationStore: ConfigurationStore
    private let runtimeRepository: RuntimeRepository
    private let failedGrantBlockStore: FailedGrantBlockFileStore
    private let shieldReconciler: ShieldReconciler
    private let stopMonitoring: (String) throws -> Void
    private let stateLock: AppGroupFileLock

    public convenience init(
        appGroupContainer: AppGroupContainer = AppGroupContainer(),
        shieldReconciler: ShieldReconciler = ShieldReconciler(),
        activityCenter: DeviceActivityCenter = DeviceActivityCenter()
    ) throws {
        let directoryURL = try appGroupContainer.directoryURL()
        let logger = Logger(subsystem: "com.koubalabs.pause.monitor", category: "reconciliation")
        self.init(
            directoryURL: directoryURL,
            shieldReconciler: shieldReconciler,
            stopMonitoring: { activityName in
                // Entry and exit are both logged because this call is known not
                // to return from inside a monitor callback. An entry without its
                // exit in the archive names it as the call that blocked, and the
                // elapsed time says how long the host waited before tearing the
                // extension down.
                let began = Date()
                logger.notice("stopMonitoring began for activity \(activityName, privacy: .public)")
                activityCenter.stopMonitoring([DeviceActivityName(activityName)])
                let elapsed = String(format: "%.3f", Date().timeIntervalSince(began))
                logger.notice(
                    "stopMonitoring returned for activity \(activityName, privacy: .public), +\(elapsed, privacy: .public)s"
                )
            }
        )
    }

    init(
        directoryURL: URL,
        shieldReconciler: ShieldReconciler,
        stopMonitoring: @escaping (String) throws -> Void
    ) {
        configurationStore = ConfigurationStore(directoryURL: directoryURL)
        runtimeRepository = RuntimeRepository(directoryURL: directoryURL)
        failedGrantBlockStore = FailedGrantBlockFileStore(directoryURL: directoryURL)
        stateLock = AppGroupFileLock(directoryURL: directoryURL)
        self.shieldReconciler = shieldReconciler
        self.stopMonitoring = stopMonitoring
    }

    public func reconcile(
        now: Date,
        trigger: SessionReconciliationTrigger
    ) -> SessionReconciliationResult {
        var result: SessionReconciliationResult
        do {
            result = try stateLock.withLock {
                reconcileUnlocked(now: now, trigger: trigger)
            }
        } catch {
            return lockFailure(error, ruleID: trigger.selectedRuleID)
        }

        guard let activityName = result.pendingStopActivityName else { return result }
        result.pendingStopActivityName = nil
        // Deliberately outside the lock. `stopMonitoring` called from within a
        // monitor callback does not return until the host tears the extension
        // down, and it touches none of the state the lock protects, so holding
        // the lock across it locks every other participant out for that long.
        do {
            try stopMonitoring(activityName)
        } catch {
            result.issues.append(
                SessionReconciliationIssue(
                    ruleID: trigger.selectedRuleID,
                    operation: .stopMonitoring,
                    underlyingError: error
                )
            )
        }
        return result
    }

    private func reconcileUnlocked(
        now: Date,
        trigger: SessionReconciliationTrigger
    ) -> SessionReconciliationResult {
        let configuration: ConfigurationDocument
        do {
            guard let file = try configurationStore.loadFile() else {
                throw SessionReconciliationServiceError.configurationMissing
            }
            configuration = file.inForce(at: now)
        } catch {
            return SessionReconciliationResult(
                repairRuleIDs: trigger.selectedRuleID.map { [$0] } ?? [],
                issues: [
                    SessionReconciliationIssue(
                        ruleID: trigger.selectedRuleID,
                        operation: .loadConfiguration,
                        underlyingError: error
                    )
                ]
            )
        }

        let coordinator = SessionReconciliationCoordinator(
            loadFailedGrantBlocks: failedGrantBlockStore.load
        )
        return coordinator.reconcile(
            ruleIDs: configuration.rules.map(\.id),
            now: now,
            trigger: trigger,
            loadRuntime: runtimeRepository.load,
            saveRuntime: runtimeRepository.save,
            clearFailedGrantBlock: failedGrantBlockStore.clear,
            applyShields: { [shieldReconciler, runtimeRepository] in
                try shieldReconciler.reconcile(
                    configuration: configuration,
                    runtimeRepository: runtimeRepository,
                    now: now
                )
            }
        )
    }

    public func resetRuntime(
        ruleID: UUID,
        now: Date,
        calendar: Calendar = .current
    ) -> SessionReconciliationResult {
        do {
            return try stateLock.withLock {
                resetRuntimeUnlocked(ruleID: ruleID, now: now, calendar: calendar)
            }
        } catch {
            return lockFailure(error, ruleID: ruleID)
        }
    }

    private func resetRuntimeUnlocked(
        ruleID: UUID,
        now: Date,
        calendar: Calendar
    ) -> SessionReconciliationResult {
        let configuration: ConfigurationDocument
        let file: ConfigurationFile
        do {
            guard let loadedFile = try configurationStore.loadFile() else {
                throw SessionReconciliationServiceError.configurationMissing
            }
            let inForce = loadedFile.inForce(at: now, calendar: calendar)
            guard inForce.rules.contains(where: { $0.id == ruleID }) else {
                throw RuleLookupError.ruleNotFound(ruleID)
            }
            file = loadedFile
            configuration = inForce
        } catch {
            return SessionReconciliationResult(
                repairRuleIDs: [ruleID],
                issues: [
                    SessionReconciliationIssue(
                        ruleID: ruleID,
                        operation: .loadConfiguration,
                        underlyingError: error
                    )
                ]
            )
        }

        let coordinator = SessionReconciliationCoordinator(
            loadFailedGrantBlocks: failedGrantBlockStore.load
        )
        return coordinator.resetRuntime(
            ruleID: ruleID,
            logicalDay: file.logicalDay(at: now, calendar: calendar),
            saveRuntime: runtimeRepository.save,
            clearFailedGrantBlock: failedGrantBlockStore.clear,
            applyShields: { [shieldReconciler, runtimeRepository] in
                try shieldReconciler.reconcile(
                    configuration: configuration,
                    runtimeRepository: runtimeRepository,
                    now: now,
                    persistExpiredSessions: false
                )
            }
        )
    }

    private func lockFailure(_ error: Error, ruleID: UUID?) -> SessionReconciliationResult {
        SessionReconciliationResult(
            repairRuleIDs: ruleID.map { [$0] } ?? [],
            issues: [
                SessionReconciliationIssue(
                    ruleID: ruleID,
                    operation: .acquireStateLock,
                    underlyingError: error
                )
            ]
        )
    }
}
