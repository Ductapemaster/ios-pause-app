import Foundation
import UIKit

final class AppLaunchRouter: TargetLaunching, @unchecked Sendable {
    private let routes: [UUID: LaunchRoute]
    private let openURL: @MainActor (URL) async -> Bool

    convenience init(configuration: ConfigurationDocument) {
        self.init(
            routes: Dictionary(
                uniqueKeysWithValues: configuration.targets.compactMap { target in
                    target.launchRoute.map { (target.ruleID, $0) }
                }
            ),
            openURL: { url in await UIApplication.shared.open(url) }
        )
    }

    init(
        routes: [UUID: LaunchRoute],
        openURL: @escaping @MainActor (URL) async -> Bool
    ) {
        self.routes = routes
        self.openURL = openURL
    }

    func hasAutomaticRoute(ruleID: UUID) -> Bool {
        routes[ruleID] == .instagram
    }

    func open(ruleID: UUID) async -> Bool {
        guard routes[ruleID] == .instagram,
              let url = URL(string: "instagram://") else { return false }
        return await openURL(url)
    }
}
