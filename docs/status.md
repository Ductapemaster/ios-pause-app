## Status — resume here

**State:** The current branch contains the Phase 1 implementation through Task 8, and every automated check passes at head. Phase 1 is not accepted or complete: the entire signed-device matrix is unrun.

**Automated evidence:** At `4b48503` on Xcode 26.6, XcodeGen generation, the complete `PauseUnitTests` scheme (133 tests, 0 failures, iPhone 17 Pro simulator), the unsigned generic iOS build, and `git status --short` with `git diff --check` all pass. The iOS 26.5 SDK production typecheck, modified-test parse, and two-process lock proof also pass; the three commits since that run change only `docs/` and `README.md`, so `aff5c21` remains the last code change and those results still describe the current tree.

**Device evidence:** [The Phase 1 device matrix](testing/phase-1-device-acceptance.md) is entirely unrun. No signed iPhone result is inferred from simulator tests, typechecking, or unsigned builds.

**Blockers:**

- [ ] Run the matrix rows that need no fixture on a signed iPhone 16 build: authorization and denial, multiple selection, independent rule editing, shields after setup and activation, shield identity and count, intent handoff, foreground duration, the three interruption rows, Instagram automatic return, manual return, app termination, midnight reset and crossing, exhausted allowance, rule removal, and rule edit during a session.
- [ ] Implement the temporary Debug-only controls listed in the acceptance record, use them for the signed failure and timing rows, then remove the temporary expiry display, callback trace, and control code after recording the evidence. None of these controls may ship in Release.
- [ ] Run the fixture-dependent rows: three- and sixteen-minute expiry restoration no more than five seconds after stored `expiresAt`, wall-clock session while backgrounded, warning callback activity stop, delayed callback recovery, isolated corrupt-runtime repair, and the scheduling, Instagram route, and failed-grant failure paths.
- [ ] Rerun the automated checks after the Debug control work; the current pass covers `4b48503` only.

**Next step:** Take the fixture-free rows of [`docs/testing/phase-1-device-acceptance.md`](testing/phase-1-device-acceptance.md) to the iPhone 16 in one sitting. Those rows exercise the core action loop and are the first hardware evidence that Screen Time and DeviceActivity behave as the design assumes, so they come before building the seven Debug instruments the remaining rows need. After Phase 1 acceptance, the next roadmap item is Phase 2 time-based rules; history remains a later question.
