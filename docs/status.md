## Status — resume here (2026-08-23)

**State:** Branch `fix/shield-primary-button-dismiss`, green at 311 tests, installed on the phone. The session-end defect is understood and reproduced: `stopMonitoring`, called from inside `intervalWillEndWarning` while the app group state lock is held, does not return for 31 seconds, and every other participant fails at the lock's 2-second deadline. That is what made the shield button dead. No fix is written. Separately, the "Done for today" button was fixed on 2026-08-23 — every refusing state now closes the app — but that same change wrongly closes the app on a lock timeout, which task 3 of the plan corrects.

**Next step:** Execute `docs/plans/session-end-lock-contention.md`, task 1 first — it is the one that ends the lock-out.

**Blockers:** No git remote, so nothing can be pushed. Every commit is local only.

**Read first:** Before any work on the defect, `docs/research/session-end-hang.md` for the mechanism and the reproduction. Before planning the redesign, `docs/research/scheduled-change-model.md`. `docs/ROADMAP.md` for the device checks.

## Open work

- [ ] Confirm on the phone that the shield's primary button now closes the app in each refusing state: the daily allowance spent, a session already open, and the repair shield. Unit tests reach the decision; they cannot reach a shield button.
- [ ] Execute `docs/plans/session-end-lock-contention.md` — three tasks, each its own commit, test first.
- [ ] Settle whether the device-wide freeze reported on 2026-08-22 is the same defect seen from outside. The lock-out explains the dead button and the stall; it does not by itself explain the whole phone stopping.
- [ ] Run the three device checks owed on the installed build: the session count moving in step with the shield's, the configurable daily reset renewing at the configured time rather than at midnight, and the three interface changes shipped after Phase 1. `docs/ROADMAP.md` has what to look for on each.
- [ ] Merge `feat/session-usage-display` into `design/phased-project-plan`. Held until the device checks pass, since a failure there lands in this branch's code.
- [ ] Build the scheduled-change presentation redesign, after Dan reviews the spec and a plan is written.
- [ ] Design blocking periods — the recurring stretches when an app cannot be entered at all. The activity-registration budget is the open question: the research note records a ceiling of 20 monitored activities, reported rather than measured, and one registration per weekday per period reaches it fast.
