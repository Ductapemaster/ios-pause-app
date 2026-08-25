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
/// centred.
///
/// Two constraints shape this, both established from the SDK rather than
/// guessed, and both recorded in `docs/research/screen-time-platform-evidence.md`:
///
/// The icon has one drawn size. `FamilyActivityIconView` bakes a
/// `.frame(width: 35, height: 35)` into its `body` and renders out of process,
/// so no font, frame, image scale, Dynamic Type setting or custom `LabelStyle`
/// reaches inside it. A `scaleEffect` is the only lever, and it enlarges by
/// stretching what the slot already drew at 35pt — so `scale` buys size at the
/// cost of sharpness, and nothing else can.
///
/// At 3x, 35pt is a 105px source. `scale` 1.5 asks 156px of it and reads
/// slightly soft; 2.3 asks 240px and is visibly mushy. Tune this one number
/// against that curve — there is no setting that makes it sharp and large.
///
/// The name is absent for a different reason. `FamilyActivityTitleView`
/// reports an ideal width of roughly one character, so `.fixedSize()` truncates
/// it to a single glyph, while leaving it free makes it greedy and
/// left-aligned inside a centred column.
struct AppIdentityBadge: View {
    let applicationToken: ApplicationToken

    /// Multiplier on the system's fixed 35pt icon. See the note above before
    /// raising it.
    var scale: CGFloat = 1.5

    private var drawnSize: CGFloat { 35 * scale }

    var body: some View {
        AppTokenLabel(applicationToken: applicationToken)
            .labelStyle(.iconOnly)
            .fixedSize()
            .scaleEffect(scale)
            .frame(width: drawnSize, height: drawnSize)
            .accessibilityLabel("The app you are entering")
    }
}
