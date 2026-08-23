## Status — resume here (2026-08-23)

**State:** Branch `feat/session-usage-display`, green at 311 tests, current build on the phone. The session-end lock-out is fixed, verified, merged and archived. Investigation since then established that the DeviceActivity host keeps the padded interval end where the schedule puts it, and that the `intervalDidEnd` seen at expiry is caused by Pause's own `stopMonitoring`. A new bug is the next work: a newly added app is stuck with the default five-minute session until the following day, which also blocks the sixteen-minute device check.

**Next step:** Explore and build the new-app configuration flow — `docs/ROADMAP.md` under Next has the mechanism, the picker constraint and the four open questions.

**Blockers:** No git remote, so nothing can be pushed. Every commit is local only.

**Read first:** Before the new-app flow or any scheduled-change work, `docs/research/scheduled-change-model.md`. Before touching the monitor callbacks or the state lock, `docs/research/session-end-hang.md`.

## Open work

- [ ] Confirm on the phone that the shield's primary button now closes the app in each refusing state: the daily allowance spent, a session already open, and the repair shield. Unit tests reach the decision; they cannot reach a shield button.
- [ ] Settle whether the device-wide freeze reported on 2026-08-22 is the same defect seen from outside. The lock-out explains the dead button and the stall; it does not by itself explain the whole phone stopping.
- [ ] Build the new-app configuration flow, so an app can be given its session length when it is added. Exploration is unfinished — the design was never presented, and `docs/ROADMAP.md` under Next carries what was established and what is still open.
- [ ] Run the three device checks owed on the installed build: the session count moving in step with the shield's, the configurable daily reset renewing at the configured time rather than at midnight, and the three interface changes shipped after Phase 1. `docs/ROADMAP.md` has what to look for on each.
- [ ] Merge `feat/session-usage-display` into `design/phased-project-plan`. Held until the device checks pass, since a failure there lands in this branch's code. The session-end fix is already merged into it.
- [ ] Build the scheduled-change presentation redesign, after Dan reviews the spec and a plan is written.
- [ ] Design blocking periods — the recurring stretches when an app cannot be entered at all. The activity-registration budget was thought to be the constraint; on reading the requirements against the shield decision path it probably is not, since a window only refuses entry and entry is decided when the button is pressed. That is reasoning, not a measurement, and building one window would settle it.
