import Foundation
import ManagedSettings
import ManagedSettingsUI
import UIKit

final class ShieldConfigExtension: ShieldConfigurationDataSource {
    override func configuration(shielding application: Application) -> ShieldConfiguration {
        let presentation: ShieldPresentation
        do {
            guard let applicationToken = application.token else {
                throw RuleLookupError.targetNotFound
            }
            let directoryURL = try AppGroupContainer().directoryURL()
            let stateLock = AppGroupFileLock(directoryURL: directoryURL)
            presentation = try stateLock.withLock {
                guard let configuration = try ConfigurationStore(directoryURL: directoryURL).load() else {
                    throw RuleLookupError.targetNotFound
                }
                let resolvedRule = try RuleLookup.resolve(
                    applicationToken: applicationToken,
                    configuration: configuration,
                    runtimeRepository: RuntimeRepository(directoryURL: directoryURL),
                    now: Date()
                )
                return ShieldPresentation(
                    rule: resolvedRule.rule,
                    decision: resolvedRule.evaluation.decision
                )
            }
        } catch {
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
