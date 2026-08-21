import DeviceActivity
import Foundation
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
        self.init(
            directoryURL: directoryURL,
            shieldReconciler: shieldReconciler,
            stopMonitoring: { activityName in
                activityCenter.stopMonitoring([DeviceActivityName(activityName)])
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
        do {
            return try stateLock.withLock {
                reconcileUnlocked(now: now, trigger: trigger)
            }
        } catch {
            return lockFailure(error, ruleID: trigger.selectedRuleID)
        }
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
            configuration = file.inForce(on: LogicalDay.containing(now))
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
            },
            stopMonitoring: stopMonitoring
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
        do {
            guard let file = try configurationStore.loadFile() else {
                throw SessionReconciliationServiceError.configurationMissing
            }
            let inForce = file.inForce(on: LogicalDay.containing(now, calendar: calendar))
            guard inForce.rules.contains(where: { $0.id == ruleID }) else {
                throw RuleLookupError.ruleNotFound(ruleID)
            }
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
            logicalDay: CalendarDay(date: now, calendar: calendar),
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
