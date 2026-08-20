## Status — resume here (2026-08-19)

**State:** Phase 1 is implemented through Task 8 and every automated check passes at `4b48503`. A signed Debug build is installed on the iPhone 16 Pro. Phase 1 is not accepted: the 23-row device matrix is unrun. No Debug-only instruments exist (why: the five failure rows exercise Pause's own rollback code, which named unit tests already cover, rather than Screen Time itself).
**Next step:** Unlock the phone, open Pause, and work the device matrix from its first row.
**Blockers:** Two matrix rows need a local midnight; two need sessions of sixteen minutes.
**Read first:** Before any timing row, `docs/testing/phase-1-device-acceptance.md`.

## Evidence

**Automated:** At `4b48503` on Xcode 26.6, XcodeGen generation, the complete `PauseUnitTests` scheme (133 tests, 0 failures, iPhone 17 Pro simulator), the unsigned generic iOS build, and `git status --short` with `git diff --check` all pass. The iOS 26.5 SDK production typecheck, modified-test parse, and two-process lock proof also pass; the commits since that run change only `docs/` and `README.md`, so `aff5c21` remains the last code change and those results still describe the current tree.

**Device:** A signed Debug build of `4b48503` is installed as `com.koubalabs.pause` on an iPhone 16 Pro (`iPhone17,1`) running iOS 26.6, above the iOS 26.5 minimum. All four bundles carry `com.apple.developer.family-controls` and the `group.com.koubalabs.pause` App Group, signed against a team profile valid to 2027-08-12. Instagram is installed on the same device. The app has not been launched: `SBMainWorkspace` refuses a remote launch while the device is locked.

**Matrix:** [The Phase 1 device matrix](testing/phase-1-device-acceptance.md) holds 23 rows to run on the device and 5 settled by named unit tests. No signed iPhone result is inferred from simulator tests, typechecking, or unsigned builds. The five-second expiry confirmation is deferred with the instruments; wall-clock observation settles the thirty-second blocking threshold [the design](design/pause-app.md) sets.
