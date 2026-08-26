# Roadmap

Prioritized work not currently in flight. Phase 1 is accepted and closed, and no phase is planned behind it.

## Next

Nothing planned. Phase 1 ships the loop the product describes, and what follows it is an open product question.

## Deferred

**Owed on the current build: confirm a refusal shield renders one button.** Passing `nil` for `secondaryButtonLabel` is how `ShieldConfiguration` omits it — the property is optional and defaults to `nil` — but that is read off the SDK declaration rather than measured. A cooldown shield has since been used on the device and was described as having one button, which is close to settling it; counting the buttons deliberately on a refusal closes it.

**Owed on the current build: does a granted session unblock the app's web domain?** A shielded app's associated domains are shielded with it, by a system shield Pause cannot configure ([the evidence](research/screen-time-platform-evidence.md)). The domain is blocked only by association with a token that a grant removes from `shield.applications`, so a running session is expected to clear the browser too. That is reasoning from where the token lives, not a measurement. The check is one step: start a session on a covered app, then load its domain in a browser while the session runs. It rides the same trip as the button count above.

**Owed on the current build: which route a failed shield press takes.** A press that reached Pause without starting a countdown has been traced to the `.unchanged` path — the app never went `.background`, so the activation was treated as already handled and the intent was discarded ([the investigation](research/shield-press-routing.md)). A second press the same evening also produced no session, from a cold launch that cannot have taken that path, and the archive cannot say whether it landed on the rules list or a repair screen. The route resolution now logs its route and reason at `.notice`, so the next occurrence settles it: collect the archive and read the `Entry route resolved:` line.

**Applying a picker selection blocks the main thread.** Adding an app holds the interface while each added app takes a file-lock cycle plus a JSON encode and atomic write, `configurationStore.save` takes another, and `ShieldReconciler.reconcile` holds a lock while re-reading every configured target's runtime and finishes with a `ManagedSettingsStore` write. Two `@Published` writes land in one run-loop turn, each rebuilding a `Label(ApplicationToken)` per rule. `AppModel` is `@MainActor` and no actor, `Task`, or dispatch hop exists on the path. Which part dominates is unmeasured; the ManagedSettings and FamilyControls costs are not visible from source.

Moving the work off the main actor would rework the locking design and the unit tests encode these calls as synchronous throughout (why: deferred on that basis — the daily cost is low because the path is configuration, not the shield-pause-use loop). A hang has since been reported, but it was traced to [the session-end lock-out](research/session-end-hang.md) rather than to this path, which leaves this entry deferred on its original reasoning and still unmeasured.

## Not planned

**Phase 2: blocking periods** — the recurring stretches when an app cannot be entered at all, as described in the product requirements. Shelved on 2026-08-24: the cap and the cooldown may already do the work, and whether a window adds anything is worth living with Phase 1 to find out.

The cost is lower than it was assumed to be, which is the part worth keeping if it is taken up. A window needs no `DeviceActivity` registration and no monitored activity per weekday. `ShieldReconciler` shields every configured target by default and unshields one only while a session runs, so an app is already shielded whenever a session is not open, and nothing has to wake to re-shield at a boundary. Windows gate entry rather than use, and entry is decided when the shield button is pressed — which makes a window a predicate over the current time, evaluated in `RulesEngine.decision` exactly as the cooldown is. That is read from the reconciler and the requirements, not measured.

One contradiction in the requirements has to be settled before any of it: the Goal describes blocking an app outside a scheduled window, while the app-configuration section describes a window as a stretch when the app cannot be entered. Those are opposite senses of the same word.

**A picker Pause owns.** Apple's picker shows no running count and nothing can be added to it: `familyActivityPicker` takes `title`, `headerText`, and `footerText` as plain strings, reads them once at presentation, and ignores later changes. Measured on an iPhone 16 Pro running iOS 26.6 — all three surfaces held their entry values while apps were tapped. The same interface offers no way to hide the Categories or Web Domains sections, so a selection the app will discard looks exactly like one it will keep.

Both limits lift the same way: `FamilyActivityData.installedApplications` (iOS 26.4) supplies the installed-app list for a selection UI built here, which would carry a live count, show apps alone, and support grouping the app defines rather than iOS. It requires the `com.apple.developer.family-controls.app-and-website-usage` entitlement, which Apple grants on request. The same entitlement makes `localizedDisplayName` readable, which is the only route to naming a covered app on Pause's own screens — worth knowing if the picker is ever taken up, not worth requesting for a label. Shelved rather than deferred: the limits are cosmetic, the work is Phase 3 scope at the earliest, and no approval has been requested — which is where it would start if it is ever taken up.
