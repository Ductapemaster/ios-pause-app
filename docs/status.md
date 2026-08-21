## Status — resume here (2026-08-20)

**State:** Deferred rule changes are built: an edit permitting more app use waits for the next daily reset, an edit that tightens applies at once, and a removal stays visible and greyed until it lands. 234 tests pass and the unsigned device build is clean. Two product decisions are settled and unbuilt: a picker save that both adds and drops apps should judge each app on its own (an add tightens, so it should apply today), and the single pending slot stays last-write-wins, made visible by the notice naming what is scheduled. The 23-row device acceptance matrix is still unrun, deferred so acceptance gates work already built (why: the app behaves correctly in the use tested so far).

**Next step:** Design, then plan, judging each app in a picker save separately, so an added app is restricted today rather than waiting with a dropped one.

**Blockers:** No git remote is configured, so nothing can be pushed. Every commit is local only.

**Read first:** Before shield work, `docs/research/shield-repair-variant.md`. Before scheduling or callback work, `docs/research/screen-time-platform-evidence.md`.

## Evidence

**Automated:** At head on Xcode 26.6, XcodeGen generation, the complete `PauseUnitTests` scheme (234 tests, 0 failures, iPhone 17 Pro simulator), the unsigned generic iOS build with no Swift warnings, and a clean `git status --short` all pass.

**Device:** A signed Debug build is installed as `com.koubalabs.pause` on an iPhone 16 Pro (`iPhone17,1`) running iOS 26.6, above the iOS 26.5 minimum. All four bundles carry `com.apple.developer.family-controls` and the `group.com.koubalabs.pause` App Group, signed against a team profile valid to 2027-08-12. Instagram is installed. Nothing from the deferred-rule-changes work has run on the phone.

**Unverified, and load-bearing beyond this effort:** No observation exists of the monitor extension opening a file in the App Group container. Its entitlements match the other targets, but the sandbox profile is the discriminator and `com.apple.deviceactivity.monitor-extension`'s is unrecorded. The shipped session-expiry path already depends on that write, so a failure would mean shield restoration has never worked, independent of deferred changes. One session expiry on device plus `log show --archive --predicate 'subsystem BEGINSWITH "com.koubalabs.pause"'` over a `devicectl device sysdiagnose` archive settles it: a refusal surfaces as a `SessionReconciliationIssue(operation: .acquireStateLock)`.

**Matrix:** [The Phase 1 device matrix](testing/phase-1-device-acceptance.md) holds 23 rows to run on the device and 5 settled by named unit tests. Rows 1, 3 and 5 were exercised during a clean install but are not recorded as passed, because that run ended in the watchdog crash. The deferred-change rows are additional to those.

**Known limits carried deliberately:** A save made while a change is scheduled replaces it rather than stacking onto it, because there is one pending slot and each candidate is built from the rules in force. The notice names what is scheduled so a replaced removal is visible in the list, but nothing prompts before replacing it.

**Deliberately out of scope:** No Debug-only instruments are built for the five failure-injection rows. The five-second expiry confirmation is deferred with them; wall-clock observation settles the thirty-second blocking threshold [the design](design/pause-app.md) sets.
