import Combine
import DeviceActivity
@preconcurrency import FamilyControls
import Foundation
import ManagedSettings
import OSLog
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
    let runtimeResetRuleID: UUID?

    init(
        applicationToken: ApplicationToken?,
        title: String,
        message: String,
        runtimeResetRuleID: UUID? = nil
    ) {
        self.applicationToken = applicationToken
        self.title = title
        self.message = message
        self.runtimeResetRuleID = runtimeResetRuleID
    }
}

enum AppEntryRoute {
    case configuration
    case pause(PauseEntryContext)
    case manualReturn(ManualReturnContent)
    case refused(RefusalContent)
    case repair(RepairContent)
}

enum AppRootRoute: Equatable {
    case configurationRepair
    case authorization
    case authorizedContent
}

enum AppModelError: LocalizedError, Equatable {
    case storageUnavailable
    case unsafeConfiguration
    case ruleNotFound
    case invalidSessionsPerDay
    case invalidSessionLength
    case invalidPauseDuration
    case invalidResetMinuteOfDay

    var errorDescription: String? {
        switch self {
        case .storageUnavailable:
            "Pause cannot reach its shared storage. Close and reopen the app, then try again."
        case .unsafeConfiguration:
            "Pause cannot change rules until its saved configuration can be read safely."
        case .ruleNotFound:
            "This app rule no longer exists. Return to the app list and try again."
        case .invalidSessionsPerDay:
            "Sessions per day must be between 1 and 20."
        case .invalidSessionLength:
            "Session length must be between 1 and 120 minutes."
        case .invalidPauseDuration:
            "Pause duration must be between 1 and 120 seconds."
        case .invalidResetMinuteOfDay:
            "The daily reset must be a quarter hour between 00:00 and 23:45."
        }
    }
}

