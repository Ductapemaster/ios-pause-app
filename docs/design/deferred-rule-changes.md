# Deferred rule changes

A rule cannot be relaxed while it is being enforced. Raising a session count, lengthening a session, or dropping an app from Pause takes effect at the start of the next logical day; every change that tightens applies immediately. The purpose is friction: editing a rule in the moment of wanting to break it should not pay off.

## Terms

- **Effective configuration** — the rules the app is enforcing right now.
- **Pending configuration** — a saved edit that has not reached its start day yet.
- **Logical day** — the period between one configured daily reset and the next, as [the architecture](pause-app.md) defines it. Session allowances renew at its start. Phase 1 resets at midnight; Phase 2 makes the time configurable per weekday.
- **Start day** — the logical day on which a pending configuration begins to apply, identified by the same `CalendarDay` the session counter uses.
- **In force** — whichever configuration applies on a given logical day; what every reader asks for.
- **Loosening** — an edit that permits more app use than the one it replaces.
- **Reset event** — the daily Device Activity callback that fires when a logical day begins.

## What defers and what does not

An edit is judged whole. If any part of it loosens, the entire edit waits for the start of the next logical day. Splitting one edit so that half applies now and half applies tomorrow would mean storing a difference rather than a document, and the added machinery is not worth the precision.

Rules are paired between the two documents by `AppRule.id`, and targets by `RuleTarget.ruleID`. A rule present in one document and absent from the other is not a field change; it is a rule added or removed, judged as below.

Loosening, and therefore deferred:

- Raising `sessionsPerDay` on a paired rule.
- Raising `sessionLengthMinutes` on a paired rule.
- Removing a target, which is how an app stops being covered.
- Pointing an existing target at a different `applicationToken`, which drops coverage of the application it named before.
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

The argument is the same logical day the session counter rolls over on, not a civil date read from the clock. Tying both to one value is what makes the design hold: a rule change and the allowance reset it arrives with are the same instant, so a day never contains two different limits. It also survives Phase 2 without revision, because the reset time moves inside that computation rather than here.

### Why the pending document is selected rather than promoted

The obvious design promotes a pending configuration into the effective slot once its start day arrives, and deletes it. That requires a write, and the shield configuration extension cannot write — its sandbox profile refuses every write in the app group container, which is what `docs/research/shield-repair-variant.md` records. A shield rendering after the reset would then have to either write, which fails, or read a configuration it knows to be superseded.

Selecting at read time removes the problem. No reader needs write access, and every reader computes the same answer from the same file.

The property to hold onto: the file describes what applies on any given day, not what applied when it was written.

### Every read site

All five configuration readers take the in-force document. A reader left on `effective` would apply a scheduled change to what the person sees but not to what they get, or the reverse:

- `AppModel` — the rules screens, and the basis for every edit.
- `ShieldStateReader` — what the shield displays.
- `ShieldActionExtension` — whether a tap grants a session.
- `ShieldReconciler` — which applications carry a shield.
- `SessionReconciliationService` — the monitor extension's view during reconciliation.

## The reset event

Nothing in the app currently runs when a logical day turns over. Session counts roll over lazily, the next time something happens to evaluate them. A deferred change would land the same way: correct in every calculation, but invisible until an unrelated event woke the app.

That is not good enough once a scheduled change can remove an app. `ManagedSettingsStore` would keep shielding an application that no longer has a rule, and the shield would resolve against a document with no target for it — showing damage where the truth is release.

Pause therefore registers one repeating daily activity whose interval begins at the reset time. `MonitorExtension.intervalDidStart` is empty today and becomes the entry point: it runs the same reconciliation every other callback already triggers. `SessionMonitorCallbackHandler` parses activity names as `session.<uuid>`, so it gains a branch routing a name it does not recognise to a plain reconcile rather than discarding it.

This fixes a category rather than a case. At the reset the monitor applies the pending configuration's consequences: the shield set matches the rules now in force, a removed application is released, and the session counter is reset where it can be seen. It costs one registration and one branch, because the handler already treats every callback as a prompt to reconcile rather than as proof of a particular event.

Missed callbacks are already the architecture's assumption. A phone that is off at the reset misses it, and the reconciliation on app launch repairs the state the next time Pause opens. That fallback is what makes a released-but-still-shielded window rare rather than impossible; it is not a reason to skip the event.

