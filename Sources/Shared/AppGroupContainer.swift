import Foundation

public struct AppGroupContainer {
    public let identifier: String

    public init(identifier: String = SharedIdentifiers.appGroup) {
        self.identifier = identifier
    }

    public func directoryURL(fileManager: FileManager = .default) throws -> URL {
        guard let url = fileManager.containerURL(forSecurityApplicationGroupIdentifier: identifier) else {
            throw PersistenceError.missingAppGroupContainer
        }
        return url
    }
}
