## Status — resume here (2026-08-23)

**State:** Branch `feat/new-app-configuration-flow`, green at 316 tests, built for device but **not installed** — the phone was unavailable. The new-app configuration flow is written: adding apps now goes through a sheet Pause owns, with Cancel and Save, and each newly picked app gets a screen taking its sessions per day and session length before anything is written. A picker save that only drops apps still defers the removal to the next reset, unchanged. Shield reconciliation no longer skips when a save contains a removal, which had left an app added in the same save unshielded.

**Next step:** Install on the phone and run the device checks — `docs/ROADMAP.md` under Next lists them, and the sixteen-minute expiry check under Deferred is now unblocked and rides the same trip. Whether `FamilyActivityPicker` composes inside our own `NavigationStack` is the one structural unknown and fails visibly.

**Blockers:** No git remote, so nothing can be pushed. Every commit is local only.

**Read first:** Before the monitor callbacks or the state lock, `docs/research/session-end-hang.md`. Before any scheduled-change work, `docs/research/scheduled-change-model.md`.

## Open work

- [ ] Install `feat/new-app-configuration-flow` on the phone and run its device checks, including the sixteen-minute expiry restoration the flow unblocks.
- [ ] Confirm on the phone that the shield's primary button now closes the app in each refusing state: the daily allowance spent, a session already open, and the repair shield. Unit tests reach the decision; they cannot reach a shield button.
- [ ] Settle whether the device-wide freeze reported on 2026-08-22 is the same defect seen from outside. The lock-out explains the dead button and the stall; it does not by itself explain the whole phone stopping.
- [ ] Run the three device checks owed on the installed build: the session count moving in step with the shield's, the configurable daily reset renewing at the configured time rather than at midnight, and the three interface changes shipped after Phase 1. `docs/ROADMAP.md` has what to look for on each.
- [ ] Merge `feat/new-app-configuration-flow` and `feat/session-usage-display` into `design/phased-project-plan`. Held until the device checks pass, since a failure there lands in this code. The session-end fix is already merged into it.
- [ ] Build the scheduled-change presentation redesign, after Dan reviews the spec and a plan is written.
- [ ] Design blocking periods — the recurring stretches when an app cannot be entered at all. The activity-registration budget was thought to be the constraint; on reading the requirements against the shield decision path it probably is not, since a window only refuses entry and entry is decided when the button is pressed. That is reasoning, not a measurement, and building one window would settle it.
