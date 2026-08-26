import FamilyControls
import ManagedSettings
import SwiftUI

/// An app drawn as the system draws it, from its `ApplicationToken`.
///
/// Neither half of `Label(applicationToken)` can be styled: the icon has a
/// fixed 35pt frame baked into its body, and the title view has one drawn size,
/// ignores `.font`, and always aligns leading. Drawing the name as ordinary
/// `Text` instead does not work either — `Application(token:).localizedDisplayName`
/// is nil in this process without the `family-controls.app-and-website-usage`
/// entitlement, which this app does not hold. All three measured on device and
/// recorded in `docs/research/screen-time-platform-evidence.md`.
///
/// So this fits the list screens, where the system's own icon and name sit in a
/// row of them. The pause screens carry Pause's wordmark instead.
struct AppTokenLabel: View {
    let applicationToken: ApplicationToken

    var body: some View {
        Label(applicationToken)
    }
}
