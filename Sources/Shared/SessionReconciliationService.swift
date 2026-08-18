import DeviceActivity
import Foundation
import PauseCore

@MainActor
public final class SessionReconciliationService {
    private let configurationStore: ConfigurationStore
    private let runtimeRepository: RuntimeRepository
    private let failedGrantBlockStore: FailedGrantBlockStore
    private let shieldReconciler: ShieldReconciler
    private let stopMonitoring: (String) throws -> Void

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
        failedGrantBlockStore = FailedGrantBlockStore(directoryURL: directoryURL)
        self.shieldReconciler = shieldReconciler
        self.stopMonitoring = stopMonitoring
    }

    public func reconcile(
        now: Date,
        trigger: SessionReconciliationTrigger
    ) -> SessionReconciliationResult {
        let configuration: ConfigurationDocument
        do {
            guard let loaded = try configurationStore.load() else {
                throw SessionReconciliationServiceError.configurationMissing
            }
            configuration = loaded
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
        let configuration: ConfigurationDocument
        do {
            guard let loaded = try configurationStore.load() else {
                throw SessionReconciliationServiceError.configurationMissing
            }
            guard loaded.rules.contains(where: { $0.id == ruleID }) else {
                throw RuleLookupError.ruleNotFound(ruleID)
            }
            configuration = loaded
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
}
