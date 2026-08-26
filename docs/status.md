## Status — resume here (2026-08-25)

**State:** The pause screens no longer show the covered app's icon. A lone 35pt `Label(applicationToken)` identified nothing — it cannot be resized and the name beside it cannot be read without an entitlement Pause does not hold — so both `PauseView` and `ManualReturnView` now carry Pause's own wordmark, "Take a Pause", where the icon sat, above the session line. The countdown's duplicate 15pt caption is gone with it. `AppIdentityBadge` and `ManualReturnContent.applicationToken` are deleted; `AppTokenLabel` stays for the list screens, where a row of system icons and names is what belongs. Merged to `design/phased-project-plan`, green at 340 tests, installed on the phone. Nothing is in flight.

**Next step:** Run the three device checks owed on this build, listed under Deferred in `docs/ROADMAP.md` — they ride one trip to the phone.

**Blockers:** No git remote, so nothing can be pushed. Every commit is local only.

**Read first:** Anything touching the app icon or name: `docs/research/screen-time-platform-evidence.md`. Shield press routing: `docs/research/shield-press-routing.md`.
