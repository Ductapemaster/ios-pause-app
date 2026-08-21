## Status — resume here (2026-08-21)

**State:** A saved edit is now judged one app at a time, so an app added in the same picker trip that drops another is covered today, and a change scheduled for one app survives a save about a different one. Built to [the design](design/per-app-rule-changes.md) via [its plan](plans/per-app-rule-changes.md); 258 tests pass, the unsigned build is warning-free, and a signed build carrying it is installed on the phone. Device acceptance was cut from 23 rows to one twenty-minute run-through plus a sixteen-minute wait, with every dropped row named and reasoned. Neither has been run. The monitor extension's app group access is settled: file I/O is permitted, measured on device.

**Next step:** Run the device acceptance run-through from a fresh install, recording each of the ten steps.

**Blockers:** No git remote is configured, so nothing can be pushed. Every commit is local only.

**Read first:** Before shield work, `docs/research/shield-repair-variant.md`. Before scheduling or callback work, `docs/research/screen-time-platform-evidence.md`. Before starting a storage change, the roadmap's open SQLite decision — it would delete `AppGroupFileLock`.

## Evidence

**Automated:** At head on Xcode 26.6, XcodeGen generation, the complete `PauseUnitTests` scheme (258 tests, 0 failures across `PauseCoreTests` 57, `PauseSharedTests` 149, `PauseAppTests` 52, iPhone 17 Pro simulator), the unsigned generic iOS build with no Swift warnings, and a clean `git status --short` all pass.

**Device:** A signed Debug build of `5d7ab65`, the last commit carrying code, is installed as `com.koubalabs.pause` on an iPhone 16 Pro (`iPhone17,1`) running iOS 26.6, above the iOS 26.5 minimum. All four bundles carry `com.apple.developer.family-controls` and the `group.com.koubalabs.pause` App Group, signed against a team profile valid to 2027-08-12. Instagram is installed. It was installed over the previous build rather than fresh, so the acceptance run needs Pause and its data deleted first.

**The monitor extension's app group access is settled.** `AppGroupSandboxProbe` runs `open(O_CREAT|O_RDWR)`, `flock`, `write` and unlock against its own file on every monitor callback and reported `permitted` at all four callbacks of a live session on 2026-08-20; the shield action extension is the control reading, and `AppGroupSandboxProbeTests` establishes that the probe reports a refusal where one genuinely occurs. No entry at error level appeared from any `com.koubalabs.pause` subsystem across the run. [The platform evidence note](research/screen-time-platform-evidence.md) carries the readings and two things they leave open: which sandbox profile the monitor extension point is assigned, and why the expiry callbacks took 31 seconds to return after the shield was already applied in the first 86 ms.

**What per-app judgment changed, beyond the picker.** The unit of judgment is one rule with its target, plus settings as a unit of their own; `ConfigurationSaveRouter` builds both documents from it and no save path changed shape. A file written by the previous router can hold an app added but left waiting, named by the scheduled document alone — that app is now covered rather than dropped, which is the one place the build went past the plan (why: silent loss of a configured app is correctness, not polish).

**Matrix:** [Device acceptance](testing/phase-1-device-acceptance.md) is a ten-step run-through, plus a sixteen-minute expiry row that uses `intervalDidEnd` where the settled three-minute row uses `intervalWillEndWarning`. Five requirements are settled by named unit tests, and seven earlier rows are listed as deliberately not verified on the device, each with its reason. The five-second timing tier is abandoned as a goal rather than deferred: thirty seconds is settled with wide margin, and five would need the stored `expiresAt` written into the log beside the callback.

**Known limits carried deliberately:** Cancelling clears everything scheduled rather than one app's change, even though the rules list presents a scheduled removal per row. A save states its opinion by rebuilding, so a rule editor save that changes nothing reads as untouched and carries a scheduled change forward.

**Deliberately out of scope:** No Debug-only instruments are built for the failure-injection cases; the unit suite covers them.
