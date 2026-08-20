# Phase 1 device acceptance

Phase 1 is not accepted until every row below is settled. Rows marked Pending need a concrete signed-device observation that passes — simulator tests and unsigned builds do not substitute for Screen Time behavior on the phone. Rows marked Unit-covered are settled by the named unit tests.

## Run record

- Date and tester: `<YYYY-MM-DD; name>`
- Device and OS: `iPhone 16 Pro (iPhone17,1); iOS 26.6` (minimum supported version: iOS 26.5)
- App source and build: `commit 4b48503; signed Debug build; bundle ID com.koubalabs.pause`
- Selected apps: `Instagram; <manual-return app>`
- Expiry evidence: `session start <clock time>; configured duration <minutes>; shield restored <clock time>; measured delay <seconds>`
- Concrete observation: `<what appeared, what was tapped, count/state before and after, and any error text>`

Use a fresh install where specified. iOS 27 requires a separate qualification run after its release and matching Xcode toolchain are available.

## What the device run covers

The device is irreplaceable for one thing: observing what iOS itself does. Screen Time authorization, shield presentation and identity, shield intent handoff, Device Activity callback timing, and how a live session behaves across backgrounding, termination, and local midnight are all only visible on the phone.

The failure rows are a different case. They exercise Pause's own rollback and repair code rather than Screen Time behavior, and unit tests already cover that code, so a device adds little. Each such row names the tests that cover it and carries Unit-covered in place of a device result.

Timing rows read wall-clock time against the session's configured duration. `docs/design/pause-app.md` tiers the criterion: a callback within five seconds of the named expiry passes, and one later than thirty seconds blocks the phase. A wall clock settles the thirty-second blocking threshold; confirming the five-second tier needs an instrument and is deferred.

## Acceptance matrix

