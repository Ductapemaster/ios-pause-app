## Status — resume here (2026-08-21)

**State:** Phase 1 is accepted and closed. The core action loop is built and in use on the phone: authorization, selection, shielding, shield handoff, the pause countdown, session grants, the daily limit, and per-app judgment of a saved edit. 258 tests pass, the unsigned build is warning-free, and a signed build is installed. Acceptance was made on ordinary device use across several configured apps rather than on the scripted run-through, which is kept as a regression script; [the acceptance doc](testing/phase-1-device-acceptance.md) records that basis and what it leaves unverified. One gap is carried knowingly: the sixteen-minute expiry row, where a session over fifteen minutes expires on `intervalDidEnd` rather than the observed `intervalWillEndWarning`. Any use of a session that long settles it.

**Next step:** Start Phase 2, time-based rules — design before code. [The roadmap](ROADMAP.md) carries the product feedback raised from device use and the open SQLite storage decision, which should be settled before the file-lock work it would delete.

**Blockers:** No git remote is configured, so nothing can be pushed. Every commit is local only.

**Read first:** Before shield work, `docs/research/shield-repair-variant.md`. Before scheduling or callback work, `docs/research/screen-time-platform-evidence.md`. Before starting a storage change, the roadmap's open SQLite decision — it would delete `AppGroupFileLock`.

## Evidence

**Automated:** At head on Xcode 26.6, XcodeGen generation, the complete `PauseUnitTests` scheme (258 tests, 0 failures across `PauseCoreTests` 57, `PauseSharedTests` 149, `PauseAppTests` 52, iPhone 17 Pro simulator), the unsigned generic iOS build with no Swift warnings, and a clean `git status --short` all pass.

**Device:** A signed Debug build of `5d7ab65`, the last commit carrying code, is installed as `com.koubalabs.pause` on an iPhone 16 Pro (`iPhone17,1`) running iOS 26.6, above the iOS 26.5 minimum. All four bundles carry `com.apple.developer.family-controls` and the `group.com.koubalabs.pause` App Group, signed against a team profile valid to 2027-08-12. Instagram is installed. It was installed over the previous build rather than fresh; the regression script starts from a fresh install, so it needs Pause and its data deleted first.

**The monitor extension's app group access is settled.** `AppGroupSandboxProbe` runs `open(O_CREAT|O_RDWR)`, `flock`, `write` and unlock against its own file on every monitor callback and reported `permitted` at all four callbacks of a live session on 2026-08-20; the shield action extension is the control reading, and `AppGroupSandboxProbeTests` establishes that the probe reports a refusal where one genuinely occurs. No entry at error level appeared from any `com.koubalabs.pause` subsystem across the run. [The platform evidence note](research/screen-time-platform-evidence.md) carries the readings and two things they leave open: which sandbox profile the monitor extension point is assigned, and why the expiry callbacks took 31 seconds to return after the shield was already applied in the first 86 ms.

**What per-app judgment changed, beyond the picker.** The unit of judgment is one rule with its target, plus settings as a unit of their own; `ConfigurationSaveRouter` builds both documents from it and no save path changed shape. A file written by the previous router can hold an app added but left waiting, named by the scheduled document alone — that app is now covered rather than dropped, which is the one place the build went past the plan (why: silent loss of a configured app is correctness, not polish).

**Matrix:** [Device acceptance](testing/phase-1-device-acceptance.md) records the basis for acceptance and keeps the ten-step run-through as a regression script. Five requirements are settled by named unit tests, and seven earlier rows are listed as deliberately not verified on the device, each with its reason. Of the two timed rows, the three-minute `intervalWillEndWarning` restoration passed on 2026-08-20 and the sixteen-minute `intervalDidEnd` restoration is unverified. The five-second timing tier is abandoned as a goal rather than deferred: thirty seconds is settled with wide margin, and five would need the stored `expiresAt` written into the log beside the callback.

**Known limits carried deliberately:** Cancelling clears everything scheduled rather than one app's change, even though the rules list presents a scheduled removal per row. A save states its opinion by rebuilding, so a rule editor save that changes nothing reads as untouched and carries a scheduled change forward.

**Deliberately out of scope:** No Debug-only instruments are built for the failure-injection cases; the unit suite covers them.
