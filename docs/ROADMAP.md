# Roadmap

Prioritized work not currently in flight. Phase 2 time-based rules remain the next planned phase; Phase 1 acceptance comes first.

## Product feedback awaiting work

Raised from device use:

- The shield offers one button. It needs a second that dismisses without starting a session — the label and destination are Dan's call.
- The pause countdown has no cancel. Leaving by Home already abandons the attempt without charging a session, so a cancel button makes an existing exit visible; nothing is reserved, scheduled, or shielded during the countdown, so it needs no rollback.
- A notification banner or a Control Center swipe abandons a pause, because scene handling treats `.inactive` the same as backgrounding (`PauseApp.swift:32-38`). Deliberate under the design, arguably too aggressive in use.

## Deferred

**Applying a picker selection blocks the main thread.** Adding an app holds the interface while each added app takes a file-lock cycle plus a JSON encode and atomic write, `configurationStore.save` takes another, and `ShieldReconciler.reconcile` holds a lock while re-reading every configured target's runtime and finishes with a `ManagedSettingsStore` write. Two `@Published` writes land in one run-loop turn, each rebuilding a `Label(ApplicationToken)` per rule. `AppModel` is `@MainActor` and no actor, `Task`, or dispatch hop exists on the path. Which part dominates is unmeasured; the ManagedSettings and FamilyControls costs are not visible from source.

Moving the work off the main actor would rework the locking design and the unit tests encode these calls as synchronous throughout (why: deferred on that basis — the daily cost is low because the path is configuration, not the shield-pause-use loop).

**File locks wait without a deadline.** `AppGroupFileLock` asks for `flock(LOCK_EX)` and waits indefinitely (`AppGroupFileLock.swift:74`). Any contention on the main thread that crosses ten seconds is a scene-update watchdog kill, which is how the self-deadlock in `9c63da8` presented. That specific cause is fixed, but the shape survives: the shield or monitor extension holding the lock mid-write while the app asks for it reaches the same end. Asking without blocking, retrying briefly, and failing with a real error after a second or two turns every remaining variant from a crash into a message (why: the highest safety return available for a change confined to one file).

**Selection feedback needs a picker we own.** Apple's picker shows no running count and nothing can be added to it: `familyActivityPicker` takes `title`, `headerText`, and `footerText` as plain strings, reads them once at presentation, and ignores later changes. Measured on an iPhone 16 Pro running iOS 26.6 — all three surfaces held their entry values while apps were tapped. The same interface offers no way to hide the Categories or Web Domains sections, so a selection the app will discard looks exactly like one it will keep.

Both limits lift the same way: `FamilyActivityData.installedApplications` (iOS 26.4) supplies the installed-app list for a selection UI built here, which would carry a live count, show apps alone, and support grouping the app defines rather than iOS. It requires the `com.apple.developer.family-controls.app-and-website-usage` entitlement, which Apple grants on request, so the approval comes before the work is worth starting.

## Open decision

**Whether shared state should move to SQLite.** SQLite ships with iOS, locks correctly across processes, carries a built-in bounded wait, and gives transactions across several values — which the current design imitates by wrapping multiple file writes in one lock. Adopting it would delete `AppGroupFileLock` and its tests. Against that: a schema and migrations to carry, and SQLite's write-ahead journal uses cross-process shared memory that interacts badly with iOS file protection while the device is locked, which is exactly the extensions' situation.

**The argument for waiting has lapsed.** It was sequencing rather than merit: replacing the storage layer underneath an unexplained symptom would have removed the ability to attribute any change in behaviour. That symptom is explained — the shield configuration extension's sandbox refuses writes and permits reads, and the shield resolves once nothing on its path takes the lock ([the note](research/shield-repair-variant.md)). The decision now stands on its own merits.

Decide it before bounding the lock waits above, not after: that change lives entirely in `AppGroupFileLock`, which adopting SQLite deletes.
