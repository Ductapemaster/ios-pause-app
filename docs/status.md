## Status — resume here (2026-08-22)

**State:** The in-app session count is built: the rules list shows each app's charged sessions against its limit for the day in progress, on `feat/session-usage-display`, green at 303 tests. Nothing about it has run on a phone yet. Three device checks are owed, all reachable from one signed build: this count moving in step with the shield's and renewing at the configured reset, the configurable daily reset itself renewing at the configured time rather than at midnight, and the three interface changes that shipped after Phase 1 (countdown cancel, the scene-interruption split, the shield's "Not now").

**Next step:** Build and sign `feat/session-usage-display` for the phone, then work the device checks listed on `docs/ROADMAP.md` under Deferred.

**Blockers:** No git remote, so nothing can be pushed. Every commit is local only.

**Read first:** `docs/ROADMAP.md` for the device checks. Before any scheduling or callback work, `docs/research/screen-time-platform-evidence.md`.

## Open work

- [ ] Run the device check for the configurable daily reset: move the reset to a quarter-hour a few minutes ahead, spend a session, wait for the reset to pass, and confirm the count renews at the new time rather than at midnight and that the shield reflects the renewed allowance.
- [ ] Confirm on the phone the three interface changes shipped after Phase 1. On the roadmap with what to check.
- [ ] Design blocking periods — the recurring stretches when an app cannot be entered at all. The activity-registration budget is the open question: the research note records a ceiling of 20 monitored activities, reported rather than measured, and one registration per weekday per period reaches it fast.
