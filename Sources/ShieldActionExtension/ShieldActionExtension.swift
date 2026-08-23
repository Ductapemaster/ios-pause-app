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

        // A failure to reach the app group container is reported and then
        // dismissed like any other refusal: the button says "Done for today",
        // and leaving it dead is worse than closing the app it is covering.
        let outcome: ShieldPrimaryAction.Outcome
        do {
            outcome = try ShieldPrimaryAction().resolve(
                applicationToken: application,
                now: Date(),
                errorSink: { logger.error("\($0, privacy: .public)") }
            )
        } catch {
            logger.error("Shield action could not start: \(String(describing: error), privacy: .public)")
            outcome = .dismiss
        }
        logger.notice("Shield action resolved: \(String(describing: outcome), privacy: .public)")
        switch outcome {
        case .openPause:
            completionHandler(.openParentalControlsApp)
        case .dismiss:
            completionHandler(.close)
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
