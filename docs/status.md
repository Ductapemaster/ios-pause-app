## Status — resume here (2026-08-20)

**State:** Phase 1 is implemented through Task 8 and 192 tests pass. A signed build runs on an iPhone 16 Pro (iOS 26.6) and the core loop works on the phone: the shield names the sessions still available, the pause countdown runs, the session is granted, and Instagram reopens. The shield reads its state without the state lock, because the sandbox profile its configuration extension runs under refuses every write. The 23-row device acceptance matrix is unrun, deferred in favour of new work (why: the app behaves correctly in the use tested so far, and acceptance gates work already built rather than blocking what follows). Deferred rule changes are specified and planned, not built.

**Next step:** Execute `docs/plans/deferred-rule-changes.md` from Task 1, after filling the four under-specified tests it flags and settling the reconciliation trigger named in Task 11.

**Blockers:** No git remote is configured, so nothing can be pushed. Every commit is local only.

**Read first:** Before shield work, `docs/research/shield-repair-variant.md`. Before building deferred changes, `docs/design/deferred-rule-changes.md`.

## Evidence

**Automated:** At head on Xcode 26.6, XcodeGen generation, the complete `PauseUnitTests` scheme (192 tests, 0 failures, iPhone 17 Pro simulator), the unsigned generic iOS build, and `git status --short` with `git diff --check` all pass.

**Device:** A signed Debug build is installed as `com.koubalabs.pause` on an iPhone 16 Pro (`iPhone17,1`) running iOS 26.6, above the iOS 26.5 minimum. All four bundles carry `com.apple.developer.family-controls` and the `group.com.koubalabs.pause` App Group, signed against a team profile valid to 2027-08-12. Instagram is installed. The app group container was deleted and recreated clean, which cleared state inherited from `ios-pause-app-claude` sharing the same group identifier.

**Reading device state:** `devicectl device sysdiagnose` is the route that reads what an extension did — its archive carries the unified log, which `log show --archive --predicate 'subsystem BEGINSWITH "com.koubalabs.pause"'` queries. `log collect` needs both USB and root and has not worked here. `devicectl device copy from --domain-type appGroupDataContainer` reads shared preferences, but nothing running under the shield configuration profile can write there, so it is blind to that extension; it also exposes only standard subdirectories, never the container root, so it cannot see `configuration.json` or the runtime files.

**Matrix:** [The Phase 1 device matrix](testing/phase-1-device-acceptance.md) holds 23 rows to run on the device and 5 settled by named unit tests. Rows 1, 3 and 5 — fresh install, authorization, multiple selection — were exercised during the clean install but are not recorded as passed, because the run that exercised them ended in the watchdog crash.

**Deliberately out of scope:** No Debug-only instruments are built for the five failure-injection rows. The five-second expiry confirmation is deferred with them; wall-clock observation settles the thirty-second blocking threshold [the design](design/pause-app.md) sets.
