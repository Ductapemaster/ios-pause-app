# Phase 1 device acceptance

Phase 1 is accepted when the run-through below is recorded as passing, plus the two timed rows that cannot fit inside it. Everything else Pause does is settled by the unit suite, or is deliberately not verified on the device — the last section says which, and why.

## What the device is for

The device is irreplaceable for one thing: observing what iOS itself does. Screen Time authorization, shield presentation and identity, shield intent handoff, Device Activity callback timing, and how a live session behaves are only visible on the phone. Everything that is Pause's own bookkeeping — what a session costs, what a rollback restores, which day a count belongs to — is a pure function over value types and is pinned by unit tests, which are faster, exact, and do not need a phone.

Almost everything in the first category happens in **one continuous pass** through the app: authorize, pick, shield, tap, pause, return, expire, exhaust. Running it as one scripted sitting rather than as separate cases is what keeps acceptance to about twenty minutes.

## Run record

- Date and tester: `<YYYY-MM-DD; name>`
- Device and OS: `iPhone 16 Pro (iPhone17,1); iOS 26.6` (minimum supported version: iOS 26.5)
- App source and build: `commit <sha>; signed Debug build; bundle ID com.koubalabs.pause`
- Selected apps: `Instagram; <second app>`
- Concrete observation per step: `<what appeared, what was tapped, count/state before and after, and any error text>`

Start from a **fresh install** — delete Pause and its data first. iOS 27 requires a separate qualification run after its release and matching Xcode toolchain are available.

## The run-through

One sitting, in order. A step that fails stops the run: later steps assume the earlier ones.

| # | Step | What to watch for |
|---|---|---|
| 1 | Install the signed build and request individual Screen Time authorization. | Authorization succeeds and Pause reaches empty configuration without needing a rule first. |
| 2 | Select Instagram and a second installed app in one picker save, then give them **different** daily allowances and session lengths. | Both apps are covered, each editor holds only its own values. |
| 3 | Open each target. | Both are shielded, each shield carries Apple's correct app identity, and each names **that rule's own** remaining count. Two apps with different allowances is what makes a rule/token mispairing visible. |
| 4 | Tap the shield's button on each app in separate attempts. | Pause opens and starts the flow for the same app whose shield was tapped. |
| 5 | Start a pause and let it run to completion in the foreground. | Use becomes available only after the full configured duration. |
| 6 | Press Home mid-pause, reopen Pause, and begin again. | The attempt is abandoned, no session is charged, and the full pause restarts. |
| 7 | Complete an Instagram pause and choose Use. | The session activates, exactly one session is charged, and `instagram://` returns to Instagram automatically. |
| 8 | Complete a pause for the second app and choose Use. | The session activates before instructions appear; returning through Home or the App Switcher opens the target. |
| 9 | Use every configured session for one rule, then open that target again the same day. | The shield refuses with the daily-limit reason and the target stays blocked. |
| 10 | Remove a configured rule whose target is shielded, and let the removal land at the next reset. | Monitoring stops, the runtime goes, and that target is no longer shielded. |

## The two timed rows

These need a wait that will not fit inside the sitting. Start each and walk away.

| Requirement | Setup | Expected | Observed | Pass/Fail |
|---|---|---|---|---|
| Three-minute expiry restoration | Start a three-minute session; record the wall-clock start and the time the shield returns. | The warning callback restores the shield well inside the thirty-second blocking threshold. | Run 2026-08-20 on the iPhone 16 Pro running iOS 26.6. `intervalWillEndWarning` arrived 22:40:39.290 and the shield rendered the exhausted variant at 22:40:39.376, 182.4s after the session's `intervalDidStart` at 22:37:36.843. | Pass against the thirty-second threshold |
| Sixteen-minute expiry restoration | Start a sixteen-minute session; record the wall-clock start and the time the shield returns. | The interval-end callback restores the shield well inside the thirty-second blocking threshold. | Not run — planned on the iPhone 16 Pro running iOS 26.6. | Pending |

The sixteen-minute row is not a longer copy of the three-minute one. A session under fifteen minutes is padded to a fifteen-minute schedule and expires on `intervalWillEndWarning`; a longer session expires on `intervalDidEnd`. They are different callbacks, and only the shorter one has been observed.

