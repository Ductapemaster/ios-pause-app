# Deferred rule changes

A rule cannot be relaxed while it is being enforced. Raising a session count, lengthening a session, or dropping an app from Pause takes effect at the start of the next logical day; every change that tightens applies immediately. The purpose is friction: editing a rule in the moment of wanting to break it should not pay off.

## Terms

- **Effective configuration** — the rules the app is enforcing right now.
- **Pending configuration** — a saved edit that has not reached its start day yet.
- **Logical day** — the period between one configured daily reset and the next, as [the architecture](../../design/pause-app.md) defines it. Session allowances renew at its start. Phase 1 resets at midnight; Phase 2 makes the time configurable per weekday.
- **Start day** — the logical day on which a pending configuration begins to apply, identified by the same `CalendarDay` the session counter uses.
- **In force** — whichever configuration applies on a given logical day; what every reader asks for.
- **Loosening** — an edit that permits more app use than the one it replaces.
- **Reset event** — the daily Device Activity callback that fires when a logical day begins.

## What defers and what does not

An edit is judged whole. If any part of it loosens, the entire edit waits for the start of the next logical day. Splitting one edit so that half applies now and half applies tomorrow would mean storing a difference rather than a document, and the added machinery is not worth the precision. [Per-app rule changes](../per-app-rule-changes/design.md) supersedes this: a split by app produces two whole documents rather than a difference, so the objection does not hold and each app is judged on its own.

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

`configuration.json` holds a wrapper around the document:

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

Four places read `configuration.json`, and each takes the in-force document. A reader left on `effective` would apply a scheduled change to what the person sees but not to what they get, or the reverse:

- `AppModel` — the rules screens, and the basis for every edit.
- `ShieldStateReader` — what the shield displays.
- `ShieldActionExtension` — whether a tap grants a session.
- `SessionReconciliationService` — the monitor extension's view during reconciliation.

`ShieldReconciler`, which decides which applications carry a shield, is not a fifth reader: it is handed a document by whichever of those callers is reconciling, so it inherits their answer.

## The reset event

Session counts roll over lazily, the next time something happens to evaluate them, and a deferred change lands the same way on its own: correct in every calculation, but invisible until an unrelated event woke the app.

That is not good enough once a scheduled change can remove an app. `ManagedSettingsStore` would keep shielding an application that no longer has a rule, and the shield would resolve against a document with no target for it — showing damage where the truth is release.

Pause therefore registers one repeating daily activity, `daily-reset`, whose interval begins at the reset time. `MonitorExtension.intervalDidStart` is the entry point.

The callback has to be read by name. A session's own activity begins at the instant the session is granted, and a schedule whose interval is already under way fires `intervalDidStart` immediately, so this callback arrives on every grant as well as at the reset. `SessionMonitorCallbackHandler` parses activity names as `session.<uuid>`; a name that parses is a grant and is discarded, and any other name is the reset.

The reset reconciles under a trigger of its own, `.dailyReset`, rather than reusing app activation. `.appActivation` is the only trigger that promotes a provisional session to active, and a provisional session is one whose launch handoff has not been confirmed — a reset pass reusing that trigger would spend a session on a launch that may never have happened. Device state is legible only through `sysdiagnose` and the unified log besides, so a trigger that said "app activated" when the reset fired would corrupt the one debugging signal there is.

What `.dailyReset` shares with an activation is the shield pass: both are whole-configuration passes, unlike the per-rule expiry callbacks, so both sweep every rule the in-force document names and then apply shields. That pass is the point of the event. A landed removal is already in force — the pending document was selected the moment the day turned over — and the pass is what lets the shields catch up, releasing an application that is no longer a target. Nothing is promoted and nothing is written back to `configuration.json`. Session allowances still roll over lazily, on the next read of a runtime.

The reset activity repeats daily and is registered whenever Pause opens, so it fires on registration too. The reconciliation is therefore idempotent and reads nothing into the callback beyond "reconcile now": it resolves what applies from the moment it runs, which is right whether a day turned over or not.

Missed callbacks are already the architecture's assumption. A phone that is off at the reset misses it, and the reconciliation on app launch repairs the state the next time Pause opens. That fallback is what makes a released-but-still-shielded window rare rather than impossible; it is not a reason to skip the event.

## Saving an edit

`AppModel` holds and edits the in-force document, never the raw effective one. That single choice keeps the rest honest: the screens show what applies today, and an edit made after a pending change has started builds on that change rather than on the document it superseded.

`AppModel` writes configuration at four points — the picker save, the rule editor save, the countdown setting, and rule removal. The countdown belongs on that list because `settings.pauseSeconds` is the one field a shorter value loosens, and nothing else can change it. Each takes the same path:

1. Build the candidate document.
2. Validate it. A pending document is held to the same rules as an effective one, so an invalid document cannot wait in storage and take effect unwatched.
3. Compare it against the in-force document.
4. If nothing loosens, write it to `effective` and clear any pending document, because an immediate tightening supersedes a scheduled change.
5. If anything loosens, leave `effective` alone and write the candidate to `pending`, with the logical day after the current one as its start day.

Step 4 matters: tightening always wins, so a scheduled loosening cannot survive a later decision to be stricter. Cancelling a pending change reaches the same end without the comparison: it writes the in-force document back over `effective` and clears `pending`, and it applies at once because it leaves the stricter rule standing.

