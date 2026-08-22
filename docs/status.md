## Status — resume here (2026-08-22)

**State:** Phase 1 is accepted, closed and merged. The configurable daily reset — half the Phase 2 gate — is designed and planned but no code is written. 263 tests pass at head, build warning-free. Blocking periods are the other half and are deliberately a separate effort, designed later (why: they are additive, while the reset changes what a day means).

**Next step:** Execute `docs/plans/configurable-daily-reset.md` from Task 1, one task at a time.

**Blockers:** No git remote, so nothing can be pushed. Every commit is local only.

**Read first:** Before executing, the plan's spec `docs/design/configurable-daily-reset.md`. Before any scheduling or callback work, `docs/research/screen-time-platform-evidence.md`.

## Open work

- [ ] Build the configurable daily reset — six tasks in `docs/plans/configurable-daily-reset.md`. Task 4 opens with a simulator probe that settles whether iOS honours a schedule wrapping past midnight; both branches are written into the task.
- [ ] Confirm on the phone the three interface changes shipped after Phase 1, and the reset once built. Both are on the roadmap with what to check.
- [ ] Design blocking periods — the recurring stretches when an app cannot be entered at all. The activity-registration budget is the open question: the research note records a ceiling of 20 monitored activities, reported rather than measured, and one registration per weekday per period reaches it fast.
