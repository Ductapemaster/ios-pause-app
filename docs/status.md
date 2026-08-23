## Status — resume here (2026-08-23)

**State:** Branch `fix/shield-primary-button-dismiss`, green at 311 tests, installed on the phone. The shield's dead "Done for today" button is fixed — every refusing state now closes the app. The device hang is **not** fixed and has no root cause. A sysdiagnose established that Pause never crashed (no crash, hang, or jetsam record; the process ran continuously across the incident) and that the daily reset is 05:00, so midnight is not the reset boundary. Pause's own logging for that window is gone — the archive retains no third-party subsystem entries that far back.

**Next step:** Gather a sysdiagnose within the hour of the next hang, phone unlocked, per `docs/research/session-end-hang.md`.

**Blockers:** No git remote, so nothing can be pushed. Every commit is local only.

**Read first:** Before any work on the hang, `docs/research/session-end-hang.md` — what is ruled out, and why a late capture cannot answer it. Before planning the redesign, `docs/research/scheduled-change-model.md`. `docs/ROADMAP.md` for the device checks.

## Open work

- [ ] Confirm on the phone that the shield's primary button now closes the app in each refusing state: the daily allowance spent, a session already open, and the repair shield. Unit tests reach the decision; they cannot reach a shield button.
- [ ] Root-cause the device hang when a session ends. Blocked on a prompt capture at the next occurrence — `docs/research/session-end-hang.md`.
- [ ] Measure what applying a picker selection actually costs on the main thread. `docs/ROADMAP.md` records the path and says measuring is the first move once a hang is reported; one now has been, and the picker opened minutes after it.
- [ ] Run the three device checks owed on the installed build: the session count moving in step with the shield's, the configurable daily reset renewing at the configured time rather than at midnight, and the three interface changes shipped after Phase 1. `docs/ROADMAP.md` has what to look for on each.
- [ ] Merge `feat/session-usage-display` into `design/phased-project-plan`. Held until the device checks pass, since a failure there lands in this branch's code.
- [ ] Build the scheduled-change presentation redesign, after Dan reviews the spec and a plan is written.
- [ ] Design blocking periods — the recurring stretches when an app cannot be entered at all. The activity-registration budget is the open question: the research note records a ceiling of 20 monitored activities, reported rather than measured, and one registration per weekday per period reaches it fast.
