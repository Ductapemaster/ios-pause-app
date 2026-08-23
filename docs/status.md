## Status — resume here (2026-08-23)

**State:** Branch `fix/shield-primary-button-dismiss`, green at 314 tests, installed on the phone. The session-end plan is done. Task 1 released the app group state lock before `stopMonitoring`, verified on the device; task 3 gave the shield a third outcome so a lock timeout leaves the shield up instead of closing the app; task 2 closed on measurement — the call costs 11 ms off the lock, so the stop stays. The 31-second block was a deadlock between the state lock and the DeviceActivity host, not a slow framework call.

**Next step:** Merge the branch, then run the device checks `docs/ROADMAP.md` lists as owed on this build.

**Blockers:** No git remote, so nothing can be pushed. Every commit is local only.

**Read first:** Before planning the redesign, `docs/research/scheduled-change-model.md`. Before any work touching the monitor callbacks or the state lock, `docs/research/session-end-hang.md`. `docs/ROADMAP.md` for the device checks.

## Open work

- [ ] Confirm on the phone that the shield's primary button now closes the app in each refusing state: the daily allowance spent, a session already open, and the repair shield. Unit tests reach the decision; they cannot reach a shield button.
- [ ] Fold `docs/plans/session-end-lock-contention.md` into `docs/archive/session-end-lock-contention/` — all three tasks are done.
- [ ] Settle whether the device-wide freeze reported on 2026-08-22 is the same defect seen from outside. The lock-out explains the dead button and the stall; it does not by itself explain the whole phone stopping.
- [ ] Run the three device checks owed on the installed build: the session count moving in step with the shield's, the configurable daily reset renewing at the configured time rather than at midnight, and the three interface changes shipped after Phase 1. `docs/ROADMAP.md` has what to look for on each.
- [ ] Merge `feat/session-usage-display` into `design/phased-project-plan`. Held until the device checks pass, since a failure there lands in this branch's code.
- [ ] Build the scheduled-change presentation redesign, after Dan reviews the spec and a plan is written.
- [ ] Design blocking periods — the recurring stretches when an app cannot be entered at all. The activity-registration budget is the open question: the research note records a ceiling of 20 monitored activities, reported rather than measured, and one registration per weekday per period reaches it fast.
