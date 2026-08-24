# Scheduled change presentation

How the rules list and the rule editor show that something is scheduled to change, and how one app's scheduled change is cancelled without touching another's.

## Terms

- **Scheduled change** — an edit that does not apply on save. One `ConfigurationDocument` replaces another at the next daily reset.
- **In force** — the document governing the app right now (`ConfigurationFile.effective`, resolved through `inForce(at:)`).
- **Pending** — the document waiting to replace it (`ConfigurationFile.pending`), with the `startDay` it lands on.
- **Unit** — one app's rule and target together, keyed by `ruleID` (`ConfigurationComparison.RuleUnit`).
- **Loosening** — a change that permits more than what is in force. The only kind of change that waits.
- **Marker** — the symbol a row carries to say a loosening is scheduled for it.

## Goal

A pending change lives on the row of the thing it changes, and is cancellable one app at a time.

## Why the presentation changes

The scheduled-change model is document-level: a save produces a whole document, and the difference between two documents is computed as a diff. The rules list is app-level: one row per app, each carrying that app's allowance and its charged sessions.

Showing a document-shaped fact in an app-shaped list forced two compromises, and both are visible:

- The banner reduced every pending change to one sentence — the first change named in full, the rest as a count. A sentence about a document has no row to sit on, so it sat above the list in a section of its own, pairing an app label whose width Pause cannot measure with text that wraps beside it.
- A pending removal decorated its app's row with a second line, a removal phrase, and a button, so one row in the list had four stacked elements where the others had one.

Both surfaces offered a cancel, and both called the same document-wide `cancelScheduledChange()`. A button labelled with one app dropped every other app's pending change too.

## The rule

A pending change lives on the row of the thing it changes. The list says *where*; the editor says *what*, and carries the cancel.

The marker means: **a loosening you asked for starts at the next reset.** Tightenings need no marker because they already applied.

Two symbols carry it, both in the accent tint: `calendar.badge.clock` for an allowance loosening, and `calendar.badge.minus` for an app on its way out. Everything finer than that is detail, and detail is one tap away.

Leaving Pause is not the same kind of event as a longer session, and the list is the surface scanned to see what is about to happen — so the one distinction the list draws is between an app that is changing and an app that is going.

## What defers, and therefore what can be marked

`ConfigurationComparison.isLoosening` decides. A unit loosens when coverage is dropped, when sessions per day or session length rises, or when a target is re-pointed at a different application. Covering an app that nothing covered before is a tightening, so **adding an app applies immediately and never carries a marker**.

Settings are judged as one unit, and only a shorter pause loosens. So:

- An app row carries the marker when that app's unit has a pending change.
- The **Pause duration** row carries it when a shorter pause is pending.
- The **Day reset** row never carries it. A reset-minute change is not tested for loosening, so it applies on save.

`ScheduledChangeWording.changes` still reports an addition, for a document saved by an earlier whole-document router that deferred an entire edit and left an addition waiting. A re-pointed target also reads as a removal plus an addition. Neither is reachable from an ordinary save.

## What the list shows

Every row is the same shape and every row is a link:

```
[app label]  [marker?]  [used/limit]  ›
```

The marker sits between the label and the count, and says which of the two kinds is scheduled. A row for an app on its way out is a link like any other — it keeps its count, because the app is still in force, still shielded, and still spending sessions until the reset.

Nothing in the list is multi-line, and nothing in the list carries a button.

## What the editor shows

The controls read the **in-force** values, because that is what governs the user now. A pending change is an annotation on that, never a substitute for it.

Below the controls, a section names the change in words and carries a cancel scoped to this app alone:

The controls are disabled whenever a change is pending, whichever kind:

- **Allowance loosening** — the section names what the allowance becomes and when, and the button reads *Cancel change*.
- **Removal** — the section says the app leaves Pause at the reset and is shielded as normal until then, and the button reads *Cancel removal*.

Disabling closes a hazard rather than guarding against it. The editor saves a document built from the rules in force, which would write over whatever is scheduled and cancel it silently; that is why a row with a pending removal is not a link today. An editor that cannot save cannot do it.

## Where a pending pause duration is cancelled

The Pause duration row is a stepper, not a link, so it has no detail view to hold the words and the button. Its settings section's footer carries both: the sentence naming the shorter pause and when it starts, and a *Cancel change* button beside it.

