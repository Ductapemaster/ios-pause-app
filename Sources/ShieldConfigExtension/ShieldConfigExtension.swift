import Foundation
import ManagedSettings
import ManagedSettingsUI
import OSLog
import UIKit

private let logger = Logger(subsystem: "com.koubalabs.pause.shieldconfig", category: "shield")

final class ShieldConfigExtension: ShieldConfigurationDataSource {
    override func configuration(shielding application: Application) -> ShieldConfiguration {
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
            logger.info("Shield resolved: \(presentation.subtitle, privacy: .public)")
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
            primaryButtonLabel: ShieldConfiguration.Label(
                text: presentation.primaryButtonTitle,
                color: .white
            ),
            primaryButtonBackgroundColor: .systemIndigo,
            secondaryButtonLabel: nil
        )
    }
}
