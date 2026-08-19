## Status — resume here

**State:** The current branch contains the Phase 1 implementation through Task 8. Phase 1 is not accepted or complete: the latest full automated rerun and the entire signed-device matrix remain pending.

**Automated evidence:** The complete simulator suite and unsigned generic iOS build passed after Task 8 review round 1 at `fc96549`. After the later `d4e6ce3` and `aff5c21` commits, the iOS 26.5 SDK production typecheck, modified-test parse, XcodeGen generation, `git diff --check`, and strengthened two-process lock proof passed. A fresh complete simulator suite and unsigned build after `aff5c21` were blocked by the Codex execution-credit limit, not by a test or build failure; they have not been rerun.

**Device evidence:** [The Phase 1 device matrix](testing/phase-1-device-acceptance.md) is entirely unrun. No signed iPhone result is inferred from simulator tests, typechecking, or unsigned builds.

**Blockers:**

- [ ] Regenerate the project and rerun the complete `PauseUnitTests` scheme and unsigned generic iOS build at the current head.
- [ ] Implement the temporary Debug-only controls listed in the acceptance record, use them for the signed failure and timing rows, then remove the temporary expiry display and control code after recording the evidence. None of these controls may ship in Release.
- [ ] Run the full signed matrix on the iPhone 16, including three- and sixteen-minute expiry restoration no more than five seconds after stored `expiresAt`, Instagram automatic return, another app's manual return, foreground interruptions, and every failure path.

**Next step:** Start at [`docs/testing/phase-1-device-acceptance.md`](testing/phase-1-device-acceptance.md), implement its temporary Debug-only prerequisites, then rerun the automated checks and execute the signed-device matrix. After Phase 1 acceptance, the next roadmap item is Phase 2 time-based rules; history remains a later question.
