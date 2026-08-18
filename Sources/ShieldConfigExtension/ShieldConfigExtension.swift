import ManagedSettings
import ManagedSettingsUI

final class ShieldConfigExtension: ShieldConfigurationDataSource {
    override func configuration(shielding application: Application) -> ShieldConfiguration {
        ShieldConfiguration()
    }
}
