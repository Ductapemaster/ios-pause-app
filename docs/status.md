## Status — resume here

**State:** The current branch contains the Phase 1 implementation through Task 8, every automated check passes at head, and a signed build is installed on the test device. Phase 1 is not accepted or complete: the device matrix is unrun.

**Automated evidence:** At `4b48503` on Xcode 26.6, XcodeGen generation, the complete `PauseUnitTests` scheme (133 tests, 0 failures, iPhone 17 Pro simulator), the unsigned generic iOS build, and `git status --short` with `git diff --check` all pass. The iOS 26.5 SDK production typecheck, modified-test parse, and two-process lock proof also pass; the commits since that run change only `docs/` and `README.md`, so `aff5c21` remains the last code change and those results still describe the current tree.

**Device readiness:** A signed Debug build of `4b48503` is installed as `com.koubalabs.pause` on an iPhone 16 Pro (`iPhone17,1`) running iOS 26.6, above the iOS 26.5 minimum. All four bundles carry `com.apple.developer.family-controls` and the `group.com.koubalabs.pause` App Group, signed against a team profile valid to 2027-08-12. Instagram is installed on the same device. The app has not been launched: `SBMainWorkspace` refuses a remote launch while the device is locked.

**Device evidence:** [The Phase 1 device matrix](testing/phase-1-device-acceptance.md) is unrun. No signed iPhone result is inferred from simulator tests, typechecking, or unsigned builds.

**Blockers:**

- [ ] Run the 23 device rows in [`docs/testing/phase-1-device-acceptance.md`](testing/phase-1-device-acceptance.md). Four of them measure expiry against observed wall-clock time and need a session of at least sixteen minutes; two need a local midnight to pass.
- [ ] Record the exact build and observations in the run record, then resolve any row that fails.

**Deliberately out of scope:** The five failure-injection rows are covered by named unit tests and are marked unit-covered in the matrix; no Debug-only instruments are built for them. The five-second expiry confirmation is deferred with them — wall-clock observation settles the thirty-second blocking threshold that [the design](design/pause-app.md) sets.

**Next step:** Unlock the phone, open Pause, and work the matrix from its first row. After Phase 1 acceptance, the next roadmap item is Phase 2 time-based rules; history remains a later question.
