## Status — resume here (2026-09-18)

**State:** A shield press made while Pause sits behind the app switcher now opens the countdown instead of leaving the user on the screen Pause was showing. A waiting shield intent marks the return as a new activation; a banner or a Control Center pull leaves none, so a countdown still survives those (why: the intent store separates the two cases, which the handled-activation flag alone cannot). The unit suite passes at 342 tests. The build is installed on the iPhone 16 Pro, running the iOS 27.2 developer beta; iOS 27 needed no code changes. Nothing is in flight.

**Next step:** Run the four device checks owed on this build, listed under Deferred in `docs/ROADMAP.md`. The app-switcher shield press is the new one. They ride one trip to the phone.

**Blockers:** None. The repo is public at https://github.com/Ductapemaster/ios-pause-app, `main` is the default branch, and the phone's IDs stay in the gitignored `Local.xcconfig`.

**Read first:** The app-switcher fix and the open cold-launch question: `docs/research/shield-press-routing.md`. Drawing a *covered* app's icon or name: `docs/research/screen-time-platform-evidence.md`.
