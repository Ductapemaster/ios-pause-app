import Foundation

public enum GlobalSettingsError: Error, Equatable, Sendable {
    case invalidPauseSeconds
    case invalidResetMinuteOfDay
    case invalidCooldownMinutes
}

public struct GlobalSettings: Codable, Equatable, Sendable {
    /// The reset is chosen from ninety-six positions rather than 1,440: a
    /// quarter-hour is fine enough for a boundary nobody watches land, and it
    /// keeps the picker to a readable length.
    public static let resetMinuteStep = 15

    /// Ten minutes bounds the cooldown to what it is for: refusing the press
    /// straight through the shield that has just returned. Spacing sessions
    /// across a day is a blocking period's job.
    public static let cooldownMinutesRange = 0...10

    public var pauseSeconds: Int
    /// Minutes after local midnight at which the day's session counts renew.
    public var resetMinuteOfDay: Int
    /// Minutes after a session's expiry during which that app refuses a new
    /// session. Zero switches the cooldown off.
    public var cooldownMinutes: Int

    public init(
        pauseSeconds: Int,
        resetMinuteOfDay: Int = 0,
        cooldownMinutes: Int = 0
    ) throws {
        guard pauseSeconds >= 1 else {
            throw GlobalSettingsError.invalidPauseSeconds
        }
        guard (0..<(24 * 60)).contains(resetMinuteOfDay),
              resetMinuteOfDay % Self.resetMinuteStep == 0 else {
            throw GlobalSettingsError.invalidResetMinuteOfDay
        }
        guard Self.cooldownMinutesRange.contains(cooldownMinutes) else {
            throw GlobalSettingsError.invalidCooldownMinutes
        }
        self.pauseSeconds = pauseSeconds
        self.resetMinuteOfDay = resetMinuteOfDay
        self.cooldownMinutes = cooldownMinutes
    }

    /// Settings saved before a field existed carry no value for it. Reading the
    /// reset as midnight and the cooldown as off is what lets an existing
    /// install upgrade without a migration or a behaviour change.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            pauseSeconds: container.decode(Int.self, forKey: .pauseSeconds),
            resetMinuteOfDay: container.decodeIfPresent(Int.self, forKey: .resetMinuteOfDay) ?? 0,
            cooldownMinutes: container.decodeIfPresent(Int.self, forKey: .cooldownMinutes) ?? 0
        )
    }

    public static let phaseOneDefault = try! GlobalSettings(pauseSeconds: 10)
}
