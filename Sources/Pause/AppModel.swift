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

private struct ConfigurationRepairError: LocalizedError {
    let changeError: Error
    let repairError: Error

    var errorDescription: String? {
        "The change couldn't be completed (\(changeError.localizedDescription)). Pause also couldn't fully restore the previous app state (\(repairError.localizedDescription)). Close and reopen Pause to retry repair."
    }
}

private struct RuntimeSnapshot {
    let ruleID: UUID
    let runtime: RuleRuntime?
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
    private let shieldReconciler: ShieldReconciler
    private var configurationStore: ConfigurationStore?
    private var runtimeRepository: RuntimeRepository?

    init(
        authorizationCenter: AuthorizationCenter = .shared,
        appGroupContainer: AppGroupContainer = AppGroupContainer(),
        activityCenter: DeviceActivityCenter = DeviceActivityCenter(),
        shieldReconciler: ShieldReconciler = ShieldReconciler()
    ) {
        self.authorizationCenter = authorizationCenter
        self.activityCenter = activityCenter
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
        var removedRuntimeSnapshots: [RuntimeSnapshot] = []
        var attemptedConfigurationSave = false

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
            try cleanUpRules(
                removedRuleIDs,
                runtimeRepository: runtimeRepository,
                snapshots: &removedRuntimeSnapshots
            )
            attemptedConfigurationSave = true
            try configurationStore.save(nextConfiguration)
            configuration = nextConfiguration
        } catch let changeError {
            do {
                try repairFailedConfigurationChange(
                    previousConfiguration: configuration,
                    runtimeSnapshots: removedRuntimeSnapshots,
                    restoreConfiguration: attemptedConfigurationSave,
                    configurationStore: configurationStore,
                    runtimeRepository: runtimeRepository
                )
            } catch let repairError {
                throw ConfigurationRepairError(
                    changeError: changeError,
                    repairError: repairError
                )
            }
            throw changeError
        }

        var normalizedSelection = FamilyActivitySelection()
        normalizedSelection.applicationTokens = selectedTokens
        pickerSelection = normalizedSelection
        reconcileShieldsIfAuthorized(title: "Apps updated, but shields need repair")
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

        let previousConfiguration = configuration
        let nextConfiguration = try ConfigurationDocument(
            settings: configuration.settings,
            rules: configuration.rules.filter { $0.id != id },
            targets: configuration.targets.filter { $0.ruleID != id }
        )
        var runtimeSnapshots: [RuntimeSnapshot] = []
        var attemptedConfigurationSave = false

        do {
            try cleanUpRules(
                [id],
                runtimeRepository: runtimeRepository,
                snapshots: &runtimeSnapshots
            )
            attemptedConfigurationSave = true
            try configurationStore.save(nextConfiguration)
        } catch let changeError {
            do {
                try repairFailedConfigurationChange(
                    previousConfiguration: previousConfiguration,
                    runtimeSnapshots: runtimeSnapshots,
                    restoreConfiguration: attemptedConfigurationSave,
                    configurationStore: configurationStore,
                    runtimeRepository: runtimeRepository
                )
            } catch let repairError {
                throw ConfigurationRepairError(
                    changeError: changeError,
                    repairError: repairError
                )
            }
            throw changeError
        }

        configuration = nextConfiguration
        pickerSelection.applicationTokens.remove(target.applicationToken)
        reconcileShieldsIfAuthorized(title: "App removed, but shields need repair")
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

    private func cleanUpRules(
        _ ruleIDs: [UUID],
        runtimeRepository: RuntimeRepository,
        snapshots: inout [RuntimeSnapshot]
    ) throws {
        for ruleID in ruleIDs {
            let runtime = try runtimeRepository.load(ruleID: ruleID)
            activityCenter.stopMonitoring([
                DeviceActivityName(SessionActivityName.sessionActivityName(for: ruleID))
            ])
            snapshots.append(RuntimeSnapshot(ruleID: ruleID, runtime: runtime))
            try runtimeRepository.delete(ruleID: ruleID)
            try shieldReconciler.unshield(ruleID: ruleID, configuration: configuration)
        }
    }

    private func repairFailedConfigurationChange(
        previousConfiguration: ConfigurationDocument,
        runtimeSnapshots: [RuntimeSnapshot],
        restoreConfiguration: Bool,
        configurationStore: ConfigurationStore,
        runtimeRepository: RuntimeRepository
    ) throws {
        var firstRepairError: Error?

        if restoreConfiguration {
            do {
                try configurationStore.save(previousConfiguration)
            } catch {
                firstRepairError = error
            }
        }

        for snapshot in runtimeSnapshots {
            guard let runtime = snapshot.runtime else { continue }
            do {
                try runtimeRepository.save(runtime, ruleID: snapshot.ruleID)
            } catch {
                firstRepairError = firstRepairError ?? error
            }
        }

        do {
            try runtimeRepository.deleteOrphanedRuntimes(
                keeping: Set(previousConfiguration.rules.map(\.id))
            )
        } catch {
            firstRepairError = firstRepairError ?? error
        }

        if canApplyManagedSettings {
            do {
                try shieldReconciler.reconcile(
                    configuration: previousConfiguration,
                    runtimeRepository: runtimeRepository,
                    now: Date()
                )
            } catch {
                firstRepairError = firstRepairError ?? error
            }
        }

        if let firstRepairError {
            throw firstRepairError
        }
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
