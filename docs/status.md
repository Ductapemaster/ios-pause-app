## Status — resume here (2026-08-22)

**State:** The configurable daily reset is merged to `design/phased-project-plan` and a signed build is installed on the phone, so every outstanding device check is now runnable. Work is in flight on `feat/session-usage-display`, which puts each app's charged sessions in the rules list as `2/4`. Tasks 1–2 of four are committed and green at 302 tests — the reader and the model wiring — leaving the row and the docs. Task 2's review had not returned when the session paused; the diff is committed, so re-dispatching it costs nothing.

**Next step:** Resume `docs/plans/session-usage-display.md` at Task 3, re-running Task 2's review first.

**Blockers:** No git remote, so nothing can be pushed. Every commit is local only.

**Read first:** Before Task 3, `docs/design/session-usage-display.md`. Before any scheduling or callback work, `docs/research/screen-time-platform-evidence.md`.

## Open work

- [ ] Run the device check for the configurable daily reset: move the reset to a quarter-hour a few minutes ahead, spend a session, wait for the reset to pass, and confirm the count renews at the new time rather than at midnight and that the shield reflects the renewed allowance.
- [ ] Confirm on the phone the three interface changes shipped after Phase 1. On the roadmap with what to check.
- [ ] Once `feat/session-usage-display` lands, check on the phone that the list's number moves in step with the shield's and that both renew at the configured reset. The list and the shield disagreeing would mean they resolve the allowance day differently, which is the defect that design exists to prevent.
- [ ] Design blocking periods — the recurring stretches when an app cannot be entered at all. The activity-registration budget is the open question: the research note records a ceiling of 20 monitored activities, reported rather than measured, and one registration per weekday per period reaches it fast.
