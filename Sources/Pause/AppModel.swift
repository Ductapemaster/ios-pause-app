import Combine
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

private struct SelectionRollbackError: LocalizedError {
    let saveError: Error
    let cleanupError: Error

    var errorDescription: String? {
        "The app selection couldn't be saved (\(saveError.localizedDescription)). Pause also couldn't remove incomplete runtime data (\(cleanupError.localizedDescription)); it will try again when the app becomes active."
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
    private var configurationStore: ConfigurationStore?
    private var runtimeRepository: RuntimeRepository?

    init(
        authorizationCenter: AuthorizationCenter = .shared,
        appGroupContainer: AppGroupContainer = AppGroupContainer()
    ) {
        self.authorizationCenter = authorizationCenter
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
        } catch {
            presentedError = AppError(title: "Couldn't load Pause", error: error)
        }
    }

    func refreshAuthorizationStatus() {
        authorizationStatus = authorizationCenter.authorizationStatus
        cleanupOrphanedRuntimes()
    }

    func requestAuthorization() async {
        do {
            try await authorizationCenter.requestAuthorization(for: .individual)
            authorizationStatus = authorizationCenter.authorizationStatus
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
            try configurationStore.save(nextConfiguration)
            configuration = nextConfiguration
        } catch let saveError {
            do {
                try runtimeRepository.deleteOrphanedRuntimes(
                    keeping: Set(configuration.rules.map(\.id))
                )
            } catch let cleanupError {
                throw SelectionRollbackError(saveError: saveError, cleanupError: cleanupError)
            }
            throw saveError
        }

        var normalizedSelection = FamilyActivitySelection()
        normalizedSelection.applicationTokens = selectedTokens
        pickerSelection = normalizedSelection

        let removedRuleIDs = existingTargets.compactMap { target in
            removedTokens.contains(target.applicationToken) ? target.ruleID : nil
        }
        var removalError: Error?
        for ruleID in removedRuleIDs {
            do {
                try runtimeRepository.delete(ruleID: ruleID)
            } catch {
                removalError = removalError ?? error
            }
        }
        if let removalError {
            presentedError = AppError(title: "Apps updated, but cleanup failed", error: removalError)
        }
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
        guard let target = configuration.targets.first(where: { $0.ruleID == id }) else {
            throw AppModelError.ruleNotFound
        }

        let previousSelection = pickerSelection
        pickerSelection.applicationTokens.remove(target.applicationToken)
        do {
            try applyPickerSelection()
        } catch {
            pickerSelection = previousSelection
            throw error
        }
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

    private static var emptyConfiguration: ConfigurationDocument {
        try! ConfigurationDocument(settings: .phaseOneDefault, rules: [], targets: [])
    }
}
