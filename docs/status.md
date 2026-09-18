## Status — resume here (2026-09-18)

**State:** Pause builds with Xcode 27.0 against the iOS 27.0 SDK with no warnings, and the unit suite passes at 340 tests. This build is installed on the iPhone 16 Pro, which is in daily use and now runs the iOS 27.2 developer beta. iOS 27 needs no code changes: the Screen Time frameworks declare nothing new in iOS 27, and neither of the two 27.0 changes that could reach an app like this one (the required scene-based lifecycle and the deprecation of `canOpenURL`) applies to Pause. The SDK reading is in `docs/research/screen-time-platform-evidence.md`. Nothing is in flight.

**Next step:** Run the three device checks owed on this build, listed under Deferred in `docs/ROADMAP.md`. They ride one trip to the phone, now on iOS 27.2. Xcode 27.0 installs to it.

**Blockers:** No git remote, so nothing can be pushed. Every commit is local only.

**Read first:** Drawing a *covered* app's icon or name: `docs/research/screen-time-platform-evidence.md`. Shield press routing: `docs/research/shield-press-routing.md`.
