import Foundation

public enum FailedGrantBlockStoreError: LocalizedError, Equatable {
    case unsupportedVersion(Int)

    public var errorDescription: String? {
        switch self {
        case let .unsupportedVersion(version):
            "Pause cannot read failed-session block data version \(version)."
        }
    }
}

@MainActor
public protocol FailedGrantBlockStoring {
    func load() throws -> Set<UUID>
    func add(ruleID: UUID) throws
    func clear(ruleID: UUID) throws
    func contains(ruleID: UUID) throws -> Bool
}

@MainActor
public final class FailedGrantBlockStore: FailedGrantBlockStoring {
    private struct Document: Codable {
        static let currentVersion = 1

        let version: Int
        var ruleIDs: Set<UUID>
    }

    private let file: AtomicJSONFile<Document>

    public init(directoryURL: URL) {
        file = AtomicJSONFile(
            url: directoryURL.appendingPathComponent(SharedIdentifiers.failedGrantBlocksFilename)
        )
    }

    public func load() throws -> Set<UUID> {
        guard let document = try file.load() else { return [] }
        guard document.version == Document.currentVersion else {
            throw FailedGrantBlockStoreError.unsupportedVersion(document.version)
        }
        return document.ruleIDs
    }

    public func add(ruleID: UUID) throws {
        var ruleIDs = try load()
        ruleIDs.insert(ruleID)
        try save(ruleIDs)
    }

    public func clear(ruleID: UUID) throws {
        var ruleIDs = try load()
        ruleIDs.remove(ruleID)
        try save(ruleIDs)
    }

    public func contains(ruleID: UUID) throws -> Bool {
        try load().contains(ruleID)
    }

    private func save(_ ruleIDs: Set<UUID>) throws {
        try file.save(Document(version: Document.currentVersion, ruleIDs: ruleIDs))
    }
}
