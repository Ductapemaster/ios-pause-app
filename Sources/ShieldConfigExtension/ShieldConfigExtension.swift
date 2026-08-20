import Foundation
import ManagedSettings
import ManagedSettingsUI
import OSLog
import UIKit

private let logger = Logger(subsystem: "com.koubalabs.pause.shieldconfig", category: "shield")

/// Records the shield's last outcome in shared preferences.
///
/// The shield runs in its own short-lived process, so a failure there leaves no
/// trace the app can show and no crash to inspect. Writing the outcome where the
/// app can read it makes the difference between a rule that could not be read and
/// one that resolved normally visible after the fact.
private func recordShieldDiagnostic(_ message: String) {
    guard let defaults = UserDefaults(suiteName: SharedIdentifiers.appGroup) else { return }
    let stamped = "\(ISO8601DateFormatter().string(from: Date())) \(message)"
    defaults.set(stamped, forKey: SharedIdentifiers.shieldDiagnosticKey)
    // The shield renders and exits, which can outrun the automatic flush.
    defaults.synchronize()
}

final class ShieldConfigExtension: ShieldConfigurationDataSource {
    override func configuration(shielding application: Application) -> ShieldConfiguration {
        let presentation: ShieldPresentation
        var failedStage: String?
        do {
            guard let applicationToken = application.token else {
                failedStage = "the shielded application carried no token"
                throw RuleLookupError.targetNotFound
            }
            let directoryURL = try AppGroupContainer().directoryURL()
            let stateLock = AppGroupFileLock(directoryURL: directoryURL)
            presentation = try stateLock.withLock {
                guard let configuration = try ConfigurationStore(directoryURL: directoryURL).load() else {
                    failedStage = "no configuration file in the app group container"
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
            logger.info("Shield resolved: \(presentation.subtitle, privacy: .public)")
            recordShieldDiagnostic("resolved: \(presentation.subtitle)")
        } catch {
            let cause = failedStage ?? String(describing: error)
            logger.error("Shield fell back to repair: \(cause, privacy: .public)")
            recordShieldDiagnostic("repair: \(cause)")
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
