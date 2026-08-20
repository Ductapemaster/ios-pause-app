import Foundation
import ManagedSettings
import PauseCore

/// Resolves what a shield should display, reading only.
///
/// The shield configuration extension runs under the
/// `managed-settings-shield-configuration` sandbox profile, which refuses every
/// write in the app group container — including `open(O_CREAT)` on the state
/// lock file. Taking the lock therefore fails before any read happens, which is
/// why this path must not take it.
///
/// Reading without the lock is safe here because every writer persists through
/// `AtomicJSONFile`, which replaces a file atomically: a reader sees the whole
/// previous file or the whole next one, never a partial write. The configuration
/// and the runtime are read as two separate files, so a write landing between
/// them can leave the pair one step apart. `RuleLookup.resolve` already treats a
/// rule it cannot match as `targetNotFound`, which surfaces as the repair
/// presentation, and the next render corrects it.
public struct ShieldStateReader {
    private let configurationStore: ConfigurationStore
    private let runtimeReader: RuntimeReading

    public init(directoryURL: URL) {
        configurationStore = ConfigurationStore(directoryURL: directoryURL)
        runtimeReader = UnlockedRuntimeReader(
            repository: RuntimeRepository(directoryURL: directoryURL)
        )
    }

    public init(appGroupContainer: AppGroupContainer = AppGroupContainer()) throws {
        self.init(directoryURL: try appGroupContainer.directoryURL())
    }

    public func presentation(
        for applicationToken: ApplicationToken,
        now: Date,
        calendar: Calendar = .current
    ) throws -> ShieldPresentation {
        guard let configuration = try configurationStore.loadWithoutLocking() else {
            throw RuleLookupError.targetNotFound
        }
        let resolved = try RuleLookup.resolve(
            applicationToken: applicationToken,
            configuration: configuration,
            runtimeRepository: runtimeReader,
            now: now,
            calendar: calendar
        )
        return ShieldPresentation(
            rule: resolved.rule,
            decision: resolved.evaluation.decision
        )
    }
}

/// Routes `RuleLookup`'s runtime read to the repository's lock-free path.
private struct UnlockedRuntimeReader: RuntimeReading {
    let repository: RuntimeRepository

    func load(ruleID: UUID) throws -> RuleRuntime? {
        try repository.loadWithoutLocking(ruleID: ruleID)
    }
}
