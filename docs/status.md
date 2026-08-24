## Status — resume here (2026-08-24)

**State:** On `feat/scheduled-change-presentation`, 21 commits ahead of `design/phased-project-plan`, green at 319 tests with the device build signing cleanly. The scheduled-change presentation redesign is built and reviewed: a marker on each app's own row, the cancel scoped to one app in its editor, and a control locked while a change is scheduled for it. The app picker is add-only — its selection is a set of additions, and an app leaves Pause only from its own row. An earlier build was tried on the phone; the three pieces of feedback from it are all implemented, and the build carrying them has not been installed.

**Next step:** Install the built app on the phone (it is at `/tmp/pause-dd/Build/Products/Debug-iphoneos/Pause.app`) and run the device checks, then merge to `design/phased-project-plan`.

**Blockers:** The phone reads `unavailable` to `devicectl`, so the install cannot run. No git remote; every commit is local.

**Read first:** Before picker or add-flow work, `docs/design/add-only-app-picker.md`. Before scheduled-change work, `docs/design/scheduled-change-presentation.md`. Before the monitor callbacks or the state lock, `docs/research/session-end-hang.md`.

## Open work

- [ ] Run the device checks `docs/ROADMAP.md` lists under Deferred. The one that matters most is cancelling one app's change leaving another's marker standing — the fault the redesign exists to correct, and the one thing no single-app test can see.
- [ ] Confirm on the phone that the disabled `Remove app` button renders greyed rather than red beside the destructive `Cancel removal`. Established by reading the code and SwiftUI's documented behaviour, never measured (why: reaching that screen needs a full Family Controls authorization and save, which no headless run can drive).
- [ ] Decide whether `NewAppSetupSheet`'s step-advance decision is worth extracting into a free function. The guarantee that a picker selection of only already-covered apps writes nothing is currently held by code-reading alone; the repo has no view-testing harness.
- [ ] Settle whether the device-wide freeze reported on 2026-08-22 is the same defect seen from outside. The lock-out explains the dead button and the stall; it does not by itself explain the whole phone stopping.
- [ ] Design blocking periods — Phase 2. `docs/ROADMAP.md` under Next carries the reasoning about the activity-registration budget.
