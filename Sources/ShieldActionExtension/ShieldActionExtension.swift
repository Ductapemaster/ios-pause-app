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
            let stateLock = AppGroupFileLock(directoryURL: directoryURL)
            let canOpen = try stateLock.withLock {
                guard let configuration = try ConfigurationStore(directoryURL: directoryURL).load() else {
                    return false
                }
                let resolvedRule = try RuleLookup.resolve(
                    applicationToken: application,
                    configuration: configuration,
                    runtimeRepository: RuntimeRepository(directoryURL: directoryURL),
                    now: now
                )
                guard case .allowed = resolvedRule.evaluation.decision else {
                    return false
                }

                try ShieldIntentStore().write(
                    ShieldIntent(applicationToken: application, createdAt: now)
                )
                return true
            }
            completionHandler(canOpen ? .openParentalControlsApp : .none)
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
