# Roadmap

Prioritized work not currently in flight. Phase 1 is accepted and closed; Phase 2 time-based rules are the next planned phase.

## Next

**Phase 2: blocking periods** — the recurring stretches when an app cannot be entered at all. The activity-registration budget was thought to be the constraint; reading the requirements against the shield decision path suggests it is not, since a window only refuses entry and entry is decided when the button is pressed. That is reasoning, not a measurement, and building one window would settle it.

A window is the same shape as the cooldown that now ships — entry refused for a stretch — and joins as a further guard in `RulesEngine.decision`. It needs what the cooldown did not: a recurring schedule and a monitored activity per weekday, so the monitor can re-shield at a boundary.

## Deferred

**Owed on the current build: confirm the cooldown refusal renders.** Set the cooldown to a minute or two, spend a session, and open the app again before it elapses. The shield should read "Cooling down until …" with one button. This is the first refusal whose subtitle carries a formatted time, and it is the only part of the cooldown that a unit test cannot reach.

**Owed on the current build: confirm a refusal shield renders one button.** Passing `nil` for `secondaryButtonLabel` is how `ShieldConfiguration` omits it — the property is optional and defaults to `nil` — but that is read off the SDK declaration rather than measured, and no rendered shield has been seen with it nil. Opening a shielded app whose allowance is spent settles it.

**Applying a picker selection blocks the main thread.** Adding an app holds the interface while each added app takes a file-lock cycle plus a JSON encode and atomic write, `configurationStore.save` takes another, and `ShieldReconciler.reconcile` holds a lock while re-reading every configured target's runtime and finishes with a `ManagedSettingsStore` write. Two `@Published` writes land in one run-loop turn, each rebuilding a `Label(ApplicationToken)` per rule. `AppModel` is `@MainActor` and no actor, `Task`, or dispatch hop exists on the path. Which part dominates is unmeasured; the ManagedSettings and FamilyControls costs are not visible from source.

Moving the work off the main actor would rework the locking design and the unit tests encode these calls as synchronous throughout (why: deferred on that basis — the daily cost is low because the path is configuration, not the shield-pause-use loop). A hang has since been reported, but it was traced to [the session-end lock-out](research/session-end-hang.md) rather than to this path, which leaves this entry deferred on its original reasoning and still unmeasured.

## Not planned

**A picker Pause owns.** Apple's picker shows no running count and nothing can be added to it: `familyActivityPicker` takes `title`, `headerText`, and `footerText` as plain strings, reads them once at presentation, and ignores later changes. Measured on an iPhone 16 Pro running iOS 26.6 — all three surfaces held their entry values while apps were tapped. The same interface offers no way to hide the Categories or Web Domains sections, so a selection the app will discard looks exactly like one it will keep.

Both limits lift the same way: `FamilyActivityData.installedApplications` (iOS 26.4) supplies the installed-app list for a selection UI built here, which would carry a live count, show apps alone, and support grouping the app defines rather than iOS. It requires the `com.apple.developer.family-controls.app-and-website-usage` entitlement, which Apple grants on request. Shelved rather than deferred: the limits are cosmetic, the work is Phase 3 scope at the earliest, and no approval has been requested — which is where it would start if it is ever taken up.
