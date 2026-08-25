## Status — resume here (2026-08-24)

**State:** Merged to `design/phased-project-plan` and green at 320 tests; the device build signs cleanly and is installed on the phone. Every refusal shield now shows a single `Close` button, which also settles the repair screen's contradiction. Nothing is in flight, and nothing else is ready to build — both remaining roadmap items are designs rather than builds. One device check is owed on this build, listed in `docs/ROADMAP.md` under Deferred.

**Next step:** Design the post-session cooldown together with Phase 2 blocking periods (`docs/ROADMAP.md` under Next) — one design question in two places.

**Blockers:** No git remote, so nothing can be pushed. Every commit is local only.

**Read first:** Before any shield work, `docs/research/screen-time-platform-evidence.md` on the configuration extension's sandbox. Before picker or add-flow work, `docs/design/add-only-app-picker.md`. Before the monitor callbacks or the state lock, `docs/research/session-end-hang.md`.

## Open work

Roughly in the order they are worth taking. The first two are one design question wearing two hats.

- [ ] **Design the post-session cooldown** (`docs/ROADMAP.md` under Next). The duration policy is the design; the entry lists the open questions and the two things already established.
- [ ] **Design blocking periods — Phase 2** (`docs/ROADMAP.md` under Next). Same shape as the cooldown — a stretch during which entry is refused — so take the two together rather than building separate machinery for one question.
- [ ] Settle whether the device-wide freeze reported on 2026-08-22 is the same defect seen from outside. The lock-out explains the dead button and the stall; it does not by itself explain the whole phone stopping.
- [ ] Decide whether the view layer is worth testing at all. Three guarantees rest on reading the code rather than on a test, because `RulesView`, `RuleEditorView` and `AllowanceSection` have no harness: that Save and the pause stepper are disabled and freed as the pending state changes, that a picker selection of only already-covered apps writes nothing, and that a reset-minute-only change leaves `pendingSettingsChange()` nil. The first two are named in the design docs as known gaps.
