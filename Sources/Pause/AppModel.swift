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

struct PauseEntryContext {
    let details: PauseEntryDetails
    let applicationToken: ApplicationToken
    let countdown: PauseCountdown
}

struct RefusalContent {
    let applicationToken: ApplicationToken
    let title: String
    let message: String
}

struct RepairContent {
    let applicationToken: ApplicationToken?
    let title: String
    let message: String
}

enum AppEntryRoute {
    case configuration
    case pause(PauseEntryContext)
    case refused(RefusalContent)
    case repair(RepairContent)
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
    @Published private(set) var entryRoute: AppEntryRoute = .configuration
    @Published private(set) var isGrantRequested = false

    private let authorizationCenter: AuthorizationCenter
    private let activityCenter: DeviceActivityCenter
    private let ruleRemovalCoordinator: RuleRemovalCoordinator
    private let shieldReconciler: ShieldReconciler
    private let shieldIntentStore: ShieldIntentStore
    private var configurationStore: ConfigurationStore?
    private var runtimeRepository: RuntimeRepository?
    private var activationCoordinator = PauseActivationCoordinator(configurationState: .failed)

    init(
        authorizationCenter: AuthorizationCenter = .shared,
        appGroupContainer: AppGroupContainer = AppGroupContainer(),
        activityCenter: DeviceActivityCenter = DeviceActivityCenter(),
        ruleRemovalCoordinator: RuleRemovalCoordinator = RuleRemovalCoordinator(),
        shieldReconciler: ShieldReconciler = ShieldReconciler(),
        shieldIntentStore: ShieldIntentStore = ShieldIntentStore()
    ) {
        self.authorizationCenter = authorizationCenter
        self.activityCenter = activityCenter
        self.ruleRemovalCoordinator = ruleRemovalCoordinator
        self.shieldReconciler = shieldReconciler
        self.shieldIntentStore = shieldIntentStore
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
                activationCoordinator.configurationBecameKnownGood()
            } else {
                activationCoordinator.configurationWasMissing(
                    hasProtectedState: Self.hasProtectedState(in: directoryURL)
                )
            }
        } catch {
            activationCoordinator.configurationLoadFailed()
            presentedError = AppError(title: "Couldn't load Pause", error: error)
        }
    }

    func refreshAuthorizationStatus() {
        authorizationStatus = authorizationCenter.authorizationStatus
    }

    func sceneDidBecomeActive(now: Date = Date()) {
        refreshAuthorizationStatus()

        var coordinator = activationCoordinator
        let outcome: PauseActivationOutcome<AppEntryRoute> = coordinator.activate(
            isAuthorized: canApplyManagedSettings,
            consumeIntent: shieldIntentStore.consume,
            resolveIntent: { [self] intent in
                try resolveShieldIntent(intent, now: now)
            },
            cleanup: { [self] in cleanupOrphanedRuntimes() },
            reconcile: { [self] in reconcileShieldsIfAuthorized() }
        )
        activationCoordinator = coordinator

        switch outcome {
        case .unchanged:
            return
        case .configuration:
            entryRoute = .configuration
        case .repair:
            entryRoute = activationRepairRoute
        case let .resolved(route):
            entryRoute = route
            if case .pause = route {
                activationCoordinator.countdownDidStart()
            }
        }
    }

    func sceneDidBecomeInactive() {
        activationCoordinator.sceneDidBecomeInactive()
        if activationCoordinator.foregroundState == .configuration, case .pause = entryRoute {
            entryRoute = .configuration
        }
    }

    func requestSessionGrant() {
        guard case .pause = entryRoute else { return }
        activationCoordinator.grantDidStart()
        isGrantRequested = true
    }

    func returnToConfiguration() {
        isGrantRequested = false
        activationCoordinator.returnedToConfiguration()
        entryRoute = .configuration
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
        guard activationCoordinator.configurationState != .failed else {
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
            activationCoordinator.configurationBecameKnownGood()
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
        guard activationCoordinator.configurationState == .knownGood,
              let runtimeRepository else { return }
        do {
            try runtimeRepository.deleteOrphanedRuntimes(
                keeping: Set(configuration.rules.map(\.id))
            )
        } catch {
            presentedError = AppError(title: "Couldn't finish app-data cleanup", error: error)
        }
    }

    private func resolveShieldIntent(
        _ intent: ShieldIntent,
        now: Date
    ) throws -> PauseActivationResolution<AppEntryRoute> {
        isGrantRequested = false

        let age = now.timeIntervalSince(intent.createdAt)
        guard age >= 0, age <= PauseEntryRouter.maximumIntentAge else {
            return PauseActivationResolution(
                payload: .repair(
                    RepairContent(
                        applicationToken: intent.applicationToken,
                        title: "This request expired",
                        message: "The app remains blocked. Return to it and try again."
                    )
                ),
                performMaintenance: false
            )
        }

        guard let runtimeRepository else {
            throw AppModelError.storageUnavailable
        }
        let matchingTargets = configuration.targets.filter {
            $0.applicationToken == intent.applicationToken
        }
        guard matchingTargets.count == 1, let target = matchingTargets.first else {
            throw RuleLookupError.targetNotFound
        }
        guard let rule = configuration.rules.first(where: { $0.id == target.ruleID }) else {
            throw RuleLookupError.ruleNotFound(target.ruleID)
        }

        guard let runtime = try runtimeRepository.load(ruleID: rule.id) else {
            throw RuleLookupError.runtimeNotFound(rule.id)
        }
        let evaluation = RuleLookup.evaluate(
            rule: rule,
            runtime: runtime,
            now: now,
            calendar: .current
        )
        let resolution = PauseEntryResolution.resolved(
            ruleID: rule.id,
            sessionsPerDay: rule.sessionsPerDay,
            pauseSeconds: configuration.settings.pauseSeconds,
            decision: evaluation.decision
        )

        let route: AppEntryRoute
        switch PauseEntryRouter.route(
            input: .intent(createdAt: intent.createdAt, resolution: resolution),
            now: now
        ) {
        case let .pause(details):
            route = .pause(
                PauseEntryContext(
                    details: details,
                    applicationToken: target.applicationToken,
                    countdown: try PauseCountdown(
                        ruleID: details.ruleID,
                        seconds: details.pauseSeconds,
                        now: now
                    )
                )
            )
        case let .refused(reason):
            route = .refused(refusalContent(for: reason, token: target.applicationToken))
        case .configuration:
            route = .configuration
        case .repair:
            route = genericRepairContent(for: intent.applicationToken)
        }
        let performMaintenance: Bool
        if case .repair = route {
            performMaintenance = false
        } else {
            performMaintenance = true
        }
        return PauseActivationResolution(
            payload: route,
            performMaintenance: performMaintenance
        )
    }

    private func refusalContent(
        for reason: RefusalReason,
        token: ApplicationToken
    ) -> RefusalContent {
        switch reason {
        case let .dailyAllowanceExhausted(limit):
            RefusalContent(
                applicationToken: token,
                title: "No sessions left today",
                message: "All \(limit) sessions have been used. This app remains blocked until the daily reset."
            )
        case let .sessionAlreadyOpen(until):
            RefusalContent(
                applicationToken: token,
                title: "A session is already open",
                message: "The current session runs until \(until.formatted(date: .omitted, time: .shortened))."
            )
        }
    }

    private func genericRepairContent(for token: ApplicationToken?) -> AppEntryRoute {
        .repair(
            RepairContent(
                applicationToken: token,
                title: "Pause needs repair",
                message: "This app's rule or session data couldn't be read safely. The app remains blocked."
            )
        )
    }

    private var activationRepairRoute: AppEntryRoute {
        switch activationCoordinator.configurationState {
        case .failed:
            .repair(
                RepairContent(
                    applicationToken: nil,
                    title: "Pause couldn't load its configuration",
                    message: "Saved rules couldn't be read safely. Existing apps remain blocked."
                )
            )
        case .missing:
            .repair(
                RepairContent(
                    applicationToken: nil,
                    title: "Pause can't match this app",
                    message: "No saved configuration is available. The app remains blocked."
                )
            )
        case .knownGood:
            genericRepairContent(for: nil)
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
        guard activationCoordinator.configurationState == .knownGood,
              canApplyManagedSettings,
              let runtimeRepository else { return }
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

    private static func hasProtectedState(in directoryURL: URL) -> Bool {
        if let shieldedApplications = ManagedSettingsStore().shield.applications,
           !shieldedApplications.isEmpty {
            return true
        }

        do {
            return try FileManager.default.contentsOfDirectory(
                at: directoryURL,
                includingPropertiesForKeys: nil
            ).contains { fileURL in
                let name = fileURL.lastPathComponent
                return name.hasPrefix("runtime-")
                    && (name.hasSuffix(".json") || name.hasSuffix(".json.removal-stage"))
            }
        } catch {
            return true
        }
    }

    private static var emptyConfiguration: ConfigurationDocument {
        try! ConfigurationDocument(settings: .phaseOneDefault, rules: [], targets: [])
    }
}
