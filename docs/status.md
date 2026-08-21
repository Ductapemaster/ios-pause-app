## Status — resume here (2026-08-20)

**State:** The monitor extension's sandbox permits file I/O in the app group container — measured on device, so shield restoration at session expiry rests on a verified permission rather than an assumption. The shield configuration extension's denial is writes only; its reads succeed. Deferred rule changes are built: an edit permitting more app use waits for the next daily reset, an edit that tightens applies at once, and a removal stays visible and greyed until it lands. 237 tests pass and the unsigned device build is clean. Two product decisions are settled and unbuilt: a picker save that both adds and drops apps should judge each app on its own, and the single pending slot stays last-write-wins, made visible by the notice naming what is scheduled. 22 device acceptance rows are still unrun.

**Next step:** Design, then plan, judging each app in a picker save separately, so an added app is restricted today rather than waiting with a dropped one.

**Blockers:** No git remote is configured, so nothing can be pushed. Every commit is local only.

**Read first:** Before shield work, `docs/research/shield-repair-variant.md`. Before scheduling or callback work, `docs/research/screen-time-platform-evidence.md`.

## Evidence

**Automated:** At head on Xcode 26.6, XcodeGen generation, the complete `PauseUnitTests` scheme (237 tests, 0 failures, iPhone 17 Pro simulator), the unsigned generic iOS build with no Swift warnings, and a clean `git status --short` all pass.

**Device:** A signed Debug build is installed as `com.koubalabs.pause` on an iPhone 16 Pro (`iPhone17,1`) running iOS 26.6, above the iOS 26.5 minimum. All four bundles carry `com.apple.developer.family-controls` and the `group.com.koubalabs.pause` App Group, signed against a team profile valid to 2027-08-12. Instagram is installed. A three-minute session was run end to end on 2026-08-20 and the shield returned at expiry. Nothing else from the deferred-rule-changes work has run on the phone.

**The monitor extension's app group access is settled.** `AppGroupSandboxProbe` runs `open(O_CREAT|O_RDWR)`, `flock`, `write` and unlock against its own file on every monitor callback and reports `permitted` at all four callbacks of a live session; the shield action extension is the control reading and `AppGroupSandboxProbeTests` establishes that the probe reports a refusal where one genuinely occurs. No entry at error level appeared from any `com.koubalabs.pause` subsystem across the run. [The platform evidence note](research/screen-time-platform-evidence.md) carries the readings. Two things it leaves open: which sandbox profile the monitor extension point is assigned, and why the expiry callbacks took 31 seconds to return after the shield was already applied in the first 86 ms.

**Matrix:** [The Phase 1 device matrix](testing/phase-1-device-acceptance.md) holds 22 rows to run on the device and 5 settled by named unit tests. Three-minute expiry restoration passes against the thirty-second threshold; its five-second tier is not settled, because the stored `expiresAt` appears in no log. Rows 1, 3 and 5 were exercised during a clean install but are not recorded as passed, because that run ended in the watchdog crash. The deferred-change rows are additional to those.

**Known limits carried deliberately:** A save made while a change is scheduled replaces it rather than stacking onto it, because there is one pending slot and each candidate is built from the rules in force. The notice names what is scheduled so a replaced removal is visible in the list, but nothing prompts before replacing it.

**Deliberately out of scope:** No Debug-only instruments are built for the five failure-injection rows. The five-second expiry confirmation is deferred with them; wall-clock observation settles the thirty-second blocking threshold [the design](design/pause-app.md) sets.