| Requirement | Test setup | Expected | Observed | Pass/Fail |
|---|---|---|---|---|
| Fresh install and Screen Time authorization | Delete Pause and its data, install the signed build, then request individual authorization. | Authorization succeeds and the app reaches empty configuration without creating a rule first. | Not run — planned on the iPhone 16 Pro running iOS 26.6. | Pending |
| Denied authorization | From a fresh install, deny the individual Screen Time request. | Pause stays in setup state and creates no rules or claim of enforcement. | Not run — planned on the iPhone 16 Pro running iOS 26.6. | Pending |
| Multiple application selection | Grant authorization and select Instagram plus another installed app in one Apple picker save. | Both eligible apps are selected and shown with Apple's labels and icons. | Not run — planned on the iPhone 16 Pro running iOS 26.6. | Pending |
| Independent rule editing | Give Instagram and the second app different daily allowances and session lengths, then reopen both editors. | Each app retains only its own saved values. | Not run — planned on the iPhone 16 Pro running iOS 26.6. | Pending |
| Shields after setup and activation | Save both rules, open each target, return to Pause, then activate each target again. | Both targets are shielded after setup and remain correctly shielded after later app activation. | Not run — planned on the iPhone 16 Pro running iOS 26.6. | Pending |
| Per-app shield identity and next-session count | Configure different allowances, then open each shield. | Apple's app identity is correct and each shield shows that rule's independent prospective session number. | Not run — planned on the iPhone 16 Pro running iOS 26.6. | Pending |
| Shield intent handoff | Tap Continue on each app's shield in separate attempts. | Pause opens and starts the flow for the same app whose shield was tapped. | Not run — planned on the iPhone 16 Pro running iOS 26.6. | Pending |
| Foreground pause duration | Start a pause and leave Pause active until the configured duration elapses. | Use becomes available only after the full configured foreground duration. | Not run — planned on the iPhone 16 Pro running iOS 26.6. | Pending |
| Home interruption | Press Home before the pause completes, reopen Pause, and begin again. | The attempt is abandoned, no session is charged, and the full pause restarts. | Not run — planned on the iPhone 16 Pro running iOS 26.6. | Pending |
| Lock interruption | Lock before the pause completes, unlock, reopen Pause, and begin again. | The attempt is abandoned, no session is charged, and the full pause restarts. | Not run — planned on the iPhone 16 Pro running iOS 26.6. | Pending |
| Scene interruption | Leave Control Center open long enough for Pause to become inactive, then return and begin again. | The attempt is abandoned, no session is charged, and the full pause restarts. | Not run — planned on the iPhone 16 Pro running iOS 26.6. | Pending |
| Instagram automatic return | Complete an Instagram pause and choose Use. | The session activates, exactly one session is charged, and `instagram://` returns to Instagram automatically. | Not run — planned on the iPhone 16 Pro running iOS 26.6. | Pending |
| Manual return | Complete a pause for the app without a supported route and choose Use. | The session activates before instructions appear; returning through Home or App Switcher opens the target. | Not run — planned on the iPhone 16 Pro running iOS 26.6. | Pending |
| Wall-clock session while backgrounded | Note the clock time at session start, background the target for part of the configured duration, then return both before and after the expiry that start time implies. | Background time consumes the grant; access remains open only until the original stored `expiresAt`. | Not run — planned on the iPhone 16 Pro running iOS 26.6. | Pending |
| Three-minute expiry restoration | Start a three-minute session and record the wall-clock start time and the time the shield returns; the wall clock settles the thirty-second blocking threshold and five-second confirmation is deferred. | The warning callback restores the shield no more than five seconds after stored expiry. | Not run — planned on the iPhone 16 Pro running iOS 26.6. | Pending |
| Sixteen-minute expiry restoration | Start a sixteen-minute session and record the wall-clock start time and the time the shield returns; the wall clock settles the thirty-second blocking threshold and five-second confirmation is deferred. | The interval-end callback restores the shield no more than five seconds after stored expiry. | Not run — planned on the iPhone 16 Pro running iOS 26.6. | Pending |
| Warning callback activity stop | By the wall clock, start a three-minute session at `t+00:00` and a second three-minute session at `t+13:30`, then watch the shield across the first activity's original interval end at `t+15:00` and the second session's expiry at `t+16:30`. The shield's own behavior settles this; a callback trace would explain why, not whether. | The second session stays open past `t+15:00`, so the first activity's original interval end neither cancels nor changes it, and the shield returns at `t+16:30`. | Not run — planned on the iPhone 16 Pro running iOS 26.6. | Pending |
| Delayed callback recovery | Unit tests drive a late or duplicate expiry callback and a following app activation. | App activation clears the expired session and restores the shield from stored expiry. | Covered by `testDuplicateCallbackWithNoOpenSessionDoesNotChangeCountAndRepairsShield`, `testFallBackAmbiguityFailsBlockedWhenResolvedCallbackIsEarly`, and `testMarkedExpiredSessionPersistsClearBeforeMarkerClearAndFullReconcile`; no device run planned. | Unit-covered |
| App termination during a session | Start a session, terminate Pause, wait beyond stored expiry, then activate Pause and the target. | The stored wall-clock expiry remains authoritative and the target returns to the shielded state. | Not run — planned on the iPhone 16 Pro running iOS 26.6. | Pending |
| Daily count reset at local midnight | Exhaust or partially use a rule before local midnight, then check the next prospective session after midnight. | The new local day starts at count zero and offers session 1. | Not run — planned on the iPhone 16 Pro running iOS 26.6. | Pending |
| Session crossing midnight | Start a session before midnight whose stored expiry is after midnight. | The active session stays open until its original expiry while the new day's count resets independently. | Not run — planned on the iPhone 16 Pro running iOS 26.6. | Pending |
| Exhausted allowance | Use every configured session for one rule, then open that target again the same day. | The shield refuses another session with the daily-limit reason and the target stays blocked. | Not run — planned on the iPhone 16 Pro running iOS 26.6. | Pending |
| Rule removal | Remove a configured rule with its target shielded and monitoring state present. | Activity monitoring stops, runtime is removed, and that target is no longer shielded. | Not run — planned on the iPhone 16 Pro running iOS 26.6. | Pending |
| Rule edit during an active session | Start a session, then edit that rule's allowance or duration before stored expiry. | The open session keeps its original expiry and accounting; edits apply only to later decisions. | Not run — planned on the iPhone 16 Pro running iOS 26.6. | Pending |
| Isolated corrupt-runtime repair | Unit tests corrupt one rule's runtime while another stays valid, then drive both flows and a confirmed reset. | Only the affected app stays blocked and Pause offers an explicit confirmed reset; the other rule remains usable. | Covered by `testConfirmedRuntimeResetTouchesOnlySelectedFileAndClearsOnlySelectedMarker`, `testUnrelatedCorruptRuntimeOverridesSelectedPauseWithFailBlockedRepair`, and `testSelectedCorruptIntentRepairIsNotReplacedByUnrelatedCorruptRuntimeRepair`; no device run planned. | Unit-covered |
| Scheduling failure | Unit tests fail Device Activity scheduler registration and reservation before a grant. | The target stays shielded, no session is charged, and the failure is visible. | Covered by `testSchedulingFailureLeavesRuntimeAndShieldUntouched` and `testReservationFailureStopsScheduleAndLeavesShieldIntact`; no device run planned. | Unit-covered |
| Explicit Instagram route failure | Unit tests fail the explicit Instagram open after grant preparation. | Runtime rolls back, monitoring stops, the target is re-shielded, and no session is charged; any incomplete repair is stated accurately. | Covered by `testExplicitRouteFailureRollsBackStopsAndReshieldsWithoutCharging` and `testExplicitLaunchFailureRollsBackStopsReconcilesAndChargesNothing`; no device run planned. | Unit-covered |
| Failed-grant relaunch safety | Unit tests leave a durable failed-grant marker across store instances, including a marker-persistence failure, and check the shield ordering that follows. | The affected app remains shielded across relaunch and Pause exposes its repair path without clearing unrelated state. | Covered by `testMarkerPersistsAcrossStoreInstances`, `testFailedGrantForceShieldPersistsBeforeApplyingImmediateBlock`, and `testFailedGrantMarkerPersistenceFailureStillAppliesShieldInOrder`; no device run planned. | Unit-covered |

## Automated checks for the acceptance commit

```bash
xcodegen generate
xcodebuild test -project Pause.xcodeproj -scheme PauseUnitTests -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
xcodebuild build -project Pause.xcodeproj -scheme Pause -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO
git status --short
```
