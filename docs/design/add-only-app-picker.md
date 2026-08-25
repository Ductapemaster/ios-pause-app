# The add-only app picker

How apps enter Pause, and why leaving it happens somewhere else.

## Terms

- **Picker** — Apple's `FamilyActivityPicker`, presented in `AppPickerSheet` so that choosing apps and saving them are separate acts.
- **Selection** — the set of application tokens the picker hands back on save (`FamilyActivitySelection`).
- **Covered** — an app Pause holds a rule and a target for, keyed by `ruleID`.
- **Loosening** — a change that permits more than what is in force. It does not apply on save; it waits for the next daily reset.

## Goal

The picker adds apps. An app leaves Pause from its own row, and from nowhere else.

## Why the picker stops removing

The picker opened seeded with every covered app, so its selection was the complete set of what Pause covers. Saving it replaced that set: an app left un-ticked was dropped, and dropping coverage is a loosening, so the removal was deferred to the next reset.

Reading the selection as a whole set has two costs, and the second is a fault:

- Removal lives in two places. An app can be dropped from the picker or removed in its own editor, and the two produce the same deferred removal by different routes.
- **A re-tick does nothing, silently.** With an app already pending removal, ticking it again in the picker produces a candidate unit equal to the unit in force, which `ConfigurationSaveRouter` reads as stating no opinion (`ConfigurationSaveRouter.swift:33-45`). The scheduled removal survives, the app still leaves at the reset, and the interface gives no sign that the re-add was ignored.

The second is the interface reaching the router gap recorded in [the overview](../README.md) as *a save states its opinion by rebuilding*. Locking a control cannot close it here, because the picker is Apple's view and does not take a per-row disabled state.

## The rule

The picker opens with nothing selected, and its selection is a set of additions rather than a set of members. Apps already covered are retained regardless of what the picker returns.

That makes the fault unreachable rather than guarded against: an app pending removal cannot be re-ticked into a contradiction, because being covered is no longer something the picker expresses an opinion about.

## What the save does

`applyPickerSelection` keeps every existing rule and target, and creates a rule for each token in the selection that is not already covered. It computes no removals, and there is no path by which a picker save can drop an app.

A token in the selection that is already covered is named rather than ignored: the allowance step reports that the app is already in Pause, and configures only the apps genuinely being added. The count of apps configured then matches the count the picker returned, so a pick that quietly did nothing is not left to be inferred from a shorter list of screens.

## Removal

`Remove app` in the rule editor is the only route out of Pause. It is unchanged: the removal is a loosening, so it waits for the next reset, the app stays shielded and keeps spending sessions until then, and its row carries the removal marker in the meantime. Cancelling it is the editor's `Cancel removal`.

## What re-detecting a launch route costs

Retained targets no longer have their launch route refreshed on a picker save. The old save rebuilt every retained target and took a freshly detected route from the picker's `Application` values when one was available; with existing apps absent from the selection, there is nothing to re-detect them from.

A launch route is therefore detected when an app is added and kept thereafter. Re-detection needs its own trigger if a route is ever found to go stale — the picker was doing it as a side effect of rebuilding, not because a save was the right moment for it.

## Testing

What the model does is pinned directly:

- A picker save that adds an app leaves every existing rule, target and runtime untouched, including an app with a scheduled removal (`testAPickerSaveThatAddsAnAppLeavesEveryExistingRuleTargetAndRuntimeUntouched`).
- A selection that omits a covered app still leaves it covered (`testAPickerSaveCannotDropAnAppOmittedFromTheSelection`).
- A save that only adds still reconciles shields, since an app covered today needs its shield now (`testAPickerSaveThatOnlyAddsStillReconcilesShields`).
- The split between added and already-covered tokens is pinned both ways (`testClassifyingAPickerSelectionNamesAlreadyCoveredTokensSeparately`, `testClassifyingAPickerSelectionOfOnlyAlreadyCoveredTokensAddsNothing`).

Nothing pins that a selection of only already-covered apps writes nothing at all. The decision lives in `NewAppSetupSheet.advance()`, which returns before calling `onComplete` when no app is being added, and in `RulesView.savePickerSelection`, which routes to the sheet rather than committing. Neither is reachable from a test: `RulesView` and `NewAppSetupSheet` have no view harness, and the decision is entangled with `@State`. Pinning it means extracting the step-advance decision into a free function. That is a gap.
