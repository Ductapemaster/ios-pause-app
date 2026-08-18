import ManagedSettings

public enum LaunchRoute: String, Codable, Equatable, Sendable {
    case instagram
}

public extension LaunchRoute {
    static func detected(for application: ManagedSettings.Application) -> LaunchRoute? {
        if application.bundleIdentifier == "com.burbn.instagram" ||
            application.localizedDisplayName == "Instagram" {
            return .instagram
        }
        return nil
    }
}
