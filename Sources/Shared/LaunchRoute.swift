import ManagedSettings

public enum LaunchRoute: String, Codable, Equatable, Sendable {
    case instagram
}

public extension LaunchRoute {
    static func detected(for application: ManagedSettings.Application) -> LaunchRoute? {
        detected(
            bundleIdentifier: application.bundleIdentifier,
            localizedDisplayName: application.localizedDisplayName
        )
    }

    static func detected(
        bundleIdentifier: String?,
        localizedDisplayName: String?
    ) -> LaunchRoute? {
        if bundleIdentifier == "com.burbn.instagram" {
            return .instagram
        }
        return nil
    }
}