A saved pending configuration replaces any earlier one rather than queueing behind it. One scheduled change at a time is enough, and a queue would let several edits compound into a change nobody chose.

### Removal defers its cleanup too

A removal is a loosening like any other, so it writes the pending document and touches nothing else. Until the reset the rule is still in force: still counting sessions, still shielding, still monitored, still selected in the picker. Deleting its runtime at the moment of the edit would leave an app that is shielded with no session data, which resolves as damage.

The reset releases the application, and the runtime file goes with the orphan cleanup that runs when Pause opens, which keeps only the rules the in-force document names. A runtime outliving its rule by that much costs nothing: the shield set is built from the document's targets, so a runtime with no target is never read.

## What the app shows

Saving a deferred edit shows a notice that names the change and when it takes effect, with a button to cancel it: "Instagram is being removed tomorrow.", "Instagram changes to 5 sessions tomorrow.", "The pause changes to 20 seconds tomorrow." Where several things are scheduled at once the notice names the first and counts the rest — "Instagram is being removed, and 2 other changes start tomorrow." — which stays one sentence at three or four changes where naming each would not. A removal is named first, being the change worth seeing go.

Naming it is what makes the single pending slot safe to look at. A later save replaces a scheduled change rather than stacking onto it, so a save made after a removal was scheduled supersedes it; a notice that only said a change was scheduled would let the removal go without a trace.

The app in that sentence has no name Pause can read. `Label(token)` renders Apple's own name and icon as a view, and there is no string behind it, so the sentence is built as the token plus the words that follow it and the label is drawn where the subject goes.

The notice sits at the top of the rules list and at the top of the rule editor, so a scheduled change cannot be forgotten before it lands. A deferred save leaves the editor open under the notice, where the wait is visible at the place it was chosen; a save that applied at once closes it.

A removed app keeps its row in the rules list until the removal lands. The row is faded, marked with the day the app goes, and carries its own cancel action. It is not a link to the editor: the editor saves a document built from the rules in force, which would write over the scheduled removal and cancel it silently. Once the removal lands the in-force document no longer names the rule, so the row goes with no flag to clear.

## Testing

The two pieces carrying the behaviour are pure functions over value types, testable without a device:

- `isLoosening(from:to:)` — one test per field in both directions; a rule added and a rule removed; a target re-pointed at another application; and a mixed edit that loosens one field while tightening another, which must defer.
- `inForce(on:)` — before, on, and after the start day, and with no pending document at all.

Above those: the save paths leave `effective` untouched for a loosening edit and clear `pending` for a tightening one; a deferred removal leaves the runtime file in place; and the reset-event reconciliation releases the application once the removal is in force.

`SessionMonitorCallbackHandler` is tested on both halves of the name check: the reset activity reconciles, and a session activity starting does not.

## Migration

An installed build from before deferred changes has a bare `ConfigurationDocument` in `configuration.json`. `ConfigurationStore` reads the file's top-level keys and picks the shape from them: a file carrying `effective` is a wrapper, and anything else is a bare document, read as `effective` with no pending change. The next write persists the wrapper. No data is lost and no version field is needed, because the key tells the two shapes apart.

The choice is made on the key rather than on a failed decode. Falling back whenever the wrapper failed to decode would hand a damaged wrapper to a legacy read of the same bytes, and what surfaced would be whatever the older shape made of them; a file carrying `effective` is read as one, and its damage is reported as its own.

## Known limits and non-goals

**Device time is taken as given.** The logical day is computed from the device clock and calendar. Moving the clock forward, or crossing time zones, moves the boundary with it and can bring a pending change forward. Not defended against, deliberately: tracking real elapsed time is not worth its cost for a case that arises in travel rather than in use.

**Deleting Pause defeats all of this.** Reinstalling gives a clean slate with no rules and no pending changes. Nothing in this design prevents it, and nothing can.

**A second save replaces a scheduled change rather than stacking onto it.** There is one pending slot, and every candidate document is built from the rules in force rather than from the pending one, so a save made while a change is scheduled writes over it. Cancelling is the only way back to the rules in force, and there is no way to hold two changes for the same reset. [Per-app rule changes](../per-app-rule-changes/design.md) narrows this to the app a save states an opinion about.

**A picker save that both adds and drops apps waits as a whole.** The edit is judged whole, so an app added in the same trip through the picker as one dropped starts being covered at the reset rather than at once. [Per-app rule changes](../per-app-rule-changes/design.md) replaces the whole-document rule with one judgment per app.

**The countdown setting is the one field a late edit reaches.** Every per-day rule is safe from timing: a loosening lands at the reset, the same instant the used-session count returns to zero, so an edit made late in the day grants nothing that day. `settings.pauseSeconds` is not per-day and has no reset to ride in on, so shortening it late does take effect that much sooner. Accepted: the exposure is a few seconds of delay before a session starts, and a second timing rule for one field costs more than it protects.

## Out of scope

Phase 1 has no notion of disabling a rule while keeping it; removal is the only way an app stops being covered. If a disable is added later it is a loosening and belongs in the same comparison.

Moving shared state to SQLite is a separate decision and does not help here. The shield configuration extension cannot read SQLite from its sandbox, so adopting it would require a second copy of this state in plain files for the shield to read — two sources of truth for what applies today, which is precisely what this design keeps singular.
