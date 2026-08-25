## Status — resume here (2026-08-24)

**State:** On `feat/scheduled-change-presentation`, 30 commits ahead of `design/phased-project-plan`, green at 319 tests, built and installed on the phone. The scheduled-change presentation redesign is complete and reviewed: a marker on each app's row, the cancel scoped to one app in its editor, and a control locked while a change is scheduled for it. The app picker adds only — its selection is a set of additions, and an app leaves Pause from its own row, where removing it keeps the editor open under the pending section. Two rounds of device feedback are folded in. The branch is unmerged and the device checks in `docs/ROADMAP.md` under Deferred have not been run.

**Next step:** Run the deferred device checks on the installed build, then merge to `design/phased-project-plan`.

**Blockers:** No git remote, so nothing can be pushed. Every commit is local only.

**Read first:** Before picker or add-flow work, `docs/design/add-only-app-picker.md`. Before scheduled-change work, `docs/design/scheduled-change-presentation.md`. Before the monitor callbacks or the state lock, `docs/research/session-end-hang.md`.

## Open work

- [ ] Run the device checks `docs/ROADMAP.md` lists under Deferred. The one that matters most is cancelling one app's change leaving another's marker standing — the fault the redesign exists to correct, and the one thing no single-app test can see.
- [ ] Decide whether the view layer is worth testing at all. Three guarantees now rest on reading the code rather than on a test, because `RulesView`, `RuleEditorView` and `AllowanceSection` have no harness: that Save and the pause stepper are disabled and freed as the pending state changes, that a picker selection of only already-covered apps writes nothing, and that a reset-minute-only change leaves `pendingSettingsChange()` nil. The first two are named in the design docs as known gaps.
- [ ] Settle whether the device-wide freeze reported on 2026-08-22 is the same defect seen from outside. The lock-out explains the dead button and the stall; it does not by itself explain the whole phone stopping.
- [ ] Design blocking periods — Phase 2. `docs/ROADMAP.md` under Next carries the reasoning about the activity-registration budget.
