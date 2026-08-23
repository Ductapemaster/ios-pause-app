## Status — resume here (2026-08-22)

**State:** The configurable daily reset is merged to `design/phased-project-plan` and a signed build is installed on the phone, so every outstanding device check is now runnable. Work is in flight on `feat/session-usage-display`, which puts each app's charged sessions in the rules list as `2/4`. Tasks 1–2 of four are committed, reviewed and green at 303 tests — the reader and the model wiring — leaving the row and the docs close-out. Task 2's review approved it with one parked finding, recorded below.

**Next step:** Add the parked call-site comment, then resume `docs/plans/session-usage-display.md` at Task 3.

**Blockers:** No git remote, so nothing can be pushed. Every commit is local only.

**Read first:** Before Task 3, `docs/design/session-usage-display.md`. Before any scheduling or callback work, `docs/research/screen-time-platform-evidence.md`.

## Open work

- [ ] Comment the `refreshUsage(now: now)` call site in `AppModel.sceneDidBecomeActive`. Its position has two reasons and only one is protected: a test pins that it must precede the `.unchanged` early return, but nothing guards that it must also *follow* the activation coordinator, whose reconciliation can roll back a provisional session and lower a count. Hoisting it above that would compile, pass every test, and publish a count one too high.
- [ ] Run the device check for the configurable daily reset: move the reset to a quarter-hour a few minutes ahead, spend a session, wait for the reset to pass, and confirm the count renews at the new time rather than at midnight and that the shield reflects the renewed allowance.
- [ ] Confirm on the phone the three interface changes shipped after Phase 1. On the roadmap with what to check.
- [ ] Once `feat/session-usage-display` lands, check on the phone that the list's number moves in step with the shield's and that both renew at the configured reset. The list and the shield disagreeing would mean they resolve the allowance day differently, which is the defect that design exists to prevent.
- [ ] Design blocking periods — the recurring stretches when an app cannot be entered at all. The activity-registration budget is the open question: the research note records a ceiling of 20 monitored activities, reported rather than measured, and one registration per weekday per period reaches it fast.
