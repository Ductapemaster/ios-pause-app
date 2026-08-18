import FamilyControls
import Foundation
import ManagedSettings

final class ShieldActionExtension: ShieldActionDelegate {
    override func handle(
        action: ShieldAction,
        for application: ApplicationToken,
        completionHandler: @escaping (ShieldActionResponse) -> Void
    ) {
        guard action == .primaryButtonPressed else {
            completionHandler(.none)
            return
        }

        do {
            let now = Date()
            let directoryURL = try AppGroupContainer().directoryURL()
            guard let configuration = try ConfigurationStore(directoryURL: directoryURL).load() else {
                completionHandler(.none)
                return
            }
            let resolvedRule = try RuleLookup.resolve(
                applicationToken: application,
                configuration: configuration,
                runtimeRepository: RuntimeRepository(directoryURL: directoryURL),
                now: now
            )
            guard case .allowed = resolvedRule.evaluation.decision else {
                completionHandler(.none)
                return
            }

            try ShieldIntentStore().write(
                ShieldIntent(applicationToken: application, createdAt: now)
            )
            completionHandler(.openParentalControlsApp)
        } catch {
            completionHandler(.none)
        }
    }

    override func handle(
        action: ShieldAction,
        for category: ActivityCategoryToken,
        completionHandler: @escaping (ShieldActionResponse) -> Void
    ) {
        completionHandler(.none)
    }

    override func handle(
        action: ShieldAction,
        for webDomain: WebDomainToken,
        completionHandler: @escaping (ShieldActionResponse) -> Void
    ) {
        completionHandler(.none)
    }
}
