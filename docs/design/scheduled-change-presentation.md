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

That is the whole vocabulary — one symbol, `calendar.badge.clock`, in the accent tint. The kind of change is detail, and detail is one tap away.

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

The marker sits between the label and the count. A row for an app on its way out is a link like any other — it keeps its count, because the app is still in force, still shielded, and still spending sessions until the reset.

Nothing in the list is multi-line, and nothing in the list carries a button.

## What the editor shows

The controls read the **in-force** values, because that is what governs the user now. A pending change is an annotation on that, never a substitute for it.

Below the controls, a section names the change in words and carries a cancel scoped to this app alone:

- **Allowance loosening** — the controls stay live. The section names what the allowance becomes and when, and the button reads *Cancel change*.
- **Removal** — the controls are disabled. The section says the app leaves Pause at the reset and is shielded as normal until then, and the button reads *Cancel removal*.

Disabling the controls under a pending removal also closes a hazard rather than guarding against it. The editor saves a document built from the rules in force, which would write over a scheduled removal and cancel it silently; that is why the row is not a link today. An editor that cannot save cannot do it.

## Where a pending pause duration is cancelled

The Pause duration row is a stepper, not a link, so it has no detail view to hold the words and the button. Its settings section's footer carries both: the sentence naming the shorter pause and when it starts, and a *Cancel change* button beside it.

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

A new edit supersedes the old one. With 2 sessions in force and 4 pending, the stepper reads 2; nudging it to 3 makes 3 the pending value.

Nudging up and back down to 2 leaves the pending 4 standing, because the router acts on a candidate that differs from what is in force, and a candidate equal to it is read as having no opinion — so the unit keeps whatever was already scheduled for it (`ConfigurationSaveRouter.swift:33-45`).

This is the router's existing behaviour. Showing in-force values in the controls is what makes it observable.

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
- A pending removal leaves the editor unable to save.
- Cancelling a pending pause duration leaves every app's pending change intact, and cancelling an app's change leaves a pending pause duration intact.

The router already supports pending changes coexisting (`ConfigurationSaveRouterTests.swift:105`, `testAScheduledRemovalSurvivesASaveAboutAnotherApp`); what is new is cancelling one of them.

`RulesView` and `RuleEditorView` have no view-snapshot harness, so the marker's presence is pinned on the model's per-rule lookup rather than on the rendered row. Whether the marker reads correctly on the device is a device check.