**The stepper is disabled while that change is pending**, and cancelling frees it. It commits on each nudge rather than behind a Save, so there is no save to block — locking the control is what the rule amounts to here. One rule covers every row that can carry a marker, apps and settings alike.

This keeps the rule — the change lives where the thing it changes lives — without inventing a screen for one control. The footer is already where that section explains itself.

## Cancelling one app's change

`cancelScheduledChange(ruleID:)` builds a new pending document from the existing one with that single unit reverted to its in-force value — restored if it was being removed, dropped if it was only ever pending, reverted if its allowance was changing. Every other unit is left as pending has it.

Three properties hold it together:

- **Nothing is lost.** The in-force document keeps the full unit for any app whose change is only pending; nothing is purged until its own reset lands. The value to revert to is always still there.
- **The start day is untouched.** It is a property of timing, not of content, so reverting one unit cannot make it ambiguous.
- **An empty pending document is not a state.** When the rebuilt document equals the in-force one, `pending` collapses to `nil`, using the equality check the router already applies (`ConfigurationSaveRouter.swift:63`).

A settings change needs the same treatment under a different key, since settings are one unit with no `ruleID`: `cancelScheduledSettingsChange()` reverts the pending document's settings to the in-force settings, leaving every app's unit alone, and collapses `pending` the same way.

Shield reconciliation, the monitor extension, and `registerDailyReset` consume the resolved document and never read `pending`, so none of them change.

## Editing an app that already has a change pending

**A pending change must be cancelled before the app can be edited again.** While one is scheduled, the editor's controls are disabled and the pending section's button is the only thing to press.

Cancelling reverts the app to the values in force and frees the controls, so superseding a scheduled change is cancel-then-edit rather than edit-over. With 2 in force and 4 pending, changing course means cancelling back to 2 and choosing again.

This makes one rule out of what were two. The spec already disabled the controls under a pending removal, because an editor save builds from the rules in force and would write over a scheduled removal, cancelling it silently. The same hazard exists for a pending allowance change, and the same guard closes it.

It also removes the trap where setting a value back to what is in force appears to undo a scheduled change and does not: the router reads a candidate equal to the in-force unit as having no opinion, so the pending value survives (`ConfigurationSaveRouter.swift:33-45`). An editor that cannot save while a change is pending cannot reach that case.

The router is untouched. The gap recorded in [the overview](../README.md) as *a save states its opinion by rebuilding* stays in the router as a mechanism, but nothing in the interface can reach it any more — it is closed by construction rather than fixed, and the overview should say so rather than claim the inference is gone.

## What is deleted

- `ScheduledChangeNotice` — the banner view.
- `ScheduledChangeSentence`, and `ScheduledChangeWording.sentence(for:starting:)` with its "and N other changes" collapsing. Every change now has its own row, so nothing needs summarising into one line.
- `RulesView.pendingRemovalRow`, and the `removalPhrase` helper that served it.

`ScheduledChangeWording.changes` and `ScheduledChangeWording.phrase` both survive: the diff and the day-naming are still needed, now per app rather than per document.

## Testing

The case nothing covers today is two independent pending changes, one cancelled:

- Two apps each with a pending change; cancelling one leaves the other's intact, with its start day unchanged.
- Cancelling the only pending change collapses `pending` to `nil`.
- Cancelling a pending removal restores the app's unit to what is in force, and the app keeps its charged-session count across the cancel.

Alongside those:

- A rule with a pending change reports one; a rule without reports none. The Pause duration row reports one only for a shorter pause, and the Day reset row never does.
- Cancelling a pending pause duration leaves every app's pending change intact, and cancelling an app's change leaves a pending pause duration intact.
- A pending pause duration disables the Pause duration stepper, and cancelling it frees the stepper at the value in force.

The editor's lock needs pinning both ways:

- A rule with any pending change — allowance or removal — leaves the editor unable to save.
- Cancelling frees the controls, and the values they return to are the ones in force.

The router already supports pending changes coexisting (`ConfigurationSaveRouterTests.swift:105`, `testAScheduledRemovalSurvivesASaveAboutAnotherApp`); what is new is cancelling one of them.

`RulesView` and `RuleEditorView` have no view-snapshot harness, so the marker's presence is pinned on the model's per-rule lookup rather than on the rendered row. Whether the marker reads correctly on the device is a device check.
