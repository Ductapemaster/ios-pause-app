import Foundation

public struct ConfigurationStore {
    private let file: AtomicJSONFile<ConfigurationFile>
    private let legacyFile: AtomicJSONFile<ConfigurationDocument>
    private let stateLock: AppGroupFileLock

    public init(directoryURL: URL) {
        let url = directoryURL.appendingPathComponent(SharedIdentifiers.configurationFilename)
        file = AtomicJSONFile(url: url)
        legacyFile = AtomicJSONFile(url: url)
        stateLock = AppGroupFileLock(directoryURL: directoryURL)
    }

    public init(appGroupContainer: AppGroupContainer = AppGroupContainer()) throws {
        self.init(directoryURL: try appGroupContainer.directoryURL())
    }

    public func loadFile() throws -> ConfigurationFile? {
        try stateLock.withLock { try loadFileUnlocked() }
    }

    /// Reads without taking the state lock. See `RuntimeRepository.loadWithoutLocking`.
    public func loadFileWithoutLocking() throws -> ConfigurationFile? {
        try loadFileUnlocked()
    }

    public func save(file document: ConfigurationFile) throws {
        try stateLock.withLock {
            try document.effective.validate()
            try document.pending?.document.validate()
            try file.save(document)
        }
    }

    private func loadFileUnlocked() throws -> ConfigurationFile? {
        guard try carriesTheWrapper() else {
            guard let legacy = try legacyFile.load() else { return nil }
            try legacy.validate()
            return ConfigurationFile(effective: legacy, pending: nil)
        }
        guard let loaded = try file.load() else { return nil }
        try loaded.effective.validate()
        try loaded.pending?.document.validate()
        return loaded
    }

    /// Which of the two shapes the file holds. A build before deferred changes
    /// wrote a bare document, and this one writes a wrapper with an `effective`
    /// key, so no version field is needed.
    ///
    /// The choice is made on the key rather than on a failed decode. Falling
    /// back whenever the wrapper fails to decode would leave a damaged wrapper
    /// to be diagnosed by a legacy read of the same bytes, so what surfaces is
    /// whatever the older shape made of them. A file carrying `effective` is
    /// read as one, and its damage is reported as its own.
    private func carriesTheWrapper() throws -> Bool {
        guard FileManager.default.fileExists(atPath: file.url.path) else { return false }
        let data = try Data(contentsOf: file.url)
        guard let fields = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            // Not a JSON object at all. Decoding the current shape reports it as
            // corrupt, which is what it is.
            return true
        }
        return fields.keys.contains("effective")
    }
}
