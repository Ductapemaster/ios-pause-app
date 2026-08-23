## Status — resume here (2026-08-23)

**State:** Branch `fix/shield-primary-button-dismiss`, green at 313 tests, installed on the phone. Task 1 of the session-end plan has landed and is verified on the device: `stopMonitoring` now runs outside the app group state lock, so the 31 seconds it spends not returning no longer lock every other participant out, and the shield's primary button acts during that window. Tasks 2 and 3 remain — the call still blocks the monitor handler for the extension's remaining life, and a lock timeout still closes the app as though the day's allowance were spent.

**Next step:** Continue `docs/plans/session-end-lock-contention.md` at task 3 — it is self-contained and closes the last wrong answer the user can see. Task 2 opens with a measurement and a decision, so it wants a session of its own.

**Blockers:** No git remote, so nothing can be pushed. Every commit is local only.

**Read first:** Before any work on the defect, `docs/research/session-end-hang.md` for the mechanism and the reproduction. Before planning the redesign, `docs/research/scheduled-change-model.md`. `docs/ROADMAP.md` for the device checks.

## Open work

- [ ] Confirm on the phone that the shield's primary button now closes the app in each refusing state: the daily allowance spent, a session already open, and the repair shield. Unit tests reach the decision; they cannot reach a shield button.
- [ ] Execute `docs/plans/session-end-lock-contention.md` tasks 2 and 3 — each its own commit, test first. Task 1 is done.
- [ ] Settle whether the device-wide freeze reported on 2026-08-22 is the same defect seen from outside. The lock-out explains the dead button and the stall; it does not by itself explain the whole phone stopping.
- [ ] Run the three device checks owed on the installed build: the session count moving in step with the shield's, the configurable daily reset renewing at the configured time rather than at midnight, and the three interface changes shipped after Phase 1. `docs/ROADMAP.md` has what to look for on each.
- [ ] Merge `feat/session-usage-display` into `design/phased-project-plan`. Held until the device checks pass, since a failure there lands in this branch's code.
- [ ] Build the scheduled-change presentation redesign, after Dan reviews the spec and a plan is written.
- [ ] Design blocking periods — the recurring stretches when an app cannot be entered at all. The activity-registration budget is the open question: the research note records a ceiling of 20 monitored activities, reported rather than measured, and one registration per weekday per period reaches it fast.
