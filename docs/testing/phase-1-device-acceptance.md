# Phase 1 device acceptance

Phase 1 is not accepted until every row below has a concrete signed-device observation and passes. Simulator tests and unsigned builds do not substitute for Screen Time behavior on the phone.

## Run record

- Date and tester: `<YYYY-MM-DD; name>`
- Device and OS: `iPhone 16; iOS <exact version>` (minimum supported version: iOS 26.5)
- App source and build: `commit <SHA>; Xcode <version>; signed build <identifier>`
- Selected apps: `Instagram; <manual-return app>`
- Expiry evidence: `stored expiresAt <timestamp>; shield restored <timestamp>; measured delay <seconds>`
- Concrete observation: `<what appeared, what was tapped, count/state before and after, and any error text>`

Use a fresh install where specified. Record the exact installed iOS 26.x version before the run. iOS 27 requires a separate qualification run after its release and matching Xcode toolchain are available.

## Acceptance matrix

| Requirement | Test setup | Expected | Observed | Pass/Fail |
|---|---|---|---|---|
| Fresh install and Screen Time authorization | Delete Pause and its data, install the signed build, then request individual authorization. | Authorization succeeds and the app reaches empty configuration without creating a rule first. | Not run — planned on iPhone 16; record the exact installed iOS 26.x version, minimum 26.5. | Pending |
| Denied authorization | From a fresh install, deny the individual Screen Time request. | Pause stays in setup state and creates no rules or claim of enforcement. | Not run — planned on iPhone 16; record the exact installed iOS 26.x version, minimum 26.5. | Pending |
| Multiple application selection | Grant authorization and select Instagram plus another installed app in one Apple picker save. | Both eligible apps are selected and shown with Apple's labels and icons. | Not run — planned on iPhone 16; record the exact installed iOS 26.x version, minimum 26.5. | Pending |
| Independent rule editing | Give Instagram and the second app different daily allowances and session lengths, then reopen both editors. | Each app retains only its own saved values. | Not run — planned on iPhone 16; record the exact installed iOS 26.x version, minimum 26.5. | Pending |
| Shields after setup and activation | Save both rules, open each target, return to Pause, then activate each target again. | Both targets are shielded after setup and remain correctly shielded after later app activation. | Not run — planned on iPhone 16; record the exact installed iOS 26.x version, minimum 26.5. | Pending |
| Per-app shield identity and next-session count | Configure different allowances, then open each shield. | Apple's app identity is correct and each shield shows that rule's independent prospective session number. | Not run — planned on iPhone 16; record the exact installed iOS 26.x version, minimum 26.5. | Pending |
| Shield intent handoff | Tap Continue on each app's shield in separate attempts. | Pause opens and starts the flow for the same app whose shield was tapped. | Not run — planned on iPhone 16; record the exact installed iOS 26.x version, minimum 26.5. | Pending |
| Foreground pause duration | Start a pause and leave Pause active until the configured duration elapses. | Use becomes available only after the full configured foreground duration. | Not run — planned on iPhone 16; record the exact installed iOS 26.x version, minimum 26.5. | Pending |
| Home interruption | Press Home before the pause completes, reopen Pause, and begin again. | The attempt is abandoned, no session is charged, and the full pause restarts. | Not run — planned on iPhone 16; record the exact installed iOS 26.x version, minimum 26.5. | Pending |
| Lock interruption | Lock before the pause completes, unlock, reopen Pause, and begin again. | The attempt is abandoned, no session is charged, and the full pause restarts. | Not run — planned on iPhone 16; record the exact installed iOS 26.x version, minimum 26.5. | Pending |
| Scene interruption | Leave Control Center open long enough for Pause to become inactive, then return and begin again. | The attempt is abandoned, no session is charged, and the full pause restarts. | Not run — planned on iPhone 16; record the exact installed iOS 26.x version, minimum 26.5. | Pending |
| Instagram automatic return | Complete an Instagram pause and choose Use. | The session activates, exactly one session is charged, and `instagram://` returns to Instagram automatically. | Not run — planned on iPhone 16; record the exact installed iOS 26.x version, minimum 26.5. | Pending |
| Manual return | Complete a pause for the app without a supported route and choose Use. | The session activates before instructions appear; returning through Home or App Switcher opens the target. | Not run — planned on iPhone 16; record the exact installed iOS 26.x version, minimum 26.5. | Pending |
| Wall-clock session while backgrounded | Start a session, background the target for part of its duration, then return before and after stored expiry. | Background time consumes the grant; access remains open only until the original stored `expiresAt`. | Not run — planned on iPhone 16; record the exact installed iOS 26.x version, minimum 26.5. | Pending |
| Three-minute expiry restoration | Start a three-minute session and record stored `expiresAt` and the shield's return time. | The warning callback restores the shield no more than five seconds after stored expiry. | Not run — planned on iPhone 16; record the exact installed iOS 26.x version, minimum 26.5. | Pending |
| Sixteen-minute expiry restoration | Start a sixteen-minute session and record stored `expiresAt` and the shield's return time. | The interval-end callback restores the shield no more than five seconds after stored expiry. | Not run — planned on iPhone 16; record the exact installed iOS 26.x version, minimum 26.5. | Pending |
| Warning callback activity stop | Observe the three-minute warning path through the underlying fifteen-minute activity, then open the target again after expiry. | The warning path attempts to stop monitoring without an early end, duplicate charge, lost shield, or blocked future session. | Not run — planned on iPhone 16; record the exact installed iOS 26.x version, minimum 26.5. | Pending |
| Delayed callback recovery | Prevent or delay the expected expiry callback, wait beyond stored expiry, then activate Pause. | App activation clears the expired session and restores the shield from stored expiry. | Not run — planned on iPhone 16; record the exact installed iOS 26.x version, minimum 26.5. | Pending |
| App termination during a session | Start a session, terminate Pause, wait beyond stored expiry, then activate Pause and the target. | The stored wall-clock expiry remains authoritative and the target returns to the shielded state. | Not run — planned on iPhone 16; record the exact installed iOS 26.x version, minimum 26.5. | Pending |
| Daily count reset at local midnight | Exhaust or partially use a rule before local midnight, then check the next prospective session after midnight. | The new local day starts at count zero and offers session 1. | Not run — planned on iPhone 16; record the exact installed iOS 26.x version, minimum 26.5. | Pending |
| Session crossing midnight | Start a session before midnight whose stored expiry is after midnight. | The active session stays open until its original expiry while the new day's count resets independently. | Not run — planned on iPhone 16; record the exact installed iOS 26.x version, minimum 26.5. | Pending |
| Exhausted allowance | Use every configured session for one rule, then open that target again the same day. | The shield refuses another session with the daily-limit reason and the target stays blocked. | Not run — planned on iPhone 16; record the exact installed iOS 26.x version, minimum 26.5. | Pending |
| Rule removal | Remove a configured rule with its target shielded and monitoring state present. | Activity monitoring stops, runtime is removed, and that target is no longer shielded. | Not run — planned on iPhone 16; record the exact installed iOS 26.x version, minimum 26.5. | Pending |
| Rule edit during an active session | Start a session, then edit that rule's allowance or duration before stored expiry. | The open session keeps its original expiry and accounting; edits apply only to later decisions. | Not run — planned on iPhone 16; record the exact installed iOS 26.x version, minimum 26.5. | Pending |
| Isolated corrupt-runtime repair | In a Debug build, corrupt one selected rule's runtime while another rule remains valid, then activate both flows. | Only the affected app stays blocked and Pause offers an explicit confirmed reset; the other rule remains usable. | Not run — planned on iPhone 16; record the exact installed iOS 26.x version, minimum 26.5. | Pending |
| Scheduling failure | Inject Device Activity registration failure before a grant. | The target stays shielded, no session is charged, and the failure is visible. | Not run — planned on iPhone 16; record the exact installed iOS 26.x version, minimum 26.5. | Pending |
| Explicit Instagram route failure | In a Debug build, inject an unavailable Instagram route after preparation. | Runtime rolls back, monitoring stops, the target is re-shielded, and no session is charged; any incomplete repair is stated accurately. | Not run — planned on iPhone 16; record the exact installed iOS 26.x version, minimum 26.5. | Pending |
| Failed-grant relaunch safety | Inject a rollback or repair failure that leaves a durable failed-grant marker, terminate Pause, and relaunch. | The affected app remains shielded across relaunch and Pause exposes its repair path without clearing unrelated state. | Not run — planned on iPhone 16; record the exact installed iOS 26.x version, minimum 26.5. | Pending |

## Automated checks for the acceptance commit

```bash
xcodegen generate
xcodebuild test -project Pause.xcodeproj -scheme PauseUnitTests -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
xcodebuild build -project Pause.xcodeproj -scheme Pause -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO
git status --short
```
