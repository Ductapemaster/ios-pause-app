import Combine
import DeviceActivity
@preconcurrency import FamilyControls
import Foundation
import ManagedSettings
import PauseCore

struct AppError: Identifiable {
    let id = UUID()
    let title: String
    let message: String

    init(title: String, error: Error) {
        self.title = title
        message = error.localizedDescription
    }
}

enum AppModelError: LocalizedError {
    case storageUnavailable
    case ruleNotFound
    case invalidSessionsPerDay
    case invalidSessionLength
    case invalidPauseDuration

    var errorDescription: String? {
        switch self {
        case .storageUnavailable:
            "Pause cannot reach its shared storage. Close and reopen the app, then try again."
        case .ruleNotFound:
            "This app rule no longer exists. Return to the app list and try again."
        case .invalidSessionsPerDay:
            "Sessions per day must be between 1 and 20."
        case .invalidSessionLength:
            "Session length must be between 1 and 120 minutes."
        case .invalidPauseDuration:
            "Pause duration must be between 1 and 120 seconds."
        }
    }
}

@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var authorizationStatus: AuthorizationStatus
    @Published private(set) var configuration: ConfigurationDocument
    @Published var pickerSelection: FamilyActivitySelection
    @Published var presentedError: AppError?

    private let authorizationCenter: AuthorizationCenter
    private let activityCenter: DeviceActivityCenter
    private let ruleRemovalCoordinator: RuleRemovalCoordinator
    private let shieldReconciler: ShieldReconciler
    private var configurationStore: ConfigurationStore?
    private var runtimeRepository: RuntimeRepository?

    init(
        authorizationCenter: AuthorizationCenter = .shared,
        appGroupContainer: AppGroupContainer = AppGroupContainer(),
        activityCenter: DeviceActivityCenter = DeviceActivityCenter(),
        ruleRemovalCoordinator: RuleRemovalCoordinator = RuleRemovalCoordinator(),
        shieldReconciler: ShieldReconciler = ShieldReconciler()
    ) {
        self.authorizationCenter = authorizationCenter
        self.activityCenter = activityCenter
        self.ruleRemovalCoordinator = ruleRemovalCoordinator
        self.shieldReconciler = shieldReconciler
        authorizationStatus = authorizationCenter.authorizationStatus
        configuration = Self.emptyConfiguration
        pickerSelection = FamilyActivitySelection()

        do {
            let directoryURL = try appGroupContainer.directoryURL()
            let configurationStore = ConfigurationStore(directoryURL: directoryURL)
            let runtimeRepository = RuntimeRepository(directoryURL: directoryURL)
            self.configurationStore = configurationStore
            self.runtimeRepository = runtimeRepository

            if let savedConfiguration = try configurationStore.load() {
                configuration = savedConfiguration
                pickerSelection.applicationTokens = Set(savedConfiguration.targets.map(\.applicationToken))
            }
            cleanupOrphanedRuntimes()
            reconcileShieldsIfAuthorized()
        } catch {
            presentedError = AppError(title: "Couldn't load Pause", error: error)
        }
    }

    func refreshAuthorizationStatus() {
        authorizationStatus = authorizationCenter.authorizationStatus
        cleanupOrphanedRuntimes()
        reconcileShieldsIfAuthorized()
    }

    func requestAuthorization() async {
        do {
            try await authorizationCenter.requestAuthorization(for: .individual)
            authorizationStatus = authorizationCenter.authorizationStatus
            reconcileShieldsIfAuthorized()
        } catch {
            authorizationStatus = authorizationCenter.authorizationStatus
            presentedError = AppError(title: "Screen Time access wasn't granted", error: error)
        }
    }

    func applyPickerSelection() throws {
        guard let configurationStore, let runtimeRepository else {
            throw AppModelError.storageUnavailable
        }

        let selectedTokens = pickerSelection.applicationTokens
        let existingTargets = configuration.targets
        let existingTokens = Set(existingTargets.map(\.applicationToken))
        let addedTokens = selectedTokens.subtracting(existingTokens)
        let retainedTokens = selectedTokens.intersection(existingTokens)
        let removedTokens = existingTokens.subtracting(selectedTokens)
        let removedRuleIDs = existingTargets.compactMap { target in
            removedTokens.contains(target.applicationToken) ? target.ruleID : nil
        }
        let rulesByID = Dictionary(uniqueKeysWithValues: configuration.rules.map { ($0.id, $0) })
        let applicationsByToken = Dictionary(
            uniqueKeysWithValues: pickerSelection.applications.compactMap { application in
                application.token.map { ($0, application) }
            }
        )

        var nextRules: [AppRule] = []
        var nextTargets: [RuleTarget] = []
        var removalOutcome = RuleRemovalOutcome(cleanupErrors: [])

        for target in existingTargets {
            guard retainedTokens.contains(target.applicationToken) else { continue }
            guard let rule = rulesByID[target.ruleID] else { continue }
            let detectedRoute = applicationsByToken[target.applicationToken].flatMap(LaunchRoute.detected)
            nextRules.append(rule)
            nextTargets.append(
                RuleTarget(
                    ruleID: target.ruleID,
                    applicationToken: target.applicationToken,
                    launchRoute: detectedRoute ?? target.launchRoute
                )
            )
        }

        let today = CalendarDay(date: Date(), calendar: .current)
        do {
            for token in addedTokens {
                let rule = try AppRule(sessionsPerDay: 3, sessionLengthMinutes: 5)
                let launchRoute = applicationsByToken[token].flatMap(LaunchRoute.detected)
                nextRules.append(rule)
                nextTargets.append(
                    RuleTarget(ruleID: rule.id, applicationToken: token, launchRoute: launchRoute)
                )
                try runtimeRepository.save(
                    RuleRuntime(logicalDay: today, sessionsStarted: 0),
                    ruleID: rule.id
                )
            }

            let nextConfiguration = try ConfigurationDocument(
                settings: configuration.settings,
                rules: nextRules,
                targets: nextTargets
            )
            if removedRuleIDs.isEmpty {
                try configurationStore.save(nextConfiguration)
            } else {
                removalOutcome = try commitRuleRemoval(
                    ruleIDs: removedRuleIDs,
                    nextConfiguration: nextConfiguration,
                    configurationStore: configurationStore,
                    runtimeRepository: runtimeRepository
                )
            }
            configuration = nextConfiguration
        } catch let changeError {
            var repairErrors: [Error] = []
            do {
                try runtimeRepository.deleteOrphanedRuntimes(
                    keeping: Set(configuration.rules.map(\.id))
                )
            } catch {
                repairErrors.append(error)
            }

            if let removalFailure = changeError as? RuleRemovalFailure {
                throw removalFailure.addingRepairErrors(repairErrors)
            }
            if !repairErrors.isEmpty {
                throw RuleRemovalFailure(
                    primaryError: changeError,
                    repairErrors: repairErrors
                )
            }
            throw changeError
        }

        var normalizedSelection = FamilyActivitySelection()
        normalizedSelection.applicationTokens = selectedTokens
        pickerSelection = normalizedSelection
        reconcileShieldsIfAuthorized(title: "Apps updated, but shields need repair")
        presentRemovalCleanupErrors(removalOutcome.cleanupErrors)
    }

    func updateRule(id: UUID, sessionsPerDay: Int, sessionLengthMinutes: Int) throws {
        guard (1...20).contains(sessionsPerDay) else {
            throw AppModelError.invalidSessionsPerDay
        }
        guard (1...120).contains(sessionLengthMinutes) else {
            throw AppModelError.invalidSessionLength
        }
        guard let configurationStore else {
            throw AppModelError.storageUnavailable
        }
        guard let index = configuration.rules.firstIndex(where: { $0.id == id }) else {
            throw AppModelError.ruleNotFound
        }

        var nextConfiguration = configuration
        nextConfiguration.rules[index] = try AppRule(
            id: id,
            sessionsPerDay: sessionsPerDay,
            sessionLengthMinutes: sessionLengthMinutes
        )
        try configurationStore.save(nextConfiguration)
        configuration = nextConfiguration
        reconcileShieldsIfAuthorized(title: "Rule saved, but shields need repair")
    }

    func updatePauseSeconds(_ seconds: Int) throws {
        guard (1...120).contains(seconds) else {
            throw AppModelError.invalidPauseDuration
        }
        guard let configurationStore else {
            throw AppModelError.storageUnavailable
        }

        var nextConfiguration = configuration
        nextConfiguration.settings = try GlobalSettings(pauseSeconds: seconds)
        try configurationStore.save(nextConfiguration)
        configuration = nextConfiguration
    }

    func removeRule(id: UUID) throws {
        guard let configurationStore, let runtimeRepository else {
            throw AppModelError.storageUnavailable
        }
        guard let target = configuration.targets.first(where: { $0.ruleID == id }) else {
            throw AppModelError.ruleNotFound
        }

        let nextConfiguration = try ConfigurationDocument(
            settings: configuration.settings,
            rules: configuration.rules.filter { $0.id != id },
            targets: configuration.targets.filter { $0.ruleID != id }
        )
        let removalOutcome = try commitRuleRemoval(
            ruleIDs: [id],
            nextConfiguration: nextConfiguration,
            configurationStore: configurationStore,
            runtimeRepository: runtimeRepository
        )

        configuration = nextConfiguration
        pickerSelection.applicationTokens.remove(target.applicationToken)
        reconcileShieldsIfAuthorized(title: "App removed, but shields need repair")
        presentRemovalCleanupErrors(removalOutcome.cleanupErrors)
    }

    func present(_ error: Error, title: String = "Couldn't save changes") {
        presentedError = AppError(title: title, error: error)
    }

    private func cleanupOrphanedRuntimes() {
        guard let runtimeRepository else { return }
        do {
            try runtimeRepository.deleteOrphanedRuntimes(
                keeping: Set(configuration.rules.map(\.id))
            )
        } catch {
            presentedError = AppError(title: "Couldn't finish app-data cleanup", error: error)
        }
    }

    private func commitRuleRemoval(
        ruleIDs: [UUID],
        nextConfiguration: ConfigurationDocument,
        configurationStore: ConfigurationStore,
        runtimeRepository: RuntimeRepository
    ) throws -> RuleRemovalOutcome {
        let previousConfiguration = configuration
        return try ruleRemovalCoordinator.remove(
            ruleIDs: ruleIDs,
            stageRuntime: { ruleID in
                try runtimeRepository.stageRemoval(ruleID: ruleID)
            },
            restoreRuntime: { stage in
                try runtimeRepository.restoreRemoval(stage)
            },
            finalizeRuntime: { stage in
                try runtimeRepository.finalizeRemoval(stage)
            },
            unshield: { ruleID in
                guard canApplyManagedSettings else { return }
                try shieldReconciler.unshield(
                    ruleID: ruleID,
                    configuration: previousConfiguration
                )
            },
            restoreShields: { failedRuntimeRestores in
                guard canApplyManagedSettings else { return }
                try shieldReconciler.reconcile(
                    configuration: previousConfiguration,
                    runtimeRepository: runtimeRepository,
                    now: Date(),
                    forceShieldedRuleIDs: failedRuntimeRestores
                )
            },
            commitConfiguration: {
                try configurationStore.save(nextConfiguration)
            },
            stopMonitoring: { ruleIDs in
                activityCenter.stopMonitoring(
                    ruleIDs.map { ruleID in
                        DeviceActivityName(
                            SessionActivityName.sessionActivityName(for: ruleID)
                        )
                    }
                )
            }
        )
    }

    private func presentRemovalCleanupErrors(_ errors: [Error]) {
        guard !errors.isEmpty else { return }
        presentedError = AppError(
            title: "App removed, but cleanup failed",
            error: RuleRemovalCleanupError(errors: errors)
        )
    }

    private func reconcileShieldsIfAuthorized(
        title: String = "Pause needs repair"
    ) {
        guard canApplyManagedSettings, let runtimeRepository else { return }
        do {
            try shieldReconciler.reconcile(
                configuration: configuration,
                runtimeRepository: runtimeRepository,
                now: Date()
            )
        } catch {
            presentedError = AppError(title: title, error: error)
        }
    }

    private var canApplyManagedSettings: Bool {
        switch authorizationStatus {
        case .approved, .approvedWithDataAccess:
            true
        case .notDetermined, .denied:
            false
        @unknown default:
            false
        }
    }

    private static var emptyConfiguration: ConfigurationDocument {
        try! ConfigurationDocument(settings: .phaseOneDefault, rules: [], targets: [])
    }
}
