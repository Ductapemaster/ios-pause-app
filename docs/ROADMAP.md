# Roadmap

Prioritized work not currently in flight. Phase 2 time-based rules remain the next planned phase; the items below are deferred defects that do not block Phase 1 acceptance.

## Deferred

**Setup freezes the UI while applying a picker selection.** Adding an app blocks the interface for several seconds before the rules screen updates. The work completes and the selection persists, so this costs responsiveness rather than correctness, and it sits on the configuration path rather than the shield-pause-use loop a normal day exercises. No acceptance row covers it.

The whole commit path runs synchronously on the main actor — `AppModel` is `@MainActor` and no actor, `Task`, or dispatch hop exists anywhere on it. Each added app takes a full App Group file-lock cycle plus a JSON encode and atomic write; `configurationStore.save` takes another; `ShieldReconciler.reconcile` then holds a lock while re-reading every configured target's runtime file and finishes with a `ManagedSettingsStore` write. Two separate `@Published` writes land in one run-loop turn, each rebuilding a `Label(ApplicationToken)` per rule. Which of these dominates is unmeasured: the cost of the ManagedSettings and FamilyControls calls is not visible from the source.

Moving this work off the main actor would rework the locking design that `fc96549`, `d4e6ce3`, and `aff5c21` settled, and the unit tests encode these calls as synchronous throughout (why: deferred on that basis, not on difficulty — the fix is well understood and the daily cost is close to zero).

**Selection feedback needs a picker we own.** While Apple's picker is open it shows no running count of what the user has chosen, and nothing can be added to it: `familyActivityPicker` accepts `title`, `headerText`, and `footerText` as plain strings, reads them once at presentation, and ignores every later change. Measured on an iPhone 16 Pro running iOS 26.6 — all three surfaces held their entry values while apps were tapped. The same interface offers no way to hide the Categories or Web Domains sections, so a selection the app will discard looks exactly like one it will keep.

Both limits lift the same way: `FamilyActivityData.installedApplications` (iOS 26.4) supplies the installed-app list for a selection UI built here, which would carry a live count, show apps alone, and support grouping the app defines rather than iOS. It requires the `com.apple.developer.family-controls.app-and-website-usage` entitlement, which Apple grants on request, so the approval comes before the work is worth starting.
