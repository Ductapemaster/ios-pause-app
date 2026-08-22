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
        // Leaving without starting a session: close the shielded app rather than
        // dismissing in place, which would leave the user on the app they opened
        // by reflex.
        if action == .secondaryButtonPressed {
            completionHandler(.close)
            return
        }
        guard action == .primaryButtonPressed else {
            completionHandler(.none)
            return
        }

        // The control reading for the monitor extension's probe: this extension
        // is known to do app group file I/O successfully, so a refusal logged
        // here would be evidence about the probe rather than about a sandbox.
        logger.notice("Shield action sandbox probe: \(AppGroupSandboxProbe.run().summary, privacy: .public)")

        do {
            let now = Date()
            let directoryURL = try AppGroupContainer().directoryURL()
            let stateLock = AppGroupFileLock(directoryURL: directoryURL)
            let canOpen = try stateLock.withLock {
                guard let file = try ConfigurationStore(directoryURL: directoryURL).loadFile() else {
                    return false
                }
                let resolvedRule = try RuleLookup.resolve(
                    applicationToken: application,
                    configurationFile: file,
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
            logger.notice("Shield action resolved: canOpen=\(canOpen, privacy: .public)")
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
