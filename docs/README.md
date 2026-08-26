# Pause — the model and the why

Pause puts a deliberate pause and a daily allowance between a reflex and an app. This page is the durable overview: what the system is, the decisions that shape it, and what it knowingly does not do. [The architecture](design/pause-app.md) carries the as-built depth; [the roadmap](ROADMAP.md) carries what is next.

## The model

A **rule** covers one app with a daily allowance: how many sessions, and how long each runs. A covered app is **shielded** by Screen Time. Tapping through the shield opens Pause, which runs a **countdown** in the foreground; only when it completes can the user spend a session. Spending one grants timed access, and expiry restores the shield. A **cooldown** — a global length from zero to ten minutes — then refuses that app a new session for a stretch, so the shield returning at expiry cannot be pressed straight through ([its design](design/post-session-cooldown.md)). The allowance renews at the start of the next **allowance day**, which begins at the daily reset — a setting, on a fifteen-minute grid, applying to all seven days, that defaults to midnight. The rules list shows each app's charged sessions against its limit for the day in progress; this is the same allowance the shield reports, and both resolve it the same way ([the design](design/session-usage-display.md)).

Two properties hold the design together:

- **The allowance cannot be edited around within a day.** A change that permits more use waits for the next daily reset; a change that permits less applies at once. The wait rides the same instant the session count returns to zero, so an edit made late in the day grants nothing that day.
- **A judgment is made per app, not per document.** A save states an opinion about the apps it touches, so a decision about one app never holds up a decision about another.

## Decisions that shape it

**State lives in JSON files under one App Group lock.** Every process — app, monitor, shield config, shield action — coordinates through one lock file, and a compound operation holds it from first read through the final shield decision. SQLite was weighed and declined: its write-ahead journal coordinates through cross-process shared memory, which interacts badly with iOS file protection on a locked device, and that is exactly when the extensions run. The current design approximates the transactions SQLite would give by holding one lock across the whole operation.

**No framework call happens while the lock is held.** The lock protects the JSON state and nothing else, so a `DeviceActivity` or `ManagedSettings` call belongs outside it. Holding one across `stopMonitoring` deadlocked the monitor for 31 seconds: both end callbacks arrive together on different threads of the one extension process, and the sibling blocked on the lock is what the stop was waiting on. Released first, the same call costs 11 ms. The mechanism is in [the session-end note](research/session-end-hang.md).

**The shield configuration extension can read but not write.** Its sandbox refuses every write in the App Group container. The monitor extension is not so limited — file I/O from it is permitted, measured across all four callbacks of a live session. Repairs therefore run from the app or the monitor, never from the shield.

**A session's stored expiry is authoritative.** Interruptions — backgrounding, termination, an edit mid-session — do not recompute it. That makes the accounting a pure function over stored values, which is why the unit suite can pin it exactly and the device is needed only for what iOS itself does.

**The device is for observing iOS, not for checking arithmetic.** Shield presentation and identity, intent handoff, callback timing and authorization are visible only on a phone. Everything that is Pause's own bookkeeping is a value-type computation and is unit-covered.

## What it knowingly does not do

- **Device time is taken as given.** The allowance day comes from the device clock and calendar, so moving the clock or crossing time zones moves the boundary. Not defended against — the cost is not worth a case that arises in travel rather than in use.
- **Deleting Pause defeats all of it.** Reinstalling gives a clean slate. Nothing in the design prevents that, and nothing can.
- **The app switcher keeps showing a shielded app's last screen.** Its card holds the snapshot iOS captured during the session that has since expired, so a refused app looks open until it is selected, at which point the shield presents and refuses. The card is a picture rather than a live view, and no session is granted behind it. Nothing here can change it: no public API reaches another app's snapshot, and shields present on foreground. That iOS never retakes the snapshot when a shield goes up is read from the behaviour rather than from anything Apple states.
- **A restricted app's website is blocked, by a screen Pause does not control.** iOS shields an app's associated web domains along with the app, so reaching the site in a browser returns the system's "Restricted" screen — no app name, no session count, and a button that starts nothing. The shield configuration and action extensions are never consulted for it, measured on device, so the appearance and the dead end are both iOS's. The only route into a session is the app icon. Pause never names a domain; the block follows from the token it shields. [The evidence](research/screen-time-platform-evidence.md).
- **One pending slot, not a queue.** A second save replaces a scheduled change for that app rather than stacking onto it, and cancelling is the only way back to the rules in force.
- **A save states its opinion by rebuilding.** Touched is inferred from the resulting document rather than declared by the screen, so a save that changes nothing reads as untouched and carries a scheduled change forward. The rule editor and the settings controls close the interface route to it by locking: a pending change locks the controls of the thing it changes, so there is no save to make while one is standing. The app picker closes its route differently, by never expressing an opinion about coverage at all: it is add-only, so a save's candidate unit for an already-covered app always matches what is in force, and the router's read of a matching unit as no opinion is now what preserves that app's scheduled change, rather than a route by which a re-tick can silently no-op one.
- **The countdown length is the one field a late edit reaches.** It is not per-day, so it has no reset to ride in on; shortening it late takes effect that much sooner. Accepted — the exposure is a few seconds.
- **Pause cannot show a covered app's name, and cannot resize its icon.** `Label(applicationToken)` is the only way to draw an app's identity from a token, and both halves are fixed: the icon at 35pt, the name at one drawn size that ignores `.font` and always aligns leading. Reading the name as a string instead fails too — `localizedDisplayName` is nil without an entitlement this app does not hold. Measured on device. [The evidence](research/screen-time-platform-evidence.md).

  This splits the screens two ways. The list screens — rules, rule editor, repair, the setup sheet — draw the label as it comes, because a row of system icons and names is what a list of apps should look like. The pause screens name nothing: a lone 35pt icon identified the app no better than the screen's own title did, so they carry Pause's wordmark instead and say the rest in Pause's own words.
- **A shield press is discarded when Pause never went to the background.** Leaving Pause by the app switcher puts it `.inactive` rather than `.background`, and only `.background` clears the flag that marks an activation handled. A shield press arriving after that is treated as an activation already dealt with, so the intent goes unread and the user stays on the screen Pause was showing. Measured on device. One flag decides both this and the case it exists for — holding a running countdown through a banner or a Control Center pull — and it cannot tell them apart. [The investigation](research/shield-press-routing.md).
- **The scene-interruption split is not verified on the phone.** Whether a notification banner raised over a countdown abandons the pause is reachable only by a person with a device; unit tests reach the model, not a SwiftUI scene phase. Left unverified deliberately — the failure is immediate and obvious in ordinary use, so it surfaces as a bug report more cheaply than as a staged check.
- **Moving the daily reset refills the day.** A reset-time change applies the moment it is saved, and a session count rolls over whenever the allowance day's label changes — in either direction — so setting the reset a few minutes out hands back the day's sessions, which makes the cap advisory rather than enforced. Accepted for the comparison logic it saves, with the guard that would close it named in [the design](design/configurable-daily-reset.md).

## Where things are

- [product-requirements.md](product-requirements.md) — the product source of truth.
- [design/pause-app.md](design/pause-app.md) — the standing architecture, all phases.
- [design/post-session-cooldown.md](design/post-session-cooldown.md) — the cooldown after a session ends.
- [ROADMAP.md](ROADMAP.md) — the single prioritized what's-next.
- [status.md](status.md) — the resume pointer.
- [research/](research/) — open investigations: the shield sandbox variant, and the Screen Time platform readings.
- [archive/](archive/) — shipped efforts, frozen. Phase 1's folder holds the regression script for the core loop.
