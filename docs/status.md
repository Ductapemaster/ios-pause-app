## Status — resume here (2026-08-24)

**State:** The post-session cooldown is built, merged to `design/phased-project-plan`, and green at 340 tests; the build is installed and the cooldown refusal was seen working on the phone. A global setting of zero to ten minutes refuses an app a new session for a stretch after one ends, and it ships switched off, so nothing changes until the Cooldown stepper is moved. The app switcher keeps showing a shielded app's last screen; that is iOS holding a stale snapshot, recorded in `docs/README.md` as a limit rather than a defect. Nothing is in flight.

**Next step:** Design Phase 2 blocking periods, which join `RulesEngine.decision` as a further guard (`docs/ROADMAP.md` under Next).

**Blockers:** No git remote, so nothing can be pushed. Every commit is local only.

**Read first:** Shield work: `docs/research/screen-time-platform-evidence.md`. Blocking periods: `docs/design/post-session-cooldown.md`. Picker or add-flow: `docs/design/add-only-app-picker.md`. Monitor callbacks or the state lock: `docs/research/session-end-hang.md`.