@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var authorizationStatus: AuthorizationStatus
    @Published private(set) var configuration: ConfigurationDocument
    @Published private(set) var pendingChangeStartDay: CalendarDay?
    /// Whether the last save deferred part of itself, as opposed to leaving a
    /// change scheduled that it never touched. The rule editor stays open only
    /// for the former: the wait it shows should be the one just chosen.
    @Published private(set) var lastSaveDeferredPart = false
    @Published var pickerSelection: FamilyActivitySelection
    @Published var presentedError: AppError?
    @Published private(set) var entryRoute: AppEntryRoute = .configuration
    @Published private(set) var isGrantRequested = false

    private let authorizationStatusProvider: () -> AuthorizationStatus
    private let authorizationRequester: () async throws -> Void
    private let activityCenter: DeviceActivityCenter
    private let shieldReconciler: ShieldReconciler
    private let shieldIntentStore: ShieldIntentStore
    private let entryActivationProvider: ((Date) throws -> PauseActivationResolution<AppEntryRoute>?)?
    private let cleanupOverride: (() -> Void)?
    private let reconciliationOverride: (() -> Void)?
    private let sessionScheduler: (any SessionScheduling)?
    private let sessionRuntimePersistence: (any RuntimePersisting)?
    private let sessionShieldController: (any ShieldControlling)?
    private let targetLauncher: (any TargetLaunching)?
    private var configurationStore: ConfigurationStore?
    /// The whole saved file, kept beside the published `configuration` so a
    /// scheduled change is still reachable once the in-force document has been
    /// selected out of it.
    ///
    /// Published because the rules list reads it directly, to ask the file which
    /// allowance day a scheduled change starts on rather than picking a reset
    /// minute out of a document itself.
    @Published private(set) var configurationFile: ConfigurationFile?
    private var runtimeRepository: RuntimeRepository?
    private var failedGrantBlockStore: FailedGrantBlockStore?
    private var stateLock: AppGroupFileLock?
    private var activationCoordinator = PauseActivationCoordinator(configurationState: .failed)
    private var isSceneActive = false
    private var authorizationStatusAtLastActivation: AuthorizationStatus?
    private var activationRuntimeRepairs: [RepairContent] = []

    init(
        authorizationCenter: AuthorizationCenter = .shared,
        appGroupContainer: AppGroupContainer = AppGroupContainer(),
        activityCenter: DeviceActivityCenter = DeviceActivityCenter(),
        shieldReconciler: ShieldReconciler = ShieldReconciler(),
        shieldIntentStore: ShieldIntentStore = ShieldIntentStore(),
        storageDirectoryURL: URL? = nil,
        authorizationStatusProvider: (() -> AuthorizationStatus)? = nil,
        authorizationRequester: (() async throws -> Void)? = nil,
        entryActivationProvider: ((Date) throws -> PauseActivationResolution<AppEntryRoute>?)? = nil,
        protectedStateDetector: ((URL) -> Bool)? = nil,
        cleanupOverride: (() -> Void)? = nil,
        reconciliationOverride: (() -> Void)? = nil,
        sessionScheduler: (any SessionScheduling)? = nil,
        sessionRuntimePersistence: (any RuntimePersisting)? = nil,
        sessionShieldController: (any ShieldControlling)? = nil,
        targetLauncher: (any TargetLaunching)? = nil
    ) {
        let statusProvider = authorizationStatusProvider
            ?? { authorizationCenter.authorizationStatus }
        self.authorizationStatusProvider = statusProvider
        self.authorizationRequester = authorizationRequester
            ?? { try await authorizationCenter.requestAuthorization(for: .individual) }
        self.activityCenter = activityCenter
        self.shieldReconciler = shieldReconciler
        self.shieldIntentStore = shieldIntentStore
        self.entryActivationProvider = entryActivationProvider
        self.cleanupOverride = cleanupOverride
        self.reconciliationOverride = reconciliationOverride
        self.sessionScheduler = sessionScheduler
        self.sessionRuntimePersistence = sessionRuntimePersistence
        self.sessionShieldController = sessionShieldController
        self.targetLauncher = targetLauncher
        authorizationStatus = statusProvider()
        configuration = Self.emptyConfiguration
        pickerSelection = FamilyActivitySelection()

        do {
            let directoryURL: URL
            if let storageDirectoryURL {
                directoryURL = storageDirectoryURL
            } else {
                directoryURL = try appGroupContainer.directoryURL()
            }
            let configurationStore = ConfigurationStore(directoryURL: directoryURL)
            let runtimeRepository = RuntimeRepository(directoryURL: directoryURL)
            self.configurationStore = configurationStore
            self.runtimeRepository = runtimeRepository
            failedGrantBlockStore = FailedGrantBlockStore(directoryURL: directoryURL)
            stateLock = AppGroupFileLock(directoryURL: directoryURL)

            if let savedFile = try configurationStore.loadFile() {
                let openedAt = Date()
                let savedConfiguration = savedFile.inForce(at: openedAt)
                configurationFile = savedFile
                configuration = savedConfiguration
                pendingChangeStartDay = Self.scheduledStartDay(in: savedFile, now: openedAt)
                pickerSelection.applicationTokens = Set(savedConfiguration.targets.map(\.applicationToken))
                activationCoordinator.configurationBecameKnownGood()
            } else {
                activationCoordinator.configurationWasMissing(
                    hasProtectedState: protectedStateDetector?(directoryURL)
                        ?? Self.hasProtectedState(in: directoryURL)
                )
            }
        } catch {
            activationCoordinator.configurationLoadFailed()
            presentedError = AppError(title: "Couldn't load Pause", error: error)
        }
    }

    func refreshAuthorizationStatus() {
        authorizationStatus = authorizationStatusProvider()
    }

    func sceneDidBecomeActive(now: Date = Date()) {
        isSceneActive = true
        refreshAuthorizationStatus()
        refreshInForceConfiguration(now: now)
        registerDailyReset()

        var coordinator = activationCoordinator
        let outcome: PauseActivationOutcome<AppEntryRoute>
        if let entryActivationProvider {
            outcome = coordinator.activate(
                isAuthorized: canApplyManagedSettings,
                consumeIntent: { try entryActivationProvider(now) },
                resolveIntent: { $0 },
                cleanup: { [self] in cleanupOrphanedRuntimes() },
                reconcile: { [self] in reconcileSessionsIfAuthorized(now: now) }
            )
        } else {
            outcome = coordinator.activate(
                isAuthorized: canApplyManagedSettings,
                consumeIntent: shieldIntentStore.consume,
                resolveIntent: { [self] intent in
                    try resolveShieldIntent(intent, now: now)
                },
                cleanup: { [self] in cleanupOrphanedRuntimes() },
                reconcile: { [self] in reconcileSessionsIfAuthorized(now: now) }
            )
        }
        activationCoordinator = coordinator
        authorizationStatusAtLastActivation = authorizationStatus

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
        if case let .resolved(.repair(selectedRepair)) = outcome {
            activationRuntimeRepairs.removeAll { pendingRepair in
                if let selectedRuleID = selectedRepair.runtimeResetRuleID {
                    return pendingRepair.runtimeResetRuleID == selectedRuleID
                }
                guard let selectedToken = selectedRepair.applicationToken else { return false }
                return pendingRepair.applicationToken == selectedToken
            }
        } else if !activationRuntimeRepairs.isEmpty {
            entryRoute = .repair(activationRuntimeRepairs.removeFirst())
        }
    }

    func sceneDidLeaveForeground() {
        isSceneActive = false
        authorizationStatusAtLastActivation = nil
        activationCoordinator.sceneDidLeaveForeground()
        if activationCoordinator.foregroundState == .configuration, case .pause = entryRoute {
            entryRoute = .configuration
        }
    }

    func requestSessionGrant() {
        Task { await requestSessionGrant(now: Date()) }
    }

    func requestSessionGrant(now: Date) async {
        guard !isGrantRequested,
              case let .pause(entry) = entryRoute,
              entry.countdown.isComplete(at: now),
              let rule = configuration.rules.first(where: { $0.id == entry.details.ruleID }),
              let runtimeRepository else { return }
        activationCoordinator.grantDidStart()
        isGrantRequested = true

        let scheduler = sessionScheduler ?? DeviceActivitySessionScheduler(center: activityCenter)
        let shield: any ShieldControlling
        if let sessionShieldController {
            shield = sessionShieldController
        } else {
            guard let failedGrantBlockStore else { return }
            shield = ConfigurationShieldController(
                configuration: configuration,
                reconciler: shieldReconciler,
                failedGrantBlockStore: failedGrantBlockStore,
                stateLock: stateLock
            )
        }
        let launcher = targetLauncher ?? AppLaunchRouter(configuration: configuration)
        let runtime: any RuntimePersisting
        if let sessionRuntimePersistence {
            runtime = sessionRuntimePersistence
        } else {
            // A rule matched, so a file was loaded: `configuration` is only ever
            // populated from one.
            guard let configurationFile else { return }
            runtime = RepositoryRuntimePersistence(
                repository: runtimeRepository,
                configurationFile: configurationFile,
                now: now
            )
        }
        let coordinator = SessionGrantCoordinator(
            scheduler: scheduler,
            runtime: runtime,
            shield: shield,
            launcher: launcher,
            lock: stateLock
        )

        do {
            let result = try await coordinator.grant(rule: rule, now: now)
            isGrantRequested = false
            activationCoordinator.returnedToConfiguration()
            switch result {
            case .openedAutomatically:
                entryRoute = .configuration
            case let .readyForManualReturn(expiresAt):
                entryRoute = .manualReturn(
                    ManualReturnContent(
                        ruleID: rule.id,
                        applicationToken: entry.applicationToken,
                        expiresAt: expiresAt
                    )
                )
            }
        } catch {
            isGrantRequested = false
            activationCoordinator.returnedToConfiguration()
            entryRoute = .configuration
            presentedError = AppError(title: "Couldn't start session", error: error)
        }
    }

    func returnToConfiguration() {
        guard activationCoordinator.canDismissConfigurationRepair else {
            entryRoute = .repair(configurationSafetyRepairContent)
            return
        }
        isGrantRequested = false
        activationCoordinator.returnedToConfiguration()
        if activationRuntimeRepairs.isEmpty {
            entryRoute = .configuration
        } else {
            entryRoute = .repair(activationRuntimeRepairs.removeFirst())
        }
    }

    func resetRuntime(ruleID: UUID, now: Date = Date()) {
        guard activationCoordinator.configurationState == .knownGood,
              let runtimeRepository,
              let failedGrantBlockStore else { return }
        let coordinator = SessionReconciliationCoordinator(
            loadFailedGrantBlocks: failedGrantBlockStore.load
        )
        let reset = { [self] in
            coordinator.resetRuntime(
                ruleID: ruleID,
                logicalDay: logicalDay(at: now),
                saveRuntime: runtimeRepository.save,
                clearFailedGrantBlock: failedGrantBlockStore.clear,
                applyShields: {
                    guard canApplyManagedSettings else { return }
                    try shieldReconciler.reconcile(
                        configuration: configuration,
                        runtimeRepository: runtimeRepository,
                        now: now,
                        persistExpiredSessions: false
                    )
                }
            )
        }
        let result: SessionReconciliationResult
        do {
            result = try stateLock?.withLock(reset) ?? reset()
        } catch {
            result = SessionReconciliationResult(
                repairRuleIDs: [ruleID],
                issues: [
                    SessionReconciliationIssue(
                        ruleID: ruleID,
                        operation: .acquireStateLock,
                        underlyingError: error
                    )
                ]
            )
        }
        guard result.issues.isEmpty else {
            presentedError = AppError(title: "Couldn't reset this app", error: result)
            if let content = runtimeRepairContent(for: ruleID) {
                entryRoute = .repair(content)
            }
            return
        }
        returnToConfiguration()
    }

    func requestAuthorization() async {
        do {
            try await authorizationRequester()
            handleAuthorizationCompletion()
        } catch {
            handleAuthorizationCompletion()
            presentedError = AppError(title: "Screen Time access wasn't granted", error: error)
        }
    }

    func applyPickerSelection(now: Date = Date()) throws {
        guard configurationStore != nil, let runtimeRepository else {
            throw AppModelError.storageUnavailable
        }
        try requireConfigurationMutation(.pickerSelection)

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

        let today = logicalDay(at: now)
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
            try persist(nextConfiguration, now: now)
            activationCoordinator.configurationSaveCompleted(successfully: true)
        } catch let changeError {
            activationCoordinator.configurationSaveCompleted(successfully: false)
            var repairErrors: [Error] = []
            if activationCoordinator.configurationState == .knownGood {
                do {
                    try runtimeRepository.deleteOrphanedRuntimes(
                        keeping: Set(configuration.rules.map(\.id))
                    )
                } catch {
                    repairErrors.append(error)
                }
            }

            if !repairErrors.isEmpty {
                throw RuleRemovalFailure(
                    primaryError: changeError,
                    repairErrors: repairErrors
                )
            }
            throw changeError
        }

        // The picker mirrors the document in force today rather than the raw
        // tap: an app whose removal is scheduled is still shielded, so it is
        // still selected.
        var inForceSelection = FamilyActivitySelection()
        inForceSelection.applicationTokens = Set(configuration.targets.map(\.applicationToken))
        pickerSelection = inForceSelection

        guard removedRuleIDs.isEmpty else {
            // Dropping an app always loosens the rules, so the edit is
            // scheduled for the next reset and only the pending document is
            // written. Every rule in the save is still in force until then, so
            // their runtimes, shields and monitoring stay as they are.
            return
        }
        reconcileShieldsIfAuthorized(title: "Apps updated, but shields need repair")
    }

    func updateRule(
        id: UUID,
        sessionsPerDay: Int,
        sessionLengthMinutes: Int,
        now: Date = Date()
    ) throws {
        try requireConfigurationMutation(.ruleEdit)
        guard (1...20).contains(sessionsPerDay) else {
            throw AppModelError.invalidSessionsPerDay
        }
        guard (1...120).contains(sessionLengthMinutes) else {
            throw AppModelError.invalidSessionLength
        }
        guard configurationStore != nil else {
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
        do {
            try persist(nextConfiguration, now: now)
        } catch {
            activationCoordinator.configurationSaveCompleted(successfully: false)
            throw error
        }
        reconcileShieldsIfAuthorized(title: "Rule saved, but shields need repair")
    }

    func updatePauseSeconds(_ seconds: Int, now: Date = Date()) throws {
        try requireConfigurationMutation(.globalSettingsEdit)
        guard (1...120).contains(seconds) else {
            throw AppModelError.invalidPauseDuration
        }
        guard configurationStore != nil else {
            throw AppModelError.storageUnavailable
        }

        var nextConfiguration = configuration
        nextConfiguration.settings = try GlobalSettings(
            pauseSeconds: seconds,
            resetMinuteOfDay: configuration.settings.resetMinuteOfDay
        )
        do {
            try persist(nextConfiguration, now: now)
        } catch {
            activationCoordinator.configurationSaveCompleted(successfully: false)
            throw error
        }
    }

    func setResetMinuteOfDay(_ minute: Int, now: Date = Date()) throws {
        // Mirrors updatePauseSeconds: the same mutation gate runs first, so a
        // save that the coordinator is not ready for is refused the same way.
        try requireConfigurationMutation(.globalSettingsEdit)
        guard (0..<(24 * 60)).contains(minute),
              minute % GlobalSettings.resetMinuteStep == 0 else {
            throw AppModelError.invalidResetMinuteOfDay
        }
        guard configurationStore != nil else {
            throw AppModelError.storageUnavailable
        }

        var nextConfiguration = configuration
        nextConfiguration.settings = try GlobalSettings(
            pauseSeconds: configuration.settings.pauseSeconds,
            resetMinuteOfDay: minute
        )
        do {
            try persist(nextConfiguration, now: now)
        } catch {
            activationCoordinator.configurationSaveCompleted(successfully: false)
            throw error
        }
        // The registration names a wall-clock time, so replacing it has to happen
        // here rather than at the next activation: an app terminated before it is
        // backgrounded would otherwise leave iOS waking Pause at the old reset.
        // This reads the reset that took effect, not `minute`, so a save the
        // router deferred leaves the registration where it was.
        registerDailyReset()
    }

    /// Drops a scheduled change, leaving the rules in force today standing.
    func cancelScheduledChange(now: Date = Date()) {
        guard let configurationStore,
              let file = configurationFile,
              file.pending != nil else { return }
        // Cancelling a loosening leaves the stricter rule standing, which is a
        // tightening, so it applies at once.
        let kept = file.inForce(at: now)
        do {
            let cleared = ConfigurationFile(effective: kept, pending: nil)
            try configurationStore.save(file: cleared)
            configurationFile = cleared
            configuration = kept
            pendingChangeStartDay = nil
            lastSaveDeferredPart = false
        } catch {
            presentedError = AppError(title: "Couldn't cancel the change", error: error)
        }
    }

    func removeRule(id: UUID, now: Date = Date()) throws {
        try requireConfigurationMutation(.ruleRemoval)
        guard configurationStore != nil else {
            throw AppModelError.storageUnavailable
        }
        guard configuration.targets.contains(where: { $0.ruleID == id }) else {
            throw AppModelError.ruleNotFound
        }

        let nextConfiguration = try ConfigurationDocument(
            settings: configuration.settings,
            rules: configuration.rules.filter { $0.id != id },
            targets: configuration.targets.filter { $0.ruleID != id }
        )
        // Removing an app always loosens the rules, so the edit is scheduled
        // for the next reset and only the pending document is written. The rule
        // is still in force until then, so its runtime, its shield, its session
        // monitoring and its place in the picker all stay as they are.
        do {
            try persist(nextConfiguration, now: now)
        } catch {
            activationCoordinator.configurationSaveCompleted(successfully: false)
            throw error
        }
    }

    func present(_ error: Error, title: String = "Couldn't save changes") {
        presentedError = AppError(title: title, error: error)
    }

    var requiresConfigurationRepair: Bool {
        activationCoordinator.requiresConfigurationRepair
    }

    var configurationLoadState: ConfigurationLoadState {
        activationCoordinator.configurationState
    }

    /// What a scheduled change does, for the notice to name. Empty once the
    /// change lands, because `configuration` is then the pending document and
    /// there is nothing between the two.
    var scheduledChanges: [ScheduledChange] {
        guard let pending = configurationFile?.pending else { return [] }
        return ScheduledChangeWording.changes(from: configuration, to: pending.document)
    }

    /// Rules the in-force document still covers that a scheduled change drops.
    ///
    /// Once the change lands, `configuration` is the pending document, so this
    /// is empty and the rows stop being marked without a flag to clear.
    var ruleIDsPendingRemoval: Set<UUID> {
        guard let pending = configurationFile?.pending else { return [] }
        let pendingRuleIDs = Set(pending.document.rules.map(\.id))
        return Set(configuration.rules.map(\.id)).subtracting(pendingRuleIDs)
    }

    var rootRoute: AppRootRoute {
        if requiresConfigurationRepair {
            return .configurationRepair
        }
        return canApplyManagedSettings ? .authorizedContent : .authorization
    }

    var configurationSafetyRepairContent: RepairContent {
        switch activationCoordinator.configurationState {
        case .failed:
            RepairContent(
                applicationToken: nil,
                title: "Pause couldn't load its configuration",
                message: "Saved rules couldn't be read safely. Existing apps remain blocked. Close and reopen Pause after repairing the saved data."
            )
        case .missing, .knownGood:
            RepairContent(
                applicationToken: nil,
                title: "Pause can't safely rebuild its app list",
                message: "Saved rules are missing while protected app state remains. Existing apps stay blocked."
            )
        }
    }

    private func cleanupOrphanedRuntimes() {
        guard activationCoordinator.configurationState == .knownGood,
              let runtimeRepository,
              let failedGrantBlockStore else { return }
        if let cleanupOverride {
            cleanupOverride()
            return
        }
        do {
            let configuredRuleIDs = Set(configuration.rules.map(\.id))
            let cleanup = {
                try runtimeRepository.deleteOrphanedRuntimes(keeping: configuredRuleIDs)
                let markerIDs = try failedGrantBlockStore.load()
                for orphanRuleID in markerIDs.subtracting(configuredRuleIDs) {
                    try failedGrantBlockStore.clear(ruleID: orphanRuleID)
                }
            }
            try stateLock?.withLock(cleanup) ?? cleanup()
        } catch {
            presentedError = AppError(title: "Couldn't finish app-data cleanup", error: error)
        }
    }

    private func requireConfigurationMutation(_ mutation: ConfigurationMutation) throws {
        guard activationCoordinator.allowsConfigurationMutation(mutation) else {
            throw AppModelError.unsafeConfiguration
        }
    }

    private func handleAuthorizationCompletion() {
        refreshAuthorizationStatus()

        guard isSceneActive else {
            activationCoordinator.authorizationDidChange()
            authorizationStatusAtLastActivation = nil
            return
        }
        guard authorizationStatusAtLastActivation != authorizationStatus else { return }

        activationCoordinator.authorizationDidChange()
        sceneDidBecomeActive()
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

        let runtime: RuleRuntime
        do {
            guard let loadedRuntime = try runtimeRepository.load(ruleID: rule.id) else {
                throw RuleLookupError.runtimeNotFound(rule.id)
            }
            runtime = loadedRuntime
        } catch {
            return PauseActivationResolution(
                payload: .repair(
                    runtimeRepairContent(for: rule.id)
                        ?? RepairContent(
                            applicationToken: target.applicationToken,
                            title: "This app's runtime needs repair",
                            message: "Pause kept this app blocked because its session data couldn't be read or repaired.",
                            runtimeResetRuleID: rule.id
                        )
                ),
                performMaintenance: false
            )
        }
        let evaluation = RuleLookup.evaluate(
            rule: rule,
            runtime: runtime,
            logicalDay: logicalDay(at: now),
            now: now
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

    /// Writes an edited document through the router, so a loosening edit is
    /// scheduled rather than applied.
    private func persist(_ candidate: ConfigurationDocument, now: Date = Date()) throws {
        guard let configurationStore else { throw AppModelError.storageUnavailable }
        let existing = try configurationStore.loadFile()
            ?? ConfigurationFile(effective: candidate, pending: nil)
        let routed = try ConfigurationSaveRouter.route(
            candidate: candidate,
            into: existing,
            now: now
        )
        try configurationStore.save(file: routed)
        configurationFile = routed
        configuration = routed.inForce(at: now)
        pendingChangeStartDay = Self.scheduledStartDay(in: routed, now: now)
        lastSaveDeferredPart = routed.effective != candidate
    }

    /// The start day of a change that has not arrived yet. A pending document is
    /// selected at read time rather than promoted, so the file still names one
    /// after its start day arrives; a start day that has arrived is in force,
    /// not scheduled.
    private static func scheduledStartDay(in file: ConfigurationFile, now: Date) -> CalendarDay? {
        guard let startDay = file.pending?.startDay,
              startDay > file.logicalDay(at: now) else { return nil }
        return startDay
    }

    /// The allowance day, resolved from the file's effective document — the one
    /// reset that may decide it.
    ///
    /// With no file there are no saved settings to read: `configuration` is then
    /// the empty document, whose reset is a default rather than anything the user
    /// chose. So the fallback is the civil date, written as the midnight reset it
    /// is, rather than a reset taken from a document that may be a pending one.
    private func logicalDay(at now: Date) -> CalendarDay {
        configurationFile?.logicalDay(at: now)
            ?? LogicalDay.containing(now, resetMinuteOfDay: 0, calendar: .current)
    }

    /// Re-selects the document in force for the day Pause is being opened on, so
    /// a change that reached its start day while the app was away takes hold
    /// without a relaunch. The file in hand holds both documents, so this reads
    /// nothing from disk.
    private func refreshInForceConfiguration(now: Date) {
        guard let configurationFile else { return }
        configuration = configurationFile.inForce(at: now)
        pendingChangeStartDay = Self.scheduledStartDay(in: configurationFile, now: now)
        pickerSelection.applicationTokens = Set(configuration.targets.map(\.applicationToken))
    }

    private func reconcileShieldsIfAuthorized(
        title: String = "Pause needs repair"
    ) {
        guard activationCoordinator.configurationState == .knownGood,
              canApplyManagedSettings,
              let runtimeRepository else { return }
        if let reconciliationOverride {
            reconciliationOverride()
            return
        }
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

    /// Re-registers the repeating daily activity that wakes the monitor at the
    /// reset. Registering under a name already registered replaces its schedule,
    /// so running this on every activation keeps one registration, not many.
    ///
    /// A failure here is logged rather than surfaced: the user cannot act on it,
    /// and the next activation both retries the registration and reconciles the
    /// state the reset would have handled.
    private func registerDailyReset() {
        guard canApplyManagedSettings else { return }
        do {
            try DailyResetScheduler(center: activityCenter).register(
                resetMinuteOfDay: configuration.settings.resetMinuteOfDay
            )
        } catch {
            Logger(subsystem: "com.koubalabs.pause", category: "dailyReset").error(
                "Could not register the daily reset activity: \(error.localizedDescription, privacy: .public)"
            )
        }
    }

    private func reconcileSessionsIfAuthorized(now: Date) {
        guard activationCoordinator.configurationState == .knownGood,
              canApplyManagedSettings,
              let runtimeRepository,
              let failedGrantBlockStore else { return }
        if let reconciliationOverride {
            reconciliationOverride()
            return
        }

        let coordinator = SessionReconciliationCoordinator(
            loadFailedGrantBlocks: failedGrantBlockStore.load
        )
        let reconcile = { [self] in
            coordinator.reconcile(
                ruleIDs: configuration.rules.map(\.id),
                now: now,
                trigger: .appActivation,
                loadRuntime: runtimeRepository.load,
                saveRuntime: runtimeRepository.save,
                clearFailedGrantBlock: failedGrantBlockStore.clear,
                applyShields: {
                    try shieldReconciler.reconcile(
                        configuration: configuration,
                        runtimeRepository: runtimeRepository,
                        now: now
                    )
                },
                stopMonitoring: { _ in }
            )
        }
        let result: SessionReconciliationResult
        do {
            result = try stateLock?.withLock(reconcile) ?? reconcile()
        } catch {
            result = SessionReconciliationResult(
                repairRuleIDs: Set(configuration.rules.map(\.id)),
                issues: [
                    SessionReconciliationIssue(
                        ruleID: nil,
                        operation: .acquireStateLock,
                        underlyingError: error
                    )
                ]
            )
        }
        activationRuntimeRepairs = result.repairRuleIDs
            .sorted { $0.uuidString < $1.uuidString }
            .compactMap(runtimeRepairContent)
        if !result.issues.isEmpty {
            presentedError = AppError(title: "Pause needs repair", error: result)
        }
    }

    private func runtimeRepairContent(for ruleID: UUID) -> RepairContent? {
        guard let target = configuration.targets.first(where: { $0.ruleID == ruleID }) else {
            return nil
        }
        return RepairContent(
            applicationToken: target.applicationToken,
            title: "This app's runtime needs repair",
            message: "Pause kept this app blocked because its session data couldn't be read or repaired.",
            runtimeResetRuleID: ruleID
        )
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
