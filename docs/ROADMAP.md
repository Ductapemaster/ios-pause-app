# Roadmap

Prioritized work not currently in flight. Phase 1 is accepted and closed; Phase 2 time-based rules are the next planned phase.

## Next

**A new app cannot be given its session length on the day it is added, and that blocks the sixteen-minute check.** Adding an app writes a rule with three sessions a day and five minutes (`AppModel.applyPickerSelection`), and the addition lands at once because covering an app is a tightening. Raising either value afterwards is a loosening (`ConfigurationComparison.isLoosening`), so it waits for the next daily reset. The default is therefore the only configuration a new app can have for the rest of the day, and no sixteen-minute session can exist until the day after the app is added.

The fix Dan wants is a configuration flow at the moment an app is added: choose sessions per day and session length before the rule is written, so the first values are part of the addition rather than an edit that has to wait. That carries a second change with it — the picker has to add one app at a time, since a flow cannot configure an unbounded set.

Apple's picker will not enforce that. `familyActivityPicker(title:footerText:isPresented:selection:)` binds a `FamilyActivitySelection`, a multi-select set with no single-selection option, so one-at-a-time has to be enforced by Pause once the sheet closes rather than by the picker itself.

Open, and to be settled before any code:
- What happens when a picker session returns more than one new app — refuse, queue them through the flow one by one, or take the first.
- Whether removal stays multi-select, given the same sheet does both today.
- Whether the flow also runs for an app being re-added after a removal.
- Whether the flow pre-fills the current defaults or requires a deliberate choice.

## Deferred

**Three interface changes are unverified on the phone.** The countdown cancel, the scene-interruption split so a banner no longer abandons a pause, and the shield's "Not now" that closes the app. Unit tests reach the model and the shield copy; they cannot reach a SwiftUI scene phase or a shield button. The check is one signed build: confirm a banner does not kill a countdown, the cancel returns without charging a session, and "Not now" closes the app.

**The configurable daily reset is unverified on the phone.** Move the reset to a quarter-hour a few minutes ahead, spend a session so the count is non-zero, wait for the reset to pass, and confirm the count renews at the new time rather than at midnight and that the shield reflects the renewed allowance.

**The in-app session count is unverified on the phone.** Spend a session on a restricted app and confirm the rules list's number moves in step with the shield's, and that both renew at the configured reset rather than at midnight. This rides the same signed build as the configurable daily reset check — one trip to the phone, not two.

**The sixteen-minute expiry restoration is unverified, and cannot be run yet.** It needs a sixteen-minute session, which no app can be given on the day it is added — see Next. A session over fifteen minutes carries no end warning, so it can only expire on `intervalDidEnd`. That is the untested path. The failure it would catch is silent and open-ended: a session that never ends leaves its target unblocked until something else reconciles. Phase 1 was accepted carrying it, on the reasoning in [the acceptance record](archive/phase-1-core-action-loop/acceptance.md) (why: it costs one sixteen-minute wait to close, and any real use of a session that long settles it).

Short and long sessions do expire on different callbacks. A short session's `intervalDidEnd` arrives at expiry only because Pause's own `stopMonitoring` cancels the pending end alarm — the host holds the padded end where the schedule put it until then, measured 2026-08-23. So the long-session path, where the interval's own end is the only signal, is exercised by nothing.

Unifying on the warning for every length would retire the branch and the untested teardown with it — `DeviceActivitySessionScheduler` is the only place the 15-minute boundary appears, and a 1-minute `warningTime` already ships for 14-minute sessions. It does not remove the device check: it swaps an unexercised `intervalDidEnd` for an unmeasured small warning on a long interval, and either way one sixteen-minute session on the phone settles it.

**Applying a picker selection blocks the main thread.** Adding an app holds the interface while each added app takes a file-lock cycle plus a JSON encode and atomic write, `configurationStore.save` takes another, and `ShieldReconciler.reconcile` holds a lock while re-reading every configured target's runtime and finishes with a `ManagedSettingsStore` write. Two `@Published` writes land in one run-loop turn, each rebuilding a `Label(ApplicationToken)` per rule. `AppModel` is `@MainActor` and no actor, `Task`, or dispatch hop exists on the path. Which part dominates is unmeasured; the ManagedSettings and FamilyControls costs are not visible from source.

Moving the work off the main actor would rework the locking design and the unit tests encode these calls as synchronous throughout (why: deferred on that basis — the daily cost is low because the path is configuration, not the shield-pause-use loop). A hang has since been reported, but it was traced to [the session-end lock-out](research/session-end-hang.md) rather than to this path, which leaves this entry deferred on its original reasoning and still unmeasured.

## Not planned

**A picker Pause owns.** Apple's picker shows no running count and nothing can be added to it: `familyActivityPicker` takes `title`, `headerText`, and `footerText` as plain strings, reads them once at presentation, and ignores later changes. Measured on an iPhone 16 Pro running iOS 26.6 — all three surfaces held their entry values while apps were tapped. The same interface offers no way to hide the Categories or Web Domains sections, so a selection the app will discard looks exactly like one it will keep.

Both limits lift the same way: `FamilyActivityData.installedApplications` (iOS 26.4) supplies the installed-app list for a selection UI built here, which would carry a live count, show apps alone, and support grouping the app defines rather than iOS. It requires the `com.apple.developer.family-controls.app-and-website-usage` entitlement, which Apple grants on request. Shelved rather than deferred: the limits are cosmetic, the work is Phase 3 scope at the earliest, and no approval has been requested — which is where it would start if it is ever taken up.
