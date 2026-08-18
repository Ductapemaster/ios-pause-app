import Foundation
import PauseCore

public final class RuntimeRepository: @unchecked Sendable {
    private let directoryURL: URL
    private let stateLock: AppGroupFileLock

    public init(directoryURL: URL) {
        self.directoryURL = directoryURL
        stateLock = AppGroupFileLock(directoryURL: directoryURL)
    }

    public func load(ruleID: UUID) throws -> RuleRuntime? {
        try stateLock.withLock { try loadUnlocked(ruleID: ruleID) }
    }

    public func save(_ runtime: RuleRuntime, ruleID: UUID) throws {
        try stateLock.withLock { try saveUnlocked(runtime, ruleID: ruleID) }
    }

    public func delete(ruleID: UUID) throws {
        try stateLock.withLock { try file(for: ruleID).delete() }
    }

    public func stageRemoval(ruleID: UUID) throws -> StagedRuntimeRemoval {
        try stateLock.withLock {
            let originalURL = fileURL(for: ruleID)
            let stagedURL = stagedFileURL(for: ruleID)
            let fileManager = FileManager.default
            let originalExists = fileManager.fileExists(atPath: originalURL.path)
            let stagedExists = fileManager.fileExists(atPath: stagedURL.path)

            if stagedExists {
                guard try isRegularFile(at: stagedURL) else {
                    throw PersistenceError.invalidStagedRuntimeFile(ruleID)
                }
                if !originalExists {
                    return StagedRuntimeRemoval(ruleID: ruleID, wasPresent: true)
                }
            }
            guard originalExists else {
                return StagedRuntimeRemoval(ruleID: ruleID, wasPresent: false)
            }
            guard try isRegularFile(at: originalURL) else {
                throw PersistenceError.invalidRuntimeFile(ruleID)
            }

            if stagedExists {
                try fileManager.removeItem(at: stagedURL)
            }
            try fileManager.moveItem(at: originalURL, to: stagedURL)
            return StagedRuntimeRemoval(ruleID: ruleID, wasPresent: true)
        }
    }

    public func restoreRemoval(_ stage: StagedRuntimeRemoval) throws {
        guard stage.wasPresent else { return }
        try stateLock.withLock {
            let originalURL = fileURL(for: stage.ruleID)
            let stagedURL = stagedFileURL(for: stage.ruleID)
            guard FileManager.default.fileExists(atPath: stagedURL.path) else {
                throw PersistenceError.missingStagedRuntime(stage.ruleID)
            }
            guard try isRegularFile(at: stagedURL) else {
                throw PersistenceError.invalidStagedRuntimeFile(stage.ruleID)
            }
            guard !FileManager.default.fileExists(atPath: originalURL.path) else {
                throw PersistenceError.runtimeRestoreDestinationExists(stage.ruleID)
            }
            try FileManager.default.moveItem(at: stagedURL, to: originalURL)
        }
    }

    public func finalizeRemoval(_ stage: StagedRuntimeRemoval) throws {
        guard stage.wasPresent else { return }
        try stateLock.withLock {
            let stagedURL = stagedFileURL(for: stage.ruleID)
            guard FileManager.default.fileExists(atPath: stagedURL.path) else {
                throw PersistenceError.missingStagedRuntime(stage.ruleID)
            }
            guard try isRegularFile(at: stagedURL) else {
                throw PersistenceError.invalidStagedRuntimeFile(stage.ruleID)
            }
            try FileManager.default.removeItem(at: stagedURL)
        }
    }

    public func deleteOrphanedRuntimes(keeping ruleIDs: Set<UUID>) throws {
        try stateLock.withLock {
            let fileURLs = try FileManager.default.contentsOfDirectory(
                at: directoryURL,
                includingPropertiesForKeys: [.isRegularFileKey]
            )
            for fileURL in fileURLs {
                let resourceValues = try fileURL.resourceValues(forKeys: [.isRegularFileKey])
                guard resourceValues.isRegularFile == true else { continue }
                guard let ruleID = ruleID(for: fileURL), !ruleIDs.contains(ruleID) else {
                    continue
                }
                try FileManager.default.removeItem(at: fileURL)
            }
        }
    }

    public func update(
        ruleID: UUID,
        _ mutation: (inout RuleRuntime) throws -> Void
    ) throws -> RuleRuntime {
        try stateLock.withLock {
            guard var runtime = try loadUnlocked(ruleID: ruleID) else {
                throw PersistenceError.missingRuntime(ruleID)
            }
            try mutation(&runtime)
            try saveUnlocked(runtime, ruleID: ruleID)
            return runtime
        }
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

    private func isRegularFile(at url: URL) throws -> Bool {
        try url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true
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
