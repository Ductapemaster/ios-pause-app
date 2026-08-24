## Status — resume here (2026-08-24)

**State:** Branch `feat/new-app-configuration-flow`, green at 316 tests, installed on the phone and verified there. Adding apps goes through a sheet Pause owns, with a Cancel that discards; each newly picked app gets a screen taking its sessions per day and session length before anything is written, so an app can be given sixteen minutes on the day it is added. A save that only drops apps still defers the removal to the next reset. Shield reconciliation no longer skips when a save contains a removal, which had left an app added in the same save unshielded.

**Next step:** Merge this branch and `feat/session-usage-display` into `design/phased-project-plan` — every check that gated them has passed or been retired. Then Phase 2, blocking periods.

**Blockers:** No git remote, so nothing can be pushed. Every commit is local only.

**Read first:** Before the monitor callbacks or the state lock, `docs/research/session-end-hang.md`. Before any scheduled-change work, `docs/research/scheduled-change-model.md`. Before a check about *when* something ran, the device logs section of `CLAUDE.md` — `log collect` answers timing questions the phone cannot be watched for.

## Open work

- [ ] Settle whether the device-wide freeze reported on 2026-08-22 is the same defect seen from outside. The lock-out explains the dead button and the stall; it does not by itself explain the whole phone stopping.
- [ ] Merge `feat/new-app-configuration-flow` and `feat/session-usage-display` into `design/phased-project-plan`.
- [ ] Build the scheduled-change presentation redesign, after Dan reviews the spec and a plan is written.
- [ ] Design blocking periods — Phase 2. `docs/ROADMAP.md` under Next carries the reasoning about the activity-registration budget.