## Saving an edit

`AppModel` holds and edits the in-force document, never the raw effective one. That single choice keeps the rest honest: the screens show what applies today, and an edit made after a pending change has started builds on that change rather than on the document it superseded.

`AppModel` writes configuration at three points — the picker save, the rule editor save, and rule removal. Each takes the same path:

1. Build the candidate document as it does today.
2. Validate it, exactly as a direct save validates today. A pending document is held to the same rules as an effective one, so an invalid document cannot wait in storage and take effect unwatched.
3. Compare it against the in-force document.
4. If nothing loosens, write it to `effective` and clear any pending document, because an immediate tightening supersedes a scheduled change.
5. If anything loosens, leave `effective` alone and write the candidate to `pending`, with the logical day after the current one as its start day.

Step 4 matters: tightening always wins, so a scheduled loosening cannot survive a later decision to be stricter. Cancelling a pending change is the same operation — it writes the in-force document back over `effective` and clears `pending`, and it applies at once because it leaves the stricter rule standing.

A saved pending configuration replaces any earlier one rather than queueing behind it. One scheduled change at a time is enough, and a queue would let several edits compound into a change nobody chose.

### Removal defers its cleanup too

Removing an app today runs `RuleRemovalCoordinator`, which stages the rule's runtime file and deletes it. A deferred removal must not do that: the rule is still in force, still counting sessions, and still shielding. Deleting its runtime would leave an app that is shielded with no session data, which resolves as damage.

So a deferred removal writes only the pending document and touches nothing else. The runtime file is deleted during the reconciliation that follows the reset event, once the removal is in force. Cleanup rides the event rather than the edit.

## What the app shows

Saving a deferred edit shows a notice that a change is scheduled and when it takes effect, with a button to cancel it. It does not restate what changed. The friction is the wait and the fact of having scheduled something, not a recitation of the fields.

The rules list carries the same notice against the rule it affects, so a pending edit cannot be forgotten before it lands.

## Testing

The two pieces carrying the behaviour are pure functions over value types, testable without a device:

- `isLoosening(from:to:)` — one test per field in both directions; a rule added and a rule removed; a target re-pointed at another application; and a mixed edit that loosens one field while tightening another, which must defer.
- `inForce(on:)` — before, on, and after the start day, and with no pending document at all.

Above those: the save paths leave `effective` untouched for a loosening edit and clear `pending` for a tightening one; a deferred removal leaves the runtime file in place; and the reset-event reconciliation deletes it once the removal is in force.

`SessionMonitorCallbackHandler` gains tests that an unrecognised activity name reconciles rather than being discarded.

## Migration

An installed build has a bare `ConfigurationDocument` in `configuration.json`. `ConfigurationStore` decodes the wrapper first and falls back to decoding the bare document, treating it as `effective` with no pending change. The next write persists the new shape. No data is lost and no version field is needed, because the two shapes are distinguishable by decoding.

## Known limits and non-goals

**Device time is taken as given.** The logical day is computed from the device clock and calendar. Moving the clock forward, or crossing time zones, moves the boundary with it and can bring a pending change forward. Not defended against, deliberately: tracking real elapsed time is not worth its cost for a case that arises in travel rather than in use.

**Deleting Pause defeats all of this.** Reinstalling gives a clean slate with no rules and no pending changes. Nothing in this design prevents it, and nothing can.

**The countdown setting is the one field a late edit reaches.** Every per-day rule is safe from timing: a loosening lands at the reset, the same instant the used-session count returns to zero, so an edit made late in the day grants nothing that day. `settings.pauseSeconds` is not per-day and has no reset to ride in on, so shortening it late does take effect that much sooner. Accepted: the exposure is a few seconds of delay before a session starts, and a second timing rule for one field costs more than it protects.

## Out of scope

Phase 1 has no notion of disabling a rule while keeping it; removal is the only way an app stops being covered. If a disable is added later it is a loosening and belongs in the same comparison.

Moving shared state to SQLite is a separate decision and does not help here. The shield configuration extension cannot read SQLite from its sandbox, so adopting it would require a second copy of this state in plain files for the shield to read — two sources of truth for what applies today, which is precisely what this design keeps singular.
