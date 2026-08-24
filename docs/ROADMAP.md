# Roadmap

Prioritized work not currently in flight. Phase 1 is accepted and closed; Phase 2 time-based rules are the next planned phase.

## Next

**Two device checks gate merging `feat/new-app-configuration-flow` and `feat/session-usage-display` into `design/phased-project-plan`.** Both are listed under Deferred: the sixteen-minute expiry restoration, which the new-app flow unblocked, and the scene-interruption split. Neither is a timestamp question, so both need a person on the phone.

**Then Phase 2: blocking periods** — the recurring stretches when an app cannot be entered at all. The activity-registration budget was thought to be the constraint; reading the requirements against the shield decision path suggests it is not, since a window only refuses entry and entry is decided when the button is pressed. That is reasoning, not a measurement, and building one window would settle it.

## Deferred

**One interface change is unverified on the phone.** The scene-interruption split, so a banner no longer abandons a pause. Unit tests reach the model; they cannot reach a SwiftUI scene phase. The check is to start a countdown, raise a notification banner over it, and confirm the pause survives.

**The sixteen-minute expiry restoration is unverified.** It needs a sixteen-minute session, which an app can now be given as it is added, so it rides the same trip as the new-app flow check. A session over fifteen minutes carries no end warning, so it can only expire on `intervalDidEnd`. That is the untested path. The failure it would catch is silent and open-ended: a session that never ends leaves its target unblocked until something else reconciles. Phase 1 was accepted carrying it, on the reasoning in [the acceptance record](archive/phase-1-core-action-loop/acceptance.md) (why: it costs one sixteen-minute wait to close, and any real use of a session that long settles it).

Short and long sessions do expire on different callbacks. A short session's `intervalDidEnd` arrives at expiry only because Pause's own `stopMonitoring` cancels the pending end alarm — the host holds the padded end where the schedule put it until then, measured 2026-08-23. So the long-session path, where the interval's own end is the only signal, is exercised by nothing.

Unifying on the warning for every length would retire the branch and the untested teardown with it — `DeviceActivitySessionScheduler` is the only place the 15-minute boundary appears, and a 1-minute `warningTime` already ships for 14-minute sessions. It does not remove the device check: it swaps an unexercised `intervalDidEnd` for an unmeasured small warning on a long interval, and either way one sixteen-minute session on the phone settles it.

**Applying a picker selection blocks the main thread.** Adding an app holds the interface while each added app takes a file-lock cycle plus a JSON encode and atomic write, `configurationStore.save` takes another, and `ShieldReconciler.reconcile` holds a lock while re-reading every configured target's runtime and finishes with a `ManagedSettingsStore` write. Two `@Published` writes land in one run-loop turn, each rebuilding a `Label(ApplicationToken)` per rule. `AppModel` is `@MainActor` and no actor, `Task`, or dispatch hop exists on the path. Which part dominates is unmeasured; the ManagedSettings and FamilyControls costs are not visible from source.

Moving the work off the main actor would rework the locking design and the unit tests encode these calls as synchronous throughout (why: deferred on that basis — the daily cost is low because the path is configuration, not the shield-pause-use loop). A hang has since been reported, but it was traced to [the session-end lock-out](research/session-end-hang.md) rather than to this path, which leaves this entry deferred on its original reasoning and still unmeasured.

## Not planned

**A picker Pause owns.** Apple's picker shows no running count and nothing can be added to it: `familyActivityPicker` takes `title`, `headerText`, and `footerText` as plain strings, reads them once at presentation, and ignores later changes. Measured on an iPhone 16 Pro running iOS 26.6 — all three surfaces held their entry values while apps were tapped. The same interface offers no way to hide the Categories or Web Domains sections, so a selection the app will discard looks exactly like one it will keep.

Both limits lift the same way: `FamilyActivityData.installedApplications` (iOS 26.4) supplies the installed-app list for a selection UI built here, which would carry a live count, show apps alone, and support grouping the app defines rather than iOS. It requires the `com.apple.developer.family-controls.app-and-website-usage` entitlement, which Apple grants on request. Shelved rather than deferred: the limits are cosmetic, the work is Phase 3 scope at the earliest, and no approval has been requested — which is where it would start if it is ever taken up.
