import FamilyControls
import Foundation
import ManagedSettings
import OSLog
import PauseCore

private let logger = Logger(subsystem: "com.koubalabs.pause.shieldaction", category: "shield")

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
                guard let file = try ConfigurationStore(directoryURL: directoryURL).loadFile() else {
                    return false
                }
                let configuration = file.inForce(on: LogicalDay.containing(now))
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
            logger.info("Shield action resolved: canOpen=\(canOpen, privacy: .public)")
            completionHandler(canOpen ? .openParentalControlsApp : .none)
        } catch {
            logger.error("Shield action failed: \(String(describing: error), privacy: .public)")
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
