import FamilyControls
import ManagedSettings
import SwiftUI

struct AppTokenLabel: View {
    let applicationToken: ApplicationToken

    var body: some View {
        Label(applicationToken)
    }
}

/// The app being entered, shown as its icon at the size the system draws it.
///
/// Neither half of `Label(applicationToken)` can be styled: the icon has a
/// fixed 35pt frame baked into its body, and the title view has one drawn size,
/// ignores `.font`, and always aligns leading. Drawing the name as ordinary
/// `Text` instead does not work either — `Application(token:).localizedDisplayName`
/// is nil in this process without the `family-controls.app-and-website-usage`
/// entitlement, which this app does not hold. All three measured on device and
/// recorded in `docs/research/screen-time-platform-evidence.md`.
///
/// So the icon stands alone here, and the identity is carried by pairing it
/// with the session line rather than by naming the app.
struct AppIdentityBadge: View {
    let applicationToken: ApplicationToken

    var body: some View {
        AppTokenLabel(applicationToken: applicationToken)
            .labelStyle(.iconOnly)
            .fixedSize()
            .accessibilityLabel("The app you are entering")
    }
}
