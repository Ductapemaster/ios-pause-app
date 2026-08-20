import Foundation

public struct ConfigurationStore {
    private let file: AtomicJSONFile<ConfigurationDocument>
    private let stateLock: AppGroupFileLock

    public init(directoryURL: URL) {
        file = AtomicJSONFile(url: directoryURL.appendingPathComponent(SharedIdentifiers.configurationFilename))
        stateLock = AppGroupFileLock(directoryURL: directoryURL)
    }

    public init(appGroupContainer: AppGroupContainer = AppGroupContainer()) throws {
        self.init(directoryURL: try appGroupContainer.directoryURL())
    }

    public func load() throws -> ConfigurationDocument? {
        try stateLock.withLock {
            guard let document = try file.load() else {
                return nil
            }
            try document.validate()
            return document
        }
    }

    /// Reads without taking the state lock. See `RuntimeRepository.loadWithoutLocking`.
    public func loadWithoutLocking() throws -> ConfigurationDocument? {
        guard let document = try file.load() else {
            return nil
        }
        try document.validate()
        return document
    }

    public func save(_ document: ConfigurationDocument) throws {
        try stateLock.withLock {
            try document.validate()
            try file.save(document)
        }
    }
}
