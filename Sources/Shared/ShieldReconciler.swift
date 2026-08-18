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

@MainActor
public struct ShieldReconciler {
    private let currentApplications: () -> Set<ApplicationToken>?
    private let applyApplications: (Set<ApplicationToken>) -> Void

    public init(store: ManagedSettingsStore = ManagedSettingsStore()) {
        currentApplications = { store.shield.applications }
        applyApplications = { store.shield.applications = $0 }
    }

    init(
        currentApplications: @escaping () -> Set<ApplicationToken>?,
        applyApplications: @escaping (Set<ApplicationToken>) -> Void
    ) {
        self.currentApplications = currentApplications
        self.applyApplications = applyApplications
    }

    public func reconcile(
        configuration: ConfigurationDocument,
        runtimeRepository: RuntimeRepository,
        now: Date,
        forceShieldedRuleIDs: Set<UUID> = []
    ) throws {
        var shieldedApplications = Set(configuration.targets.map(\.applicationToken))
        var unreadableRuleIDs: [UUID] = []

        for target in configuration.targets {
            guard !forceShieldedRuleIDs.contains(target.ruleID) else { continue }
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

        applyApplications(shieldedApplications)

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

        var shieldedApplications = currentApplications() ?? []
        shieldedApplications.remove(target.applicationToken)
        applyApplications(shieldedApplications)
    }
}
