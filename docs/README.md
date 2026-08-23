# Pause — the model and the why

Pause puts a deliberate pause and a daily allowance between a reflex and an app. This page is the durable overview: what the system is, the decisions that shape it, and what it knowingly does not do. [The architecture](design/pause-app.md) carries the as-built depth; [the roadmap](ROADMAP.md) carries what is next.

## The model

A **rule** covers one app with a daily allowance: how many sessions, and how long each runs. A covered app is **shielded** by Screen Time. Tapping through the shield opens Pause, which runs a **countdown** in the foreground; only when it completes can the user spend a session. Spending one grants timed access, and expiry restores the shield. The allowance renews at the start of the next **allowance day**, which begins at the daily reset — a setting, on a fifteen-minute grid, applying to all seven days, that defaults to midnight. The rules list shows each app's charged sessions against its limit for the day in progress; this is the same allowance the shield reports, and both resolve it the same way ([the design](design/session-usage-display.md)).

Two properties hold the design together:

- **The allowance cannot be edited around within a day.** A change that permits more use waits for the next daily reset; a change that permits less applies at once. The wait rides the same instant the session count returns to zero, so an edit made late in the day grants nothing that day.
- **A judgment is made per app, not per document.** A save states an opinion about the apps it touches, so a decision about one app never holds up a decision about another.

## Decisions that shape it

**State lives in JSON files under one App Group lock.** Every process — app, monitor, shield config, shield action — coordinates through one lock file, and a compound operation holds it from first read through the final shield decision. SQLite was weighed and declined: its write-ahead journal coordinates through cross-process shared memory, which interacts badly with iOS file protection on a locked device, and that is exactly when the extensions run. The current design approximates the transactions SQLite would give by holding one lock across the whole operation.

**The shield configuration extension can read but not write.** Its sandbox refuses every write in the App Group container. The monitor extension is not so limited — file I/O from it is permitted, measured across all four callbacks of a live session. Repairs therefore run from the app or the monitor, never from the shield.

**A session's stored expiry is authoritative.** Interruptions — backgrounding, termination, an edit mid-session — do not recompute it. That makes the accounting a pure function over stored values, which is why the unit suite can pin it exactly and the device is needed only for what iOS itself does.

**The device is for observing iOS, not for checking arithmetic.** Shield presentation and identity, intent handoff, callback timing and authorization are visible only on a phone. Everything that is Pause's own bookkeeping is a value-type computation and is unit-covered.

## What it knowingly does not do

- **Device time is taken as given.** The allowance day comes from the device clock and calendar, so moving the clock or crossing time zones moves the boundary. Not defended against — the cost is not worth a case that arises in travel rather than in use.
- **Deleting Pause defeats all of it.** Reinstalling gives a clean slate. Nothing in the design prevents that, and nothing can.
- **One pending slot, not a queue.** A second save replaces a scheduled change for that app rather than stacking onto it, and cancelling is the only way back to the rules in force.
- **A save states its opinion by rebuilding.** Touched is inferred from the resulting document rather than declared by the screen, so an editor save that changes nothing reads as untouched and carries a scheduled change forward.
- **The countdown length is the one field a late edit reaches.** It is not per-day, so it has no reset to ride in on; shortening it late takes effect that much sooner. Accepted — the exposure is a few seconds.
- **Expiry restoration is verified at three minutes, not sixteen.** A session over fifteen minutes ends on a different callback, and only the shorter one has been observed. Tracked in [the roadmap](ROADMAP.md).
- **Moving the daily reset refills the day.** A reset-time change applies the moment it is saved, and a session count rolls over whenever the allowance day's label changes — in either direction — so setting the reset a few minutes out hands back the day's sessions, which makes the cap advisory rather than enforced. Accepted for the comparison logic it saves, with the guard that would close it named in [the design](design/configurable-daily-reset.md).

## Where things are

- [product-requirements.md](product-requirements.md) — the product source of truth.
- [design/pause-app.md](design/pause-app.md) — the standing architecture, all phases.
- [ROADMAP.md](ROADMAP.md) — the single prioritized what's-next.
- [status.md](status.md) — the resume pointer.
- [research/](research/) — open investigations: the shield sandbox variant, and the Screen Time platform readings.
- [archive/](archive/) — shipped efforts, frozen. Phase 1's folder holds the regression script for the core loop.
