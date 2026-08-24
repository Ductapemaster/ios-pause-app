## Status — resume here (2026-08-24)

**State:** On `design/phased-project-plan`, green at 328 tests, with the new-app configuration flow merged and verified on the phone. The scheduled-change presentation redesign is specced and planned but not started: no code written, `docs/plans/scheduled-change-presentation.md` holds six tasks, each ending on a green suite. It replaces the banner and the bespoke pending-removal row with a marker on each app's own row, moves the cancel into that app's editor, and locks a control while a change is scheduled for it. The router is deliberately untouched.

**Next step:** Execute the plan, task by task — subagent-driven was recommended and Dan has not chosen yet.

**Blockers:** No git remote, so nothing can be pushed. Every commit is local only.

**Read first:** Before any scheduled-change work, `docs/design/scheduled-change-presentation.md` then its plan. Before the monitor callbacks or the state lock, `docs/research/session-end-hang.md`. Before a check about *when* something ran, the device logs section of `CLAUDE.md`.

## Open work

- [ ] Execute `docs/plans/scheduled-change-presentation.md`. Six tasks; Task 1 is the two per-row lookups on `AppModel`.
- [ ] Run the three device checks the plan names once it lands: both markers tellable apart at a glance, an app with a pending change opening to locked controls, and cancelling one app's change leaving another's standing. The last is the fault the redesign exists to correct and no single-app test can see it.
- [ ] Settle whether the device-wide freeze reported on 2026-08-22 is the same defect seen from outside. The lock-out explains the dead button and the stall; it does not by itself explain the whole phone stopping.
- [ ] Design blocking periods — Phase 2. `docs/ROADMAP.md` under Next carries the reasoning about the activity-registration budget.
