import Foundation
import ManagedSettings
import PauseCore

public enum ShieldReconciliationError: LocalizedError, Equatable {
    case unreadableRuntimes([UUID])

    public var errorDescription: String? {
        switch self {
        case let .unreadableRuntimes(ruleIDs):
            let count = ruleIDs.count
            return "Pause kept \(count) app\(count == 1 ? "" : "s") blocked because \(count == 1 ? "its" : "their") session data could not be read or repaired. Open each affected app in Pause to repair it."
        }
    }
}

public struct ShieldReconciler {
    private let store: ManagedSettingsStore

    public init(store: ManagedSettingsStore = ManagedSettingsStore()) {
        self.store = store
    }

    public func reconcile(
        configuration: ConfigurationDocument,
        runtimeRepository: RuntimeRepository,
        now: Date
    ) throws {
        var shieldedApplications = Set(configuration.targets.map(\.applicationToken))
        var unreadableRuleIDs: [UUID] = []

        for target in configuration.targets {
            do {
                guard var runtime = try runtimeRepository.load(ruleID: target.ruleID) else {
                    unreadableRuleIDs.append(target.ruleID)
                    continue
                }

                if let openSession = runtime.openSession, openSession.expiresAt > now {
                    shieldedApplications.remove(target.applicationToken)
                    continue
                }

                if runtime.openSession != nil {
                    runtime.clearExpiredSession(at: now)
                    try runtimeRepository.save(runtime, ruleID: target.ruleID)
                }
            } catch {
                unreadableRuleIDs.append(target.ruleID)
            }
        }

        store.shield.applications = shieldedApplications

        guard unreadableRuleIDs.isEmpty else {
            throw ShieldReconciliationError.unreadableRuntimes(
                unreadableRuleIDs.sorted { $0.uuidString < $1.uuidString }
            )
        }
    }

    public func unshield(ruleID: UUID, configuration: ConfigurationDocument) throws {
        let matchingTargets = configuration.targets.filter { $0.ruleID == ruleID }
        guard matchingTargets.count == 1, let target = matchingTargets.first else {
            throw RuleLookupError.ruleNotFound(ruleID)
        }

        var shieldedApplications = store.shield.applications ?? []
        shieldedApplications.remove(target.applicationToken)
        store.shield.applications = shieldedApplications
    }
}
