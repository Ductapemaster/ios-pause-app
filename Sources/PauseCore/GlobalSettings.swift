import Foundation

public enum GlobalSettingsError: Error, Equatable, Sendable {
    case invalidPauseSeconds
    case invalidResetMinuteOfDay
}

public struct GlobalSettings: Codable, Equatable, Sendable {
    /// The reset is chosen from ninety-six positions rather than 1,440: a
    /// quarter-hour is fine enough for a boundary nobody watches land, and it
    /// keeps the picker to a readable length.
    public static let resetMinuteStep = 15

    public var pauseSeconds: Int
    /// Minutes after local midnight at which the day's session counts renew.
    public var resetMinuteOfDay: Int

    public init(pauseSeconds: Int, resetMinuteOfDay: Int = 0) throws {
        guard pauseSeconds >= 1 else {
            throw GlobalSettingsError.invalidPauseSeconds
        }
        guard (0..<(24 * 60)).contains(resetMinuteOfDay),
              resetMinuteOfDay % Self.resetMinuteStep == 0 else {
            throw GlobalSettingsError.invalidResetMinuteOfDay
        }
        self.pauseSeconds = pauseSeconds
        self.resetMinuteOfDay = resetMinuteOfDay
    }

    /// Settings saved before the reset was configurable carry no reset minute.
    /// Reading one as midnight is what lets an existing install upgrade without
    /// a migration or a behaviour change.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            pauseSeconds: container.decode(Int.self, forKey: .pauseSeconds),
            resetMinuteOfDay: container.decodeIfPresent(Int.self, forKey: .resetMinuteOfDay) ?? 0
        )
    }

    public static let phaseOneDefault = try! GlobalSettings(pauseSeconds: 10)
}
