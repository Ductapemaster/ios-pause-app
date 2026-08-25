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

        // A failure to reach the app group container at all is reported and then
        // dismissed like any other refusal: the button says "Close", and a
        // container this extension cannot reach is not a condition that
        // clears on the next press, so leaving the shield up would leave the
        // button permanently dead. A failure inside a reachable container is
        // the transient case, and `.keepShield` covers that one.
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
        case .keepShield:
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
