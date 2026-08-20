# Deferred rule changes

A rule cannot be relaxed while it is being enforced. Raising a session count, lengthening a session, or dropping an app from Pause takes effect at the start of the next logical day; every change that tightens applies immediately. The purpose is friction: editing a rule in the moment of wanting to break it should not pay off.

## Terms

- **Effective configuration** — the rules the app is enforcing right now.
- **Pending configuration** — a saved edit that has not reached its start day yet.
- **Logical day** — the period between one configured daily reset and the next, as [the architecture](pause-app.md) defines it. Session allowances renew at its start. Phase 1 resets at midnight; Phase 2 makes the time configurable per weekday.
- **Start day** — the logical day on which a pending configuration begins to apply, identified by the same `CalendarDay` the session counter uses.
- **In force** — whichever of the two applies on a given day; what every reader asks for.
- **Loosening** — an edit that permits more app use than the one it replaces.

## What defers and what does not

An edit is judged whole. If any part of it loosens, the entire edit waits for the start of the next logical day. Splitting one edit so that half applies now and half applies tomorrow would mean storing a difference rather than a document, and the added machinery is not worth the precision.

Loosening, and therefore deferred:

- Raising `sessionsPerDay` on any rule.
- Raising `sessionLengthMinutes` on any rule.
- Removing a target, which is how an app stops being covered.
- Lowering `settings.pauseSeconds`, which shortens the wait before a session starts.
- Moving a daily reset earlier, once Phase 2 makes reset times configurable. An earlier reset ends the current logical day sooner and hands out a fresh allowance, which is the most direct escape the settings can offer.

Tightening or neutral, and therefore immediate:

- Lowering `sessionsPerDay` or `sessionLengthMinutes`.
- Adding a target, which brings a new app under Pause.
- Raising `pauseSeconds`.

Adding a rule and its target together is neutral: an app that was not covered becomes covered, which permits nothing new.

## The model

`configuration.json` currently holds a bare `ConfigurationDocument`. It gains a wrapper:

```
ConfigurationFile
  effective: ConfigurationDocument
  pending:   PendingConfiguration?      // document + startDay: CalendarDay
```

Every reader resolves what applies through one function:

```
inForce(on logicalDay: CalendarDay) -> ConfigurationDocument
    pending where pending.startDay <= logicalDay, otherwise effective
```

`CalendarDay` is already `Codable` and `Comparable`, so the comparison needs nothing new.

The argument is the same logical day the session counter rolls over on, not a civil date read from the clock. Tying both to one value is what makes the design hold: a rule change and the allowance reset it rides in on always happen at the same instant, so a day never contains two different limits. It also survives Phase 2 without revision, because the reset time moves inside that computation rather than here.

### Why the pending document is selected rather than promoted

The obvious design promotes a pending configuration into the effective slot once its start day arrives, and deletes it. That requires a write, and the shield configuration extension cannot write — its sandbox profile refuses every write in the app group container, which is what `docs/research/shield-repair-variant.md` records. A shield rendering after the reset would then have to either write, which fails, or read a configuration it knows to be superseded.

Selecting at read time removes the problem. No reader needs write access, and every reader — app, monitor extension, both shield extensions — computes the same answer from the same file. Collapsing a pending document into the effective slot and clearing it becomes hygiene rather than correctness, done opportunistically the next time the app writes for its own reasons.

The property to hold onto: the file is a description of what applies on any given day, not a description of what applied when it was written.

## Saving an edit

`AppModel` holds and edits the in-force document, never the raw effective one. That single choice keeps the rest honest: the screens show what applies today, and an edit made after a pending change has started builds on that change rather than on the document it superseded.

`AppModel` writes configuration at three points — the picker save, the rule editor save, and rule removal. Each takes the same path:

1. Build the candidate document as it does today.
2. Compare it against the in-force document.
3. If nothing loosens, write it to `effective` and clear any pending document, because an immediate tightening supersedes a scheduled change.
4. If anything loosens, leave `effective` alone and write the candidate to `pending`, with the logical day after the current one as its start day.

Step 3 matters: tightening always wins, so a scheduled loosening cannot survive a later decision to be stricter.

A saved pending configuration replaces any earlier one rather than queueing behind it. One scheduled change at a time is enough, and a queue would let several edits compound into a change nobody chose.

## What the app shows

Saving a deferred edit names what will happen and when, and requires a confirmation — "Instagram goes to 5 sessions tomorrow. Today stays at 3." That confirmation is where the friction lands. The waiting period removes the payoff from editing in the moment; the sentence makes the attempt visible.

The rules list shows any scheduled change against the rule it affects, so a pending edit cannot be forgotten. Cancelling one is allowed: cancelling a loosening leaves the stricter rule in force, which is the direction always permitted, and forbidding it would lock in a change already regretted.

## Testing

The two pieces carrying the behaviour are pure functions over value types, testable without a device:

- `isLoosening(from:to:)` — one test per field in both directions, plus a mixed edit that loosens in one field and tightens in another, which must defer.
- `inForce(on:)` — before, on, and after the start day; and with no pending document at all.

Above those, the save paths in `AppModel` get tests that a loosening edit leaves the effective document untouched, and that a tightening edit clears a pending one.

`ShieldStateReader` and `ShieldReconciler` change only in which document they read, so their existing tests hold with a configuration whose pending document has and has not started.

## Migration

An installed build has a bare `ConfigurationDocument` in `configuration.json`. `ConfigurationStore` decodes the wrapper first and falls back to decoding the bare document, treating it as `effective` with no pending change. The next write persists the new shape. No data is lost and no version field is needed, because the two shapes are distinguishable by decoding.

## Known limits

**The countdown setting is the one field a late edit reaches.** Every per-day rule is safe from timing: a loosening lands at the reset, which is the same instant the used-session count returns to zero, so an edit made late in the day grants nothing that day no matter how few hours remain. Limits and counters move together.

`settings.pauseSeconds` is not per-day and has no reset to ride in on, so shortening it late in the day does take effect that much sooner. Accepted rather than fixed: the exposure is a few seconds of delay before a session starts, and a second timing rule for one field costs more than it protects. A fixed delay applied to everything would be worse, since it would land mid-day and leave a logical day holding two different limits.

**A scheduled removal does not unshield by itself.** Nothing runs at the reset. `ManagedSettingsStore` keeps shielding an app until `ShieldReconciler` next runs, which happens when Pause is opened or a monitor callback fires. Until then an app dropped by a pending edit still meets a shield, and the shield resolves against an in-force document with no target for it, which renders the repair variant.

That combination is wrong twice over — the app should not be shielded, and the copy blames a fault that has not occurred. The mitigation is to reconcile on app activation, which already happens, and to treat a token with no matching target as unmanaged rather than broken:

- [ ] Decide the shield copy for an app that is shielded but no longer covered by a rule. It should read as the app being released rather than as damage.

## Out of scope

Phase 1 has no notion of disabling a rule while keeping it; removal is the only way an app stops being covered. If a disable is added later it is a loosening and belongs in the same comparison.

Moving shared state to SQLite is a separate decision and does not help here. The shield configuration extension cannot read SQLite from its sandbox, so adopting it would require a second copy of this state in plain files for the shield to read — two sources of truth for what applies today, which is precisely the value this design keeps singular.
