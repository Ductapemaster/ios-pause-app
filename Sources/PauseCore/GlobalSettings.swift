import Foundation

public enum GlobalSettingsError: Error, Equatable, Sendable {
    case invalidPauseSeconds
}

public struct GlobalSettings: Codable, Equatable, Sendable {
    public var pauseSeconds: Int

    public init(pauseSeconds: Int) throws {
        guard pauseSeconds >= 1 else {
            throw GlobalSettingsError.invalidPauseSeconds
        }
        self.pauseSeconds = pauseSeconds
    }

    public static let phaseOneDefault = try! GlobalSettings(pauseSeconds: 10)
}