**The five-second tier is not settled and is not being pursued.** [The design](../design/pause-app.md) tiers the criterion at five seconds to pass and thirty to block. The wall clock and the unified log both settle thirty. Five would need the stored `expiresAt` in the log alongside the callback, because both callbacks carry an unmeasured latency against the moments they name — an instrument worth building only if a restoration is ever seen to run late.

## Settled by unit tests

These exercise Pause's own rollback, repair and accounting rather than Screen Time behavior, so a device adds nothing they do not already have.

| Requirement | Covered by |
|---|---|
| Delayed callback recovery | `testDuplicateCallbackWithNoOpenSessionDoesNotChangeCountAndRepairsShield`, `testFallBackAmbiguityFailsBlockedWhenResolvedCallbackIsEarly`, `testMarkedExpiredSessionPersistsClearBeforeMarkerClearAndFullReconcile` |
| Isolated corrupt-runtime repair | `testConfirmedRuntimeResetTouchesOnlySelectedFileAndClearsOnlySelectedMarker`, `testUnrelatedCorruptRuntimeOverridesSelectedPauseWithFailBlockedRepair`, `testSelectedCorruptIntentRepairIsNotReplacedByUnrelatedCorruptRuntimeRepair` |
| Scheduling failure | `testSchedulingFailureLeavesRuntimeAndShieldUntouched`, `testReservationFailureStopsScheduleAndLeavesShieldIntact` |
| Explicit Instagram route failure | `testExplicitRouteFailureRollsBackStopsAndReshieldsWithoutCharging`, `testExplicitLaunchFailureRollsBackStopsReconcilesAndChargesNothing` |
| Failed-grant relaunch safety | `testMarkerPersistsAcrossStoreInstances`, `testFailedGrantForceShieldPersistsBeforeApplyingImmediateBlock`, `testFailedGrantMarkerPersistenceFailureStillAppliesShieldInOrder` |

## Deliberately not verified on the device

Each of these was a row in an earlier, longer matrix. Dropping a row does not make its behavior verified — it makes it **unverified by choice**, on the reasoning given. Any of them is worth reinstating if the behavior it names ever misbehaves in use.

- **Lock interruption** and **scene interruption**. Both reach the same branch as pressing Home: `PauseApp.swift:32-38` treats `.inactive` exactly as backgrounding. One trigger through that branch is the run-through's step 6; the other two would re-observe one code path. That the branch is aggressive is a known product question, recorded in the roadmap, not an acceptance question.
- **Denied authorization.** A whole fresh-install-and-deny cycle to observe one setup screen refusing to advance.
- **Multiple application selection as its own row.** Apple's picker rendering Apple's labels is Apple's behavior; step 2 depends on the selection working anyway, so a failure there stops the run regardless.
- **Independent rule editing as its own row.** Per-rule persistence is unit-covered and folded into step 2, where it costs nothing to look.
- **Wall-clock session while backgrounded**, **app termination during a session**, and **rule edit during an active session.** All three assert that the stored `expiresAt` stays authoritative through an interruption. That is accounting over stored values, which the unit suite covers directly and exactly.
- **Daily count reset at local midnight** and **session crossing midnight.** Both need the tester awake at midnight or the device clock moved, which changes the thing being measured. The logical-day computation is unit-covered, and the device half — whether the `daily-reset` activity actually fires — was observed on 2026-08-20: `intervalDidStart for activity daily-reset` at 22:36:50, recorded in [the platform evidence note](../research/screen-time-platform-evidence.md).
- **Warning callback activity stop.** A choreographed seventeen-minute two-session sequence to confirm that a stale interval end does not cancel a live session. The same note establishes the `stopMonitoring` → `intervalDidEnd` semantics it rests on, and the 2026-08-20 run shows that exact callback pair arriving together and being handled without error.

## Automated checks for the acceptance commit

```bash
xcodegen generate
xcodebuild test -project Pause.xcodeproj -scheme PauseUnitTests -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
xcodebuild build -project Pause.xcodeproj -scheme Pause -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO
git status --short
```
