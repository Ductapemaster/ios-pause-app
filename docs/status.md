## Status — resume here (2026-08-22)

**State:** Phase 1 is accepted, closed and merged. The configurable daily reset — half the Phase 2 gate — is built: 285 tests pass at head, build warning-free. The device check has not run — it needs a signed build on the phone and cannot run in the simulator. Blocking periods are the other half of the gate and are deliberately a separate effort, designed later (why: they are additive, while the reset changes what a day means).

**Next step:** Run the device check in `docs/ROADMAP.md`, then design blocking periods.

**Blockers:** No git remote, so nothing can be pushed. Every commit is local only.

**Read first:** `docs/design/configurable-daily-reset.md` for the reset's design. Before any scheduling or callback work, `docs/research/screen-time-platform-evidence.md`.

## Open work

- [ ] Run the device check for the configurable daily reset: move the reset to a quarter-hour a few minutes ahead, spend a session, wait for the reset to pass, and confirm the count renews at the new time rather than at midnight and that the shield reflects the renewed allowance.
- [ ] Confirm on the phone the three interface changes shipped after Phase 1. On the roadmap with what to check.
- [ ] Design blocking periods — the recurring stretches when an app cannot be entered at all. The activity-registration budget is the open question: the research note records a ceiling of 20 monitored activities, reported rather than measured, and one registration per weekday per period reaches it fast.
