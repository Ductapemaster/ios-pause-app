## Status — resume here (2026-08-20)

**State:** Phase 1 is implemented through Task 8 and 188 tests pass. A signed build runs on an iPhone 16 Pro (iOS 26.6) installed clean, and the core loop works: shield, pause countdown, session grant, automatic return to Instagram. Two device defects are open. Adding an app deadlocked the file lock and the watchdog killed the app; that is fixed and the app now configures without crashing. The shield still renders its repair variant instead of the session count, cause not yet established. The device matrix is otherwise unrun.

**Next step:** Open Instagram on the device, then read `shield-diagnostic-v1` per the command in `docs/research/shield-repair-variant.md`.

**Blockers:** The shield defect blocks the matrix rows covering shield identity, session count, and intent handoff.

**Read first:** Before any shield work, `docs/research/shield-repair-variant.md`.

## Evidence

**Automated:** At head on Xcode 26.6, XcodeGen generation, the complete `PauseUnitTests` scheme (188 tests, 0 failures, iPhone 17 Pro simulator), the unsigned generic iOS build, and `git status --short` with `git diff --check` all pass.

**Device:** A signed Debug build is installed as `com.koubalabs.pause` on an iPhone 16 Pro (`iPhone17,1`) running iOS 26.6, above the iOS 26.5 minimum. All four bundles carry `com.apple.developer.family-controls` and the `group.com.koubalabs.pause` App Group, signed against a team profile valid to 2027-08-12. Instagram is installed. The app group container was deleted and recreated clean, which cleared state inherited from `ios-pause-app-claude` sharing the same group identifier.

**Reading device state:** `log collect` needs both USB and root and has not worked here. `devicectl device copy from --domain-type appGroupDataContainer` reads shared preferences over the network tunnel and is the working route; it exposes only standard subdirectories, never the container root, so it cannot see `configuration.json` or the runtime files.

**Matrix:** [The Phase 1 device matrix](testing/phase-1-device-acceptance.md) holds 23 rows to run on the device and 5 settled by named unit tests. Rows 1, 3 and 5 — fresh install, authorization, multiple selection — were exercised during the clean install but are not recorded as passed, because the run that exercised them ended in the watchdog crash.

**Deliberately out of scope:** No Debug-only instruments are built for the five failure-injection rows. The five-second expiry confirmation is deferred with them; wall-clock observation settles the thirty-second blocking threshold [the design](design/pause-app.md) sets.
