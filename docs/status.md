## Status — resume here (2026-08-23)

**State:** Two bugs were reported in use on 2026-08-22 and the branch is now `fix/shield-primary-button-dismiss`, green at 311 tests and installed on the phone. The shield's dead "Done for today" button is fixed: every refusing state now closes the shielded app instead of doing nothing. The device hang when a session ended near midnight is **not** fixed — no root cause, and no fix attempted. The shield render now logs entry and exit at `notice` so the next occurrence is diagnosable. The scheduled-change presentation spec still awaits Dan's review.

**Next step:** Capture device logs at the next hang, following the checklist in `docs/research/session-end-hang.md`.

**Blockers:** No git remote, so nothing can be pushed. Every commit is local only.

**Read first:** Before any work on the hang, `docs/research/session-end-hang.md` — it holds what is ruled out and how to capture evidence. Before planning the redesign, `docs/research/scheduled-change-model.md`. `docs/ROADMAP.md` for the device checks.

## Open work

- [ ] Confirm on the phone that the shield's primary button now closes the app in each refusing state: the daily allowance spent, a session already open, and the repair shield. Unit tests reach the decision; they cannot reach a shield button.
- [ ] Root-cause the device hang when a session ends. Blocked on evidence from the next occurrence — `docs/research/session-end-hang.md`.
- [ ] Run the three device checks owed on the installed build: the session count moving in step with the shield's, the configurable daily reset renewing at the configured time rather than at midnight, and the three interface changes shipped after Phase 1. `docs/ROADMAP.md` has what to look for on each.
- [ ] Merge `feat/session-usage-display` into `design/phased-project-plan`. Held until the device checks pass, since a failure there lands in this branch's code.
- [ ] Build the scheduled-change presentation redesign, after Dan reviews the spec and a plan is written.
- [ ] Design blocking periods — the recurring stretches when an app cannot be entered at all. The activity-registration budget is the open question: the research note records a ceiling of 20 monitored activities, reported rather than measured, and one registration per weekday per period reaches it fast.
