# Phase 1 device acceptance

Phase 1 is accepted as of 2026-08-21, on informal device use across several configured apps rather than on the run-through below. Bugs are fixed as they surface in use.

## Basis for acceptance

The Phase 1 loop was exercised on the phone in ordinary use with multiple apps: authorization, selection, shielding, shield handoff, the pause countdown, session grants and the daily limit. That use was not scripted and was not recorded step by step, so no step below carries a run record.

This is acceptance by judgment: it says the loop works in use. It does not say each row below was observed. Two consequences worth holding:

- A row here is unverified unless its own section says otherwise. The unit-covered requirements further down are the exception — those are pinned exactly, and are not affected by how the device pass was made.
- **The sixteen-minute expiry row is not covered by that use and not covered by the unit suite.** It is the one behaviour Phase 1 ships without evidence for; see [the two timed rows](#the-two-timed-rows).

The run-through is kept below as a regression script. It is what to run when a bug appears in the loop, and the cheapest way to re-establish the whole loop after a change that reaches it.

## What the device is for

The device is irreplaceable for one thing: observing what iOS itself does. Screen Time authorization, shield presentation and identity, shield intent handoff, Device Activity callback timing, and how a live session behaves are only visible on the phone. Everything that is Pause's own bookkeeping — what a session costs, what a rollback restores, which day a count belongs to — is a pure function over value types and is pinned by unit tests, which are faster, exact, and do not need a phone.

Almost everything in the first category happens in **one continuous pass** through the app: authorize, pick, shield, tap, pause, return, expire, exhaust. Running it as one scripted sitting rather than as separate cases is what keeps the script to about twenty minutes.

## The regression script

One sitting, in order, from a **fresh install** — delete Pause and its data first. A step that fails stops the run: later steps assume the earlier ones.

Record, if run:

- Date and tester: `<YYYY-MM-DD; name>`
- Device and OS: `iPhone 16 Pro (iPhone17,1); iOS 26.6` (minimum supported version: iOS 26.5)
- App source and build: `commit <sha>; signed Debug build; bundle ID com.koubalabs.pause`
- Selected apps: `Instagram; <second app>`
- Concrete observation per step: `<what appeared, what was tapped, count/state before and after, and any error text>`

iOS 27 requires a separate qualification run after its release and matching Xcode toolchain are available.

**Settings that make the script fit the sitting.** The pause countdown is global and ranges 1–120 seconds; set it to 30, long enough to press Home mid-countdown at step 6. Give Instagram 1 session × 3 min, so step 7 exhausts it and step 9 needs no extra grants. Give the second app 2 sessions × 16 min — different on both axes, which is what makes a rule/token mispairing visible at step 3, and its grant at step 8 doubles as the sixteen-minute timed row. The second app must not be Instagram, which is the only app with a supported launch route (`LaunchRoute.swift:19`), so any other choice exercises the manual-return path.

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
| 10 | Remove a configured rule whose target is shielded, then advance the device date one day and reopen Pause. | Monitoring stops, the runtime goes, and that target is no longer shielded. |

**Why step 10 moves the clock.** A removal is a loosening (`ConfigurationComparison.swift:38-40`), so it writes the pending document and the rule stays in force — shielding, counting, still in the picker — until the logical day turns over, which Phase 1 puts at local midnight. Waiting for it does not fit a sitting. Advancing the date is a faithful trigger rather than a workaround: the pending document is selected at read time on `pending.startDay <= logicalDay` (`ConfigurationFile.swift:32`), and the reset reconciliation is registered on every app open and resolves what applies from the moment it runs. This is a state question, not a timing one, which is what separates it from the midnight rows listed as deliberately not verified — there, moving the clock would change the thing being measured.

## The two timed rows

These need a wait that will not fit inside the sitting. Start each and walk away.

| Requirement | Setup | Expected | Observed | Pass/Fail |
|---|---|---|---|---|
| Three-minute expiry restoration | Start a three-minute session; record the wall-clock start and the time the shield returns. | The warning callback restores the shield well inside the thirty-second blocking threshold. | Run 2026-08-20 on the iPhone 16 Pro running iOS 26.6. `intervalWillEndWarning` arrived 22:40:39.290 and the shield rendered the exhausted variant at 22:40:39.376, 182.4s after the session's `intervalDidStart` at 22:37:36.843. | Pass against the thirty-second threshold |
| Sixteen-minute expiry restoration | Start a sixteen-minute session; record the wall-clock start and the time the shield returns. | The interval-end callback restores the shield well inside the thirty-second blocking threshold. | Not observed. | Unverified |

The sixteen-minute row is not a longer copy of the three-minute one. A session under fifteen minutes is padded to a fifteen-minute schedule and expires on `intervalWillEndWarning`; a longer session expires on `intervalDidEnd`. They are different callbacks, and only the shorter one has been observed.

**This is the one gap Phase 1 carries knowingly.** The failure it would catch is silent and open-ended: if `intervalDidEnd` does not restore the shield, a session longer than fifteen minutes never ends and the target stays unblocked until something else reconciles. Any use of a session over fifteen minutes settles it, so it costs a single sixteen-minute wait to close whenever that is worth doing.

**The five-second tier is not settled and is not being pursued.** [The design](../../design/pause-app.md) tiers the criterion at five seconds to pass and thirty to block. The wall clock and the unified log both settle thirty. Five would need the stored `expiresAt` in the log alongside the callback, because both callbacks carry an unmeasured latency against the moments they name — an instrument worth building only if a restoration is ever seen to run late.

## Settled by unit tests

These exercise Pause's own rollback, repair and accounting rather than Screen Time behavior, so a device adds nothing they do not already have. They hold regardless of how the device pass was made.

| Requirement | Covered by |
|---|---|
| Delayed callback recovery | `testDuplicateCallbackWithNoOpenSessionDoesNotChangeCountAndRepairsShield`, `testFallBackAmbiguityFailsBlockedWhenResolvedCallbackIsEarly`, `testMarkedExpiredSessionPersistsClearBeforeMarkerClearAndFullReconcile` |
| Isolated corrupt-runtime repair | `testConfirmedRuntimeResetTouchesOnlySelectedFileAndClearsOnlySelectedMarker`, `testUnrelatedCorruptRuntimeOverridesSelectedPauseWithFailBlockedRepair`, `testSelectedCorruptIntentRepairIsNotReplacedByUnrelatedCorruptRuntimeRepair` |
| Scheduling failure | `testSchedulingFailureLeavesRuntimeAndShieldUntouched`, `testReservationFailureStopsScheduleAndLeavesShieldIntact` |
| Explicit Instagram route failure | `testExplicitRouteFailureRollsBackStopsAndReshieldsWithoutCharging`, `testExplicitLaunchFailureRollsBackStopsReconcilesAndChargesNothing` |
| Failed-grant relaunch safety | `testMarkerPersistsAcrossStoreInstances`, `testFailedGrantForceShieldPersistsBeforeApplyingImmediateBlock`, `testFailedGrantMarkerPersistenceFailureStillAppliesShieldInOrder` |

## Deliberately not verified on the device

Each of these was a row in an earlier, longer matrix. Dropping a row does not make its behavior verified — it makes it **unverified by choice**, on the reasoning given. Any of them is worth reinstating if the behavior it names ever misbehaves in use.

- **Lock interruption** and **scene interruption**. At acceptance both reached the same branch as pressing Home, so triggering one of the three — the script's step 6 — covered the code path. That is no longer true: scene handling now abandons an attempt only on backgrounding, and a transient loss of active status stands. A banner or Control Center pull is therefore its own path, and confirming a countdown survives one is worth a row if the behaviour is ever doubted. Locking still reaches backgrounding, so it still abandons.
- **Denied authorization.** A whole fresh-install-and-deny cycle to observe one setup screen refusing to advance.
- **Multiple application selection as its own row.** Apple's picker rendering Apple's labels is Apple's behavior; step 2 depends on the selection working anyway, so a failure there stops the run regardless.
- **Independent rule editing as its own row.** Per-rule persistence is unit-covered and folded into step 2, where it costs nothing to look.
- **Wall-clock session while backgrounded**, **app termination during a session**, and **rule edit during an active session.** All three assert that the stored `expiresAt` stays authoritative through an interruption. That is accounting over stored values, which the unit suite covers directly and exactly.
- **Daily count reset at local midnight** and **session crossing midnight.** Both need the tester awake at midnight or the device clock moved, which changes the thing being measured. The logical-day computation is unit-covered, and the device half — whether the `daily-reset` activity actually fires — was observed on 2026-08-20: `intervalDidStart for activity daily-reset` at 22:36:50, recorded in [the platform evidence note](../../research/screen-time-platform-evidence.md).
- **Warning callback activity stop.** A choreographed seventeen-minute two-session sequence to confirm that a stale interval end does not cancel a live session. The same note establishes the `stopMonitoring` → `intervalDidEnd` semantics it rests on, and the 2026-08-20 run shows that exact callback pair arriving together and being handled without error.

## Automated checks

```bash
xcodegen generate
xcodebuild test -project Pause.xcodeproj -scheme PauseUnitTests -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
xcodebuild build -project Pause.xcodeproj -scheme Pause -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO
git status --short
```
