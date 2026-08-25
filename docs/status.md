## Status — resume here (2026-08-24)

**State:** On `design/phased-project-plan`, green at 319 tests with the device build signing cleanly and installed on the phone. The per-app scheduled change presentation is merged and verified there. Nothing is in flight. A shield change was explored and deliberately not built: forcing a re-entry after a session ends needs a mark that only the user's action can clear, and dismissing a shield by swiping the app away runs no code, so the rule is not expressible. A cooldown replaces it on the roadmap and answers the same want from a timestamp alone.

**Next step:** Unify the shield's refusal screens onto one `Close` button — the one ready task; the rest need designing.

**Blockers:** No git remote, so nothing can be pushed. Every commit is local only.

**Read first:** Before any shield work, `docs/research/screen-time-platform-evidence.md` on the configuration extension's sandbox. Before picker or add-flow work, `docs/design/add-only-app-picker.md`. Before the monitor callbacks or the state lock, `docs/research/session-end-hang.md`.

## Open work

Roughly in the order they are worth taking. The first stands alone; the next two are one design question wearing two hats.

- [ ] **Unify the shield's refusal screens onto a single `Close` button.** On the out-of-sessions screen both buttons already close the app — `"Done for today"` resolves to `.dismiss` and `"Not now"` to `.close` — so one of them restates the other. Ready to build: copy and one button, no new state, no platform unknown. Retires `testEveryPresentationOffersTheSameWayOut`, which pins the two-button shape.
- [ ] **Design the post-session cooldown** (`docs/ROADMAP.md` under Next). The duration policy is the design; the entry lists the open questions and the two things already established.
- [ ] **Design blocking periods — Phase 2** (`docs/ROADMAP.md` under Next). Same shape as the cooldown — a stretch during which entry is refused — so take the two together rather than building separate machinery for one question.
- [ ] Fix the repair shield's button, which reads `"Done for today"` and dismisses beneath text telling the user to open Pause (`docs/ROADMAP.md` under Deferred). Small, and it rides whichever shield task is taken first.
- [ ] Settle whether the device-wide freeze reported on 2026-08-22 is the same defect seen from outside. The lock-out explains the dead button and the stall; it does not by itself explain the whole phone stopping.
- [ ] Decide whether the view layer is worth testing at all. Three guarantees rest on reading the code rather than on a test, because `RulesView`, `RuleEditorView` and `AllowanceSection` have no harness: that Save and the pause stepper are disabled and freed as the pending state changes, that a picker selection of only already-covered apps writes nothing, and that a reset-minute-only change leaves `pendingSettingsChange()` nil. The first two are named in the design docs as known gaps.
