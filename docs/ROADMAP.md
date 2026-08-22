# Roadmap

Prioritized work not currently in flight. Phase 1 is accepted and closed; Phase 2 time-based rules are the next planned phase.

## Ready to build

Each of these is decided and scoped. None is large, and none blocks another.

**The pause countdown has no cancel.** `PauseView` hides the back button (`PauseView.swift:56`), so the only exit is Home. Leaving by Home already abandons the attempt without charging a session, so a cancel button makes an existing exit visible rather than adding one. Nothing is reserved, scheduled, or shielded before `onUseSession`, so it needs no rollback.

**A transient overlay abandons a pause.** Scene handling sends every phase that is not `.active` to `sceneDidBecomeInactive` (`PauseApp.swift:32-38`), so a notification banner, a Control Center swipe, or a lock kills the countdown the same way backgrounding does. Only backgrounding should: a transient overlay is not the user leaving, and losing a countdown to a notification punishes something they did not do.

**The shield offers one button.** It needs a second, "Not now", that dismisses without starting a session and sends the user to the Home Screen. Closing the shield in place would leave them on the app they opened by reflex; moving them away is the point of the escape.

**File locks wait without a deadline.** `AppGroupFileLock` asks for `flock(LOCK_EX)` and waits indefinitely (`AppGroupFileLock.swift:74`). Any contention on the main thread that crosses ten seconds is a scene-update watchdog kill, which is how the self-deadlock in `9c63da8` presented. That specific cause is fixed, but the shape survives: the shield or monitor extension holding the lock mid-write while the app asks for it reaches the same end. Asking without blocking, retrying briefly, and failing with a real error after a second or two turns every remaining variant from a crash into a message. The change is confined to one file, and the storage decision that would have deleted that file is settled — [the architecture](design/pause-app.md) keeps JSON under one lock.

## Deferred

**The sixteen-minute expiry restoration is unverified.** A session over fifteen minutes expires on `intervalDidEnd`, where the observed three-minute case expires on `intervalWillEndWarning` — different callbacks, and only the shorter one has been seen restore the shield. The failure it would catch is silent and open-ended: a session that never ends leaves its target unblocked until something else reconciles. Phase 1 was accepted carrying it, on the reasoning in [the acceptance doc](testing/phase-1-device-acceptance.md) (why: it costs one sixteen-minute wait to close, and any real use of a session that long settles it).

**Applying a picker selection blocks the main thread.** Adding an app holds the interface while each added app takes a file-lock cycle plus a JSON encode and atomic write, `configurationStore.save` takes another, and `ShieldReconciler.reconcile` holds a lock while re-reading every configured target's runtime and finishes with a `ManagedSettingsStore` write. Two `@Published` writes land in one run-loop turn, each rebuilding a `Label(ApplicationToken)` per rule. `AppModel` is `@MainActor` and no actor, `Task`, or dispatch hop exists on the path. Which part dominates is unmeasured; the ManagedSettings and FamilyControls costs are not visible from source.

Moving the work off the main actor would rework the locking design and the unit tests encode these calls as synchronous throughout (why: deferred on that basis — the daily cost is low because the path is configuration, not the shield-pause-use loop). No hang has been reported in use; measuring it is the cheap first move if one is.

## Not planned

**A picker Pause owns.** Apple's picker shows no running count and nothing can be added to it: `familyActivityPicker` takes `title`, `headerText`, and `footerText` as plain strings, reads them once at presentation, and ignores later changes. Measured on an iPhone 16 Pro running iOS 26.6 — all three surfaces held their entry values while apps were tapped. The same interface offers no way to hide the Categories or Web Domains sections, so a selection the app will discard looks exactly like one it will keep.

Both limits lift the same way: `FamilyActivityData.installedApplications` (iOS 26.4) supplies the installed-app list for a selection UI built here, which would carry a live count, show apps alone, and support grouping the app defines rather than iOS. It requires the `com.apple.developer.family-controls.app-and-website-usage` entitlement, which Apple grants on request. Shelved rather than deferred: the limits are cosmetic, the work is Phase 3 scope at the earliest, and no approval has been requested — which is where it would start if it is ever taken up.
