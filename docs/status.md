## Status — resume here (2026-08-22)

**State:** Two threads. The in-app session count is built, reviewed and installed on the phone from `feat/session-usage-display`, green at 307 tests — three device checks are owed on that build, and the overnight renewal check is running. Separately, the scheduled-change presentation is designed but not built: `docs/design/scheduled-change-presentation.md` moves every pending change onto the row of the thing it changes, deletes the banner and the pending-removal row, and adds per-app cancel. The spec is awaiting Dan's review; no implementation plan exists yet.

**Next step:** Once Dan approves the spec, write the implementation plan for `docs/design/scheduled-change-presentation.md`.

**Blockers:** No git remote, so nothing can be pushed. Every commit is local only.

**Read first:** Before planning or building the redesign, `docs/research/scheduled-change-model.md` — it maps what per-app cancel costs. `docs/ROADMAP.md` for the device checks.


## Open work

- [ ] Run the three device checks owed on the installed build: the session count moving in step with the shield's, the configurable daily reset renewing at the configured time rather than at midnight, and the three interface changes shipped after Phase 1. `docs/ROADMAP.md` has what to look for on each.
- [ ] Merge `feat/session-usage-display` into `design/phased-project-plan`. Held until the device checks pass, since a failure there lands in this branch's code.
- [ ] Build the scheduled-change presentation redesign, after Dan reviews the spec and a plan is written.
- [ ] Design blocking periods — the recurring stretches when an app cannot be entered at all. The activity-registration budget is the open question: the research note records a ceiling of 20 monitored activities, reported rather than measured, and one registration per weekday per period reaches it fast.
