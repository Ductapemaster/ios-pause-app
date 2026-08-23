import Foundation
import ManagedSettings
import ManagedSettingsUI
import OSLog
import UIKit

private let logger = Logger(subsystem: "com.koubalabs.pause.shieldconfig", category: "shield")

final class ShieldConfigExtension: ShieldConfigurationDataSource {
    override func configuration(shielding application: Application) -> ShieldConfiguration {
        // Entry and exit both at notice, for the same reason the monitor
        // extension logs at notice: only notice and above reach the log data
        // store, so an entry with no matching exit is the only way to see from
        // an archive that a render began and never finished.
        logger.notice("Shield render began")
        defer { logger.notice("Shield render returned") }

        let presentation: ShieldPresentation
        do {
            guard let applicationToken = application.token else {
                logger.error("Shield fell back to repair: the shielded application carried no token")
                return shieldConfiguration(
                    applicationName: application.localizedDisplayName ?? "This app",
                    presentation: .repair
                )
            }
            presentation = try ShieldStateReader().presentation(for: applicationToken, now: Date())
            logger.notice("Shield resolved: \(presentation.subtitle, privacy: .public)")
        } catch {
            logger.error("Shield fell back to repair: \(String(describing: error), privacy: .public)")
            presentation = .repair
        }

        return shieldConfiguration(
            applicationName: application.localizedDisplayName ?? "This app",
            presentation: presentation
        )
    }

    override func configuration(
        shielding application: Application,
        in category: ActivityCategory
    ) -> ShieldConfiguration {
        configuration(shielding: application)
    }

    private func shieldConfiguration(
        applicationName: String,
        presentation: ShieldPresentation
    ) -> ShieldConfiguration {
        ShieldConfiguration(
            backgroundBlurStyle: .systemMaterial,
            backgroundColor: nil,
            icon: nil,
            title: ShieldConfiguration.Label(text: applicationName, color: .label),
            subtitle: ShieldConfiguration.Label(text: presentation.subtitle, color: .secondaryLabel),
            // iOS does not reliably honour the primary button's label colour, so
            // the button cannot depend on one: white text was rendered in a
            // system colour close to the indigo behind it and disappeared. A
            // light button reads against the system's own dark label whether our
            // colour is applied or ignored. Both values are fixed rather than
            // dynamic, so the pair cannot invert in dark mode.
            primaryButtonLabel: ShieldConfiguration.Label(
                text: presentation.primaryButtonTitle,
                color: UIColor(white: 0.1, alpha: 1)
            ),
            primaryButtonBackgroundColor: UIColor(white: 0.97, alpha: 1),
            secondaryButtonLabel: ShieldConfiguration.Label(
                text: presentation.secondaryButtonTitle,
                color: .label
            )
        )
    }
}
