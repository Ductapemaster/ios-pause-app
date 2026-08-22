# Roadmap

Prioritized work not currently in flight. Phase 1 is accepted and closed; Phase 2 time-based rules are the next planned phase.

## Deferred

**Three interface changes are unverified on the phone.** The countdown cancel, the scene-interruption split so a banner no longer abandons a pause, and the shield's "Not now" that closes the app. Unit tests reach the model and the shield copy; they cannot reach a SwiftUI scene phase or a shield button. The check is one signed build: confirm a banner does not kill a countdown, the cancel returns without charging a session, and "Not now" closes the app.

**The configurable daily reset is unverified on the phone.** Once built, move the reset to a quarter-hour a few minutes ahead, spend a session, and confirm the count renews at the new time rather than at midnight.

**The sixteen-minute expiry restoration is unverified.** A session over fifteen minutes expires on `intervalDidEnd`, where the observed three-minute case expires on `intervalWillEndWarning` — different callbacks, and only the shorter one has been seen restore the shield. The failure it would catch is silent and open-ended: a session that never ends leaves its target unblocked until something else reconciles. Phase 1 was accepted carrying it, on the reasoning in [the acceptance record](archive/phase-1-core-action-loop/acceptance.md) (why: it costs one sixteen-minute wait to close, and any real use of a session that long settles it).

**Applying a picker selection blocks the main thread.** Adding an app holds the interface while each added app takes a file-lock cycle plus a JSON encode and atomic write, `configurationStore.save` takes another, and `ShieldReconciler.reconcile` holds a lock while re-reading every configured target's runtime and finishes with a `ManagedSettingsStore` write. Two `@Published` writes land in one run-loop turn, each rebuilding a `Label(ApplicationToken)` per rule. `AppModel` is `@MainActor` and no actor, `Task`, or dispatch hop exists on the path. Which part dominates is unmeasured; the ManagedSettings and FamilyControls costs are not visible from source.

Moving the work off the main actor would rework the locking design and the unit tests encode these calls as synchronous throughout (why: deferred on that basis — the daily cost is low because the path is configuration, not the shield-pause-use loop). No hang has been reported in use; measuring it is the cheap first move if one is.

## Not planned

**A picker Pause owns.** Apple's picker shows no running count and nothing can be added to it: `familyActivityPicker` takes `title`, `headerText`, and `footerText` as plain strings, reads them once at presentation, and ignores later changes. Measured on an iPhone 16 Pro running iOS 26.6 — all three surfaces held their entry values while apps were tapped. The same interface offers no way to hide the Categories or Web Domains sections, so a selection the app will discard looks exactly like one it will keep.

Both limits lift the same way: `FamilyActivityData.installedApplications` (iOS 26.4) supplies the installed-app list for a selection UI built here, which would carry a live count, show apps alone, and support grouping the app defines rather than iOS. It requires the `com.apple.developer.family-controls.app-and-website-usage` entitlement, which Apple grants on request. Shelved rather than deferred: the limits are cosmetic, the work is Phase 3 scope at the earliest, and no approval has been requested — which is where it would start if it is ever taken up.
