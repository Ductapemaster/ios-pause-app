import Foundation

public struct ConfigurationStore {
    private let file: AtomicJSONFile<ConfigurationDocument>

    public init(directoryURL: URL) {
        file = AtomicJSONFile(url: directoryURL.appendingPathComponent("configuration.json"))
    }

    public init(appGroupContainer: AppGroupContainer = AppGroupContainer()) throws {
        self.init(directoryURL: try appGroupContainer.directoryURL())
    }

    public func load() throws -> ConfigurationDocument? {
        guard let document = try file.load() else {
            return nil
        }
        try document.validate()
        return document
    }

    public func save(_ document: ConfigurationDocument) throws {
        try document.validate()
        try file.save(document)
    }
}
