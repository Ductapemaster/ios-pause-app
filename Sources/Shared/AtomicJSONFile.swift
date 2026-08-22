import Foundation

public enum PersistenceError: Error, Equatable {
    case corruptFile(URL)
    case missingAppGroupContainer
    case missingRuntime(UUID)
}

public struct AtomicJSONFile<Value: Codable> {
    public let url: URL

    public init(url: URL) {
        self.url = url
    }

    public func load() throws -> Value? {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return nil
        }

        let data = try Data(contentsOf: url)
        do {
            return try JSONDecoder().decode(Value.self, from: data)
        } catch is DecodingError {
            throw PersistenceError.corruptFile(url)
        }
    }

    public func save(_ value: Value) throws {
        let data = try JSONEncoder().encode(value)
        try data.write(to: url, options: .atomic)
    }

    public func delete() throws {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return
        }
        try FileManager.default.removeItem(at: url)
    }
}
