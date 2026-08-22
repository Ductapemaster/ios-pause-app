import Foundation
import ManagedSettings

public struct ShieldIntent: Codable, Equatable {
    public let applicationToken: ApplicationToken
    public let createdAt: Date

    public init(applicationToken: ApplicationToken, createdAt: Date) {
        self.applicationToken = applicationToken
        self.createdAt = createdAt
    }
}

public struct ShieldIntentStore {
    private static let corruptionURL = URL(string: "app-group-userdefaults://shield-intent-v1")!
    private let defaults: UserDefaults?

    public init(appGroupIdentifier: String = SharedIdentifiers.appGroup) {
        defaults = UserDefaults(suiteName: appGroupIdentifier)
    }

    public init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    public func write(_ intent: ShieldIntent) throws {
        guard let defaults else {
            throw PersistenceError.missingAppGroupContainer
        }
        defaults.set(try JSONEncoder().encode(intent), forKey: SharedIdentifiers.shieldIntentKey)
    }

    public func consume() throws -> ShieldIntent? {
        guard let defaults else {
            throw PersistenceError.missingAppGroupContainer
        }
        guard let data = defaults.data(forKey: SharedIdentifiers.shieldIntentKey) else {
            return nil
        }

        defer { defaults.removeObject(forKey: SharedIdentifiers.shieldIntentKey) }
        do {
            return try JSONDecoder().decode(ShieldIntent.self, from: data)
        } catch is DecodingError {
            throw PersistenceError.corruptFile(Self.corruptionURL)
        }
    }
}
