import Foundation
import ManagedSettings
import PauseCore

public enum ShieldReconciliationError: LocalizedError, Equatable {
    case unreadableRuntimes([UUID])
    case unreadableFailedGrantBlocks

    public var errorDescription: String? {
        switch self {
        case let .unreadableRuntimes(ruleIDs):
            let count = ruleIDs.count
            return "Pause kept \(count) app\(count == 1 ? "" : "s") blocked because \(count == 1 ? "its" : "their") session data could not be read or repaired. Open each affected app in Pause to repair it."
        case .unreadableFailedGrantBlocks:
            return "Pause kept all configured apps blocked because failed-session block data could not be read."
        }
    }
}

public struct ShieldReconciler {
    private let currentApplications: () -> Set<ApplicationToken>?
    private let applyApplications: (Set<ApplicationToken>) -> Void
    private let failedGrantBlockIDs: () throws -> Set<UUID>
    private let stateLockProvider: () throws -> AppGroupFileLock?

    public init(
        store: ManagedSettingsStore = ManagedSettingsStore(),
        appGroupContainer: AppGroupContainer = AppGroupContainer()
    ) {
        currentApplications = { store.shield.applications }
        applyApplications = { store.shield.applications = $0 }
        failedGrantBlockIDs = {
            let directoryURL = try appGroupContainer.directoryURL()
            return try FailedGrantBlockFileStore(directoryURL: directoryURL).load()
        }
        stateLockProvider = {
            AppGroupFileLock(directoryURL: try appGroupContainer.directoryURL())
        }
    }

    init(
        currentApplications: @escaping () -> Set<ApplicationToken>?,
        applyApplications: @escaping (Set<ApplicationToken>) -> Void,
        failedGrantBlockIDs: @escaping () throws -> Set<UUID>,
        stateLock: AppGroupFileLock? = nil
    ) {
        self.currentApplications = currentApplications
        self.applyApplications = applyApplications
        self.failedGrantBlockIDs = failedGrantBlockIDs
        stateLockProvider = { stateLock }
    }

    public func reconcile(
        configuration: ConfigurationDocument,
        runtimeRepository: RuntimeRepository,
        now: Date,
        forceShieldedRuleIDs: Set<UUID> = [],
        persistExpiredSessions: Bool = true
    ) throws {
        try withStateLock {
            try reconcileUnlocked(
                configuration: configuration,
                runtimeRepository: runtimeRepository,
                now: now,
                forceShieldedRuleIDs: forceShieldedRuleIDs,
                persistExpiredSessions: persistExpiredSessions
            )
        }
    }

    private func reconcileUnlocked(
        configuration: ConfigurationDocument,
        runtimeRepository: RuntimeRepository,
        now: Date,
        forceShieldedRuleIDs: Set<UUID>,
        persistExpiredSessions: Bool
    ) throws {
        var shieldedApplications = Set(configuration.targets.map(\.applicationToken))
        var unreadableRuleIDs: [UUID] = []
        let durableFailedGrantRuleIDs: Set<UUID>

        do {
            durableFailedGrantRuleIDs = try failedGrantBlockIDs()
        } catch {
            applyApplications(shieldedApplications)
            throw ShieldReconciliationError.unreadableFailedGrantBlocks
        }
        let requiredShieldRuleIDs = forceShieldedRuleIDs.union(durableFailedGrantRuleIDs)

        for target in configuration.targets {
            guard !requiredShieldRuleIDs.contains(target.ruleID) else { continue }
            do {
                guard var runtime = try runtimeRepository.load(ruleID: target.ruleID) else {
                    unreadableRuleIDs.append(target.ruleID)
                    continue
                }

                if let openSession = runtime.openSession, openSession.expiresAt > now {
                    shieldedApplications.remove(target.applicationToken)
                    continue
                }

                if runtime.openSession != nil, persistExpiredSessions {
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
        try withStateLock {
            try unshieldUnlocked(ruleID: ruleID, configuration: configuration)
        }
    }

    private func unshieldUnlocked(ruleID: UUID, configuration: ConfigurationDocument) throws {
        let matchingTargets = configuration.targets.filter { $0.ruleID == ruleID }
        guard matchingTargets.count == 1, let target = matchingTargets.first else {
            throw RuleLookupError.ruleNotFound(ruleID)
        }

        var shieldedApplications = currentApplications() ?? []
        shieldedApplications.remove(target.applicationToken)
        applyApplications(shieldedApplications)
    }

    public func forceShield(ruleID: UUID, configuration: ConfigurationDocument) throws {
        try withStateLock {
            let token = try applicationToken(ruleID: ruleID, configuration: configuration)
            forceShieldUnlocked(applicationToken: token)
        }
    }

    func applicationToken(
        ruleID: UUID,
        configuration: ConfigurationDocument
    ) throws -> ApplicationToken {
        let matchingTargets = configuration.targets.filter { $0.ruleID == ruleID }
        guard matchingTargets.count == 1, let target = matchingTargets.first else {
            throw RuleLookupError.ruleNotFound(ruleID)
        }
        return target.applicationToken
    }

    func forceShield(applicationToken: ApplicationToken) throws {
        try withStateLock {
            forceShieldUnlocked(applicationToken: applicationToken)
        }
    }

    private func forceShieldUnlocked(applicationToken: ApplicationToken) {
        var shieldedApplications = currentApplications() ?? []
        shieldedApplications.insert(applicationToken)
        applyApplications(shieldedApplications)
    }

    func withStateLock<T>(_ body: () throws -> T) throws -> T {
        if let stateLock = try stateLockProvider() {
            return try stateLock.withLock(body)
        }
        return try body()
    }
}
