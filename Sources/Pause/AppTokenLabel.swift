import FamilyControls
import ManagedSettings
import SwiftUI

struct AppTokenLabel: View {
    let applicationToken: ApplicationToken

    var body: some View {
        Label(applicationToken)
    }
}

/// The app being entered, presented as its own subject: its icon alone,
/// centred at the size the system draws it.
///
/// Two constraints shape this, both established from the SDK rather than
/// guessed, and both recorded in `docs/research/screen-time-platform-evidence.md`:
///
/// The icon cannot be made larger. `FamilyActivityIconView` bakes a
/// `.frame(width: 35, height: 35)` into its `body`, and renders out of process
/// so nothing here ever holds the image. No font, frame, image scale, Dynamic
/// Type setting or custom `LabelStyle` reaches inside it. A `scaleEffect` does
/// enlarge it, by stretching a 35pt raster, which is visibly soft — so it is
/// left at its native size deliberately.
///
/// The name is absent for a different reason. `FamilyActivityTitleView`
/// reports an ideal width of roughly one character, so `.fixedSize()` truncates
/// it to a single glyph, while leaving it free makes it greedy and
/// left-aligned inside a centred column.
///
/// The icon carries the identity on its own: the user arrived by pressing that
/// app's shield, and the session line names the rule.
struct AppIdentityBadge: View {
    let applicationToken: ApplicationToken

    var body: some View {
        AppTokenLabel(applicationToken: applicationToken)
            .labelStyle(.iconOnly)
            .fixedSize()
            .accessibilityLabel("The app you are entering")
    }
}
