## Status — resume here (2026-08-24)

**State:** The post-session cooldown is built, merged to `design/phased-project-plan`, and green at 340 tests; the build is installed on the phone. A global setting from zero to ten minutes refuses an app a new session for a stretch after one ends, so the shield returning at expiry can no longer be pressed straight through. It ships switched off, so nothing changes until the Cooldown stepper is moved off `Off`.

**Next step:** Two device checks are owed on this build and ride one trip to the phone — `docs/ROADMAP.md` under Deferred. Then Phase 2 blocking periods, which join the same decision as a further guard (`docs/ROADMAP.md` under Next).

**Blockers:** No git remote, so nothing can be pushed. Every commit is local only.

**Read first:** Before any shield work, `docs/research/screen-time-platform-evidence.md` on the configuration extension's sandbox. Before picker or add-flow work, `docs/design/add-only-app-picker.md`. Before the monitor callbacks or the state lock, `docs/research/session-end-hang.md`. Before blocking-period work, `docs/design/post-session-cooldown.md` — the guard it joins and why its position needs no argument.
