import Foundation
import PauseCore

public final class RuntimeRepository: @unchecked Sendable {
    private let directoryURL: URL
    private let lock = NSLock()

    public init(directoryURL: URL) {
        self.directoryURL = directoryURL
    }

    public func load(ruleID: UUID) throws -> RuleRuntime? {
        lock.lock()
        defer { lock.unlock() }
        return try loadUnlocked(ruleID: ruleID)
    }

    public func save(_ runtime: RuleRuntime, ruleID: UUID) throws {
        lock.lock()
        defer { lock.unlock() }
        try saveUnlocked(runtime, ruleID: ruleID)
    }

    public func delete(ruleID: UUID) throws {
        lock.lock()
        defer { lock.unlock() }
        try file(for: ruleID).delete()
    }

    public func stageRemoval(ruleID: UUID) throws -> StagedRuntimeRemoval {
        lock.lock()
        defer { lock.unlock() }

        let originalURL = fileURL(for: ruleID)
        let stagedURL = stagedFileURL(for: ruleID)
        guard !FileManager.default.fileExists(atPath: stagedURL.path) else {
            throw PersistenceError.stagedRuntimeAlreadyExists(ruleID)
        }
        guard FileManager.default.fileExists(atPath: originalURL.path) else {
            return StagedRuntimeRemoval(ruleID: ruleID, wasPresent: false)
        }
        let resourceValues = try originalURL.resourceValues(forKeys: [.isRegularFileKey])
        guard resourceValues.isRegularFile == true else {
            throw PersistenceError.invalidRuntimeFile(ruleID)
        }

        try FileManager.default.moveItem(at: originalURL, to: stagedURL)
        return StagedRuntimeRemoval(ruleID: ruleID, wasPresent: true)
    }

    public func restoreRemoval(_ stage: StagedRuntimeRemoval) throws {
        guard stage.wasPresent else { return }
        lock.lock()
        defer { lock.unlock() }

        let originalURL = fileURL(for: stage.ruleID)
        let stagedURL = stagedFileURL(for: stage.ruleID)
        guard FileManager.default.fileExists(atPath: stagedURL.path) else {
            throw PersistenceError.missingStagedRuntime(stage.ruleID)
        }
        guard !FileManager.default.fileExists(atPath: originalURL.path) else {
            throw PersistenceError.runtimeRestoreDestinationExists(stage.ruleID)
        }
        try FileManager.default.moveItem(at: stagedURL, to: originalURL)
    }

    public func finalizeRemoval(_ stage: StagedRuntimeRemoval) throws {
        guard stage.wasPresent else { return }
        lock.lock()
        defer { lock.unlock() }

        let stagedURL = stagedFileURL(for: stage.ruleID)
        guard FileManager.default.fileExists(atPath: stagedURL.path) else {
            throw PersistenceError.missingStagedRuntime(stage.ruleID)
        }
        try FileManager.default.removeItem(at: stagedURL)
    }

    public func deleteOrphanedRuntimes(keeping ruleIDs: Set<UUID>) throws {
        lock.lock()
        defer { lock.unlock() }

        let fileURLs = try FileManager.default.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: [.isRegularFileKey]
        )
        for fileURL in fileURLs {
            let resourceValues = try fileURL.resourceValues(forKeys: [.isRegularFileKey])
            guard resourceValues.isRegularFile == true else { continue }
            guard let ruleID = ruleID(for: fileURL), !ruleIDs.contains(ruleID) else { continue }
            try FileManager.default.removeItem(at: fileURL)
        }
    }

    public func update(
        ruleID: UUID,
        _ mutation: (inout RuleRuntime) throws -> Void
    ) throws -> RuleRuntime {
        lock.lock()
        defer { lock.unlock() }

        guard var runtime = try loadUnlocked(ruleID: ruleID) else {
            throw PersistenceError.missingRuntime(ruleID)
        }
        try mutation(&runtime)
        try saveUnlocked(runtime, ruleID: ruleID)
        return runtime
    }

    private func loadUnlocked(ruleID: UUID) throws -> RuleRuntime? {
        try file(for: ruleID).load()
    }

    private func saveUnlocked(_ runtime: RuleRuntime, ruleID: UUID) throws {
        try file(for: ruleID).save(runtime)
    }

    private func file(for ruleID: UUID) -> AtomicJSONFile<RuleRuntime> {
        AtomicJSONFile(url: fileURL(for: ruleID))
    }

    private func fileURL(for ruleID: UUID) -> URL {
        directoryURL.appendingPathComponent("runtime-\(ruleID.uuidString.lowercased()).json")
    }

    private func stagedFileURL(for ruleID: UUID) -> URL {
        directoryURL.appendingPathComponent(
            "runtime-\(ruleID.uuidString.lowercased()).json.removal-stage"
        )
    }

    private func ruleID(for fileURL: URL) -> UUID? {
        let filename = fileURL.lastPathComponent
        let prefix = "runtime-"
        let suffix = ".json"
        guard filename.hasPrefix(prefix), filename.hasSuffix(suffix) else { return nil }

        let idStart = filename.index(filename.startIndex, offsetBy: prefix.count)
        let idEnd = filename.index(filename.endIndex, offsetBy: -suffix.count)
        let idString = String(filename[idStart..<idEnd])
        guard let ruleID = UUID(uuidString: idString) else { return nil }
        guard filename == "runtime-\(ruleID.uuidString.lowercased()).json" else { return nil }
        return ruleID
    }
}
