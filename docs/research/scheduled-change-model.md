# Scheduled-change model: per-app cancel investigation

Read-only investigation. Branch `feat/session-usage-display`. All line numbers verified against the working tree at investigation time.

## Terms

- **Effective document** — the rules in force today (`ConfigurationFile.effective`).
- **Pending document** — the whole replacement document scheduled for the next reset (`ConfigurationFile.pending.document`).
- **Unit** — one rule + the target naming its app (`ConfigurationComparison.RuleUnit`), keyed by `ruleID`.
- **Router** — `ConfigurationSaveRouter`, which splits an incoming candidate document into what applies now and what waits.

## 1. How a scheduled change is created

Every write to configuration goes through one path: `AppModel.persist(_:now:)` (`Sources/Pause/AppModel.swift:923-938`), which calls `ConfigurationSaveRouter.route(candidate:into:now:)` (`Sources/Shared/ConfigurationSaveRouter.swift:13-72`) and saves whatever it returns. There is no direct-write path that bypasses the router.

Callers that build a candidate document and call `persist`:
- `applyPickerSelection()` — app add/remove/re-point (`Sources/Pause/AppModel.swift:435-533`).
- `updateRule(id:sessionsPerDay:sessionLengthMinutes:)` — the rule editor save (`AppModel.swift:535-568`).
- `updatePauseSeconds(_:)` (`AppModel.swift:570-590`) and `setResetMinuteOfDay(_:)` (`AppModel.swift:592-621`) — settings edits.
- `removeRule(id:)` — same router path, called from elsewhere in the rule editor flow (`AppModel.swift:643-667`).

**What decides immediate vs. scheduled is the router, not the caller, and it decides per unit, not per save.** `ConfigurationSaveRouter.route` (lines 13-72) computes, for every rule ID present in in-force/candidate/scheduled, a "target" unit (what the candidate says, or what was already scheduled if the candidate is silent about that unit), then applies `ConfigurationComparison.isLoosening(from:to:)` (`Sources/Shared/ConfigurationComparison.swift:33-48`) per unit: if the target loosens relative to what's in force, the *old* (in-force) unit goes into the immediate document and the target goes into the scheduled document; otherwise the target goes into both. Settings (`pauseSeconds`, `resetMinuteOfDay`) are judged as one unit the same way (`ConfigurationSaveRouter.swift:48-57`; loosening test at `ConfigurationComparison.swift:50-52`, only `pauseSeconds` — a reset-time change is judged as *not* loosening on its own, so a bare reset edit applies immediately, confirming `docs/design/configurable-daily-reset.md`'s "Applying a change" section, line 41-47 there).

A "loosening" is: dropped coverage (app removed), more sessions/day, longer sessions, or a target re-pointed at a different app (`ConfigurationComparison.isLoosening(from:to:)`, lines 33-48); for settings, a shorter pause (`ConfigurationComparison.swift:50-52`). Anything else (tightening, addition, unrelated apps) applies at once.

The router always rebuilds the *entire* scheduled document from scratch out of per-unit decisions (`scheduledResultUnits`, `document(settings:units:)`, lines 100-109) — there is no notion of "add one change to the existing pending document." A save that touches app A while app B already has a scheduled removal preserves B's scheduled state only because B's unit is silent in the candidate and the router falls back to `scheduledUnits[ruleID]` (line 36). This is exactly what lets independent pending changes coexist today — confirmed by `testAScheduledRemovalSurvivesASaveAboutAnotherApp` and `testAScheduledAllowanceSurvivesASaveAboutAnotherApp` (`Tests/SharedTests/ConfigurationSaveRouterTests.swift:105-148`).

## 2. Storage and read shape

`ConfigurationFile` (`Sources/Shared/ConfigurationFile.swift:22-74`):
```swift
public struct ConfigurationFile {
    public var effective: ConfigurationDocument
    public var pending: PendingConfiguration?   // { document: ConfigurationDocument, startDay: CalendarDay }
}
```
There is no third slot and no per-app pending list — `pending` is one optional whole-document replacement plus one `startDay` for the whole thing (`PendingConfiguration`, `ConfigurationFile.swift:4-13`).

`inForce(on:)` / `inForce(at:)` (lines 31-56): if `pending == nil` or `pending.startDay > logicalDay`, return `effective`; otherwise return `pending.document` in full — an all-or-nothing swap, never a merge.

`logicalDay(at:)` (lines 46-52) always resolves from `effective.settings.resetMinuteOfDay`, never from the pending document's settings, by design (comment there, and confirmed in `docs/design/configurable-daily-reset.md` "Which reset time defines the day", lines 29-35 — doc and code agree). `nextLogicalDay(after:)` (lines 58-73) is likewise always resolved off `effective`'s reset, and is where a newly-created pending's `startDay` comes from (`ConfigurationSaveRouter.swift:69`, using `routed.nextLogicalDay`, i.e. the *new* file's effective reset, not the old one — relevant if a reset-time change and a loosening are saved together).

`ConfigurationStore.save` (`Sources/Shared/ConfigurationStore.swift:27-32`) validates both `effective` and `pending?.document` independently via `ConfigurationDocument.validate()` (`Sources/Shared/ConfigurationDocument.swift:37-58`), which just checks 1:1 rule/target correspondence — it does not cross-validate `effective` against `pending`.

## 3. What `cancelScheduledChange()` does today

`AppModel.cancelScheduledChange(now:)` (`Sources/Pause/AppModel.swift:624-641`):
```swift
let kept = file.inForce(at: now)          // whichever document currently governs
let cleared = ConfigurationFile(effective: kept, pending: nil)
try configurationStore.save(file: cleared)
```
It **discards the entire pending document**, unconditionally, and writes `effective = kept` (today's in-force document, unchanged) with `pending = nil`. There is no per-app targeting; it clears the whole scheduled change regardless of what caused it. This confirms the report's premise: a change scheduled by a different edit than the one the user is looking at (e.g. one app's removal, another app's allowance loosening, both queued at once by unrelated saves through the router's per-unit fallback) is cancelled *in its entirety* — the user pressing "Cancel removal" on app A's row (`RulesView.swift:132-134`) or "Cancel change" on the banner (`ScheduledChangeNotice.swift:170-172`) both call this same document-wide method, wiping app B's pending allowance change too. Pinned by `testCancellingAScheduledChangeLeavesTodaysRuleInForce` (`Tests/PauseAppTests/AppModelFlowTests.swift:275-294`), which only exercises the single-change case and does not test the multi-change scenario.

## 4. Can a scheduled document be rebuilt minus one app? (the crux)

**Identity.** A rule and its target are keyed by `ruleID` (`RuleTarget.ruleID`, `ConfigurationDocument.swift:15`; `ConfigurationComparison.units(of:)` keys its dictionary by `target.ruleID`, `ConfigurationComparison.swift:25-31`). The `ApplicationToken` is carried inside the target (`RuleTarget.applicationToken`) but is not itself the identity key used for lookups anywhere in this pipeline — `ruleID` is. This matters: a re-point (same `ruleID`, different token) is legal and is read as removal-of-old-token + addition-of-new-token in the wording layer (`ScheduledChangeWording.changes`, `ScheduledChangeNotice.swift:70-76`), but the underlying document model still tracks it as *one* unit under one `ruleID`.

**Reconstructability.** For each of the three cases a per-app cancel would need to handle:

- **Restoring a removed rule** (app dropped from the pending document): the in-force document still carries the full unit — `rule` and `target` — for that `ruleID`, because a removal never touches the effective document until the reset lands (`removeRule`, `AppModel.swift:643-667`; `applyPickerSelection`, `AppModel.swift:525-533`). So `ConfigurationComparison.units(of: inForce)[ruleID]` has everything needed to rebuild the unit exactly as it was. **Not lossy for this case**, provided the reconstruction takes the unit from `inForce`, not from some diff — which is straightforward since the router already computes exactly this (`inForceUnit` at `ConfigurationSaveRouter.swift:30`).

- **Dropping an added app** (app present only in `pending`, not `inForce`): trivial — just omit that `ruleID` from the rebuilt scheduled document's unit list. No data needed beyond what's already in the pending document being edited.

- **Reverting an allowance edit** (`sessionsPerDay`/`sessionLengthMinutes` changed in `pending` vs. `inForce` for the same `ruleID`): same as the removal case — take the unit from `inForce` for that one `ruleID`, keep every other unit's pending value. Not lossy, same reasoning.

**So the reconstruction itself is not lossy at the data level** — the in-force document is always a strict superset of what's needed to restore any one app's prior state, because nothing is ever purged from `effective` until its own reset lands. The rebuild is mechanically: for the one target `ruleID`, replace whatever unit is in the current pending document with `inForceUnits[ruleID]` (or drop it if `inForceUnits[ruleID]` is nil, i.e. it was a pure addition), leave every other unit as `pending` already has it, and settings untouched. This is structurally identical to what `ConfigurationSaveRouter.route` already does per-unit — a per-app cancel is really "route a synthetic candidate that says 'this one unit reverts to in-force, all other units unchanged.'"

**What is NOT handled by the existing router and would need new logic:**
- The router's per-unit split is driven by comparing a *candidate* document against *in-force* and re-deriving loosening/tightening. A per-app cancel isn't a save — the "candidate" is implicit ("what's already scheduled, minus this app's change"), so a cancel operation needs its own function rather than routing through `ConfigurationSaveRouter.route`, or it needs to synthesize a full candidate document (in-force document with that one unit's *later* pending values still applied for a shortcut? No — actually the natural synthetic candidate is: take the *current pending document*, and for the cancelled `ruleID` swap in the in-force unit) and feed it back through a router-like pass. Either way this is new code, not reuse of `route` as-is, because `route`'s "loosening → defer" policy no longer applies (a cancel of one unit is inherently a tightening for that unit and should apply/stay in the schedule as revert, not re-trigger deferral logic).
- **Settings never get this treatment.** `GlobalSettings` (pause duration, reset minute) is one unit for the whole document (`ConfigurationSaveRouter.swift:48-57`) — there is no "settings pending row" in the redesigned per-row UI as described (the report scope is "the thing it changes" — an app row). A pending pause-duration or reset-minute change has no natural row to live on and no described cancel target. **This is a gap the redesign needs to resolve explicitly** — either give settings changes their own cancellable affordance or decide they stay document-wide-cancel-only.
- **Ambiguity in "what does cancelling one unit mean when `startDay` differs conceptually per app.** Today there's exactly one `startDay` for the whole pending document (`PendingConfiguration.startDay`). If per-app cancel leaves a document with fewer differences from in-force, the single `startDay` is still correct (it's just "next reset"), so this isn't actually a problem — `startDay` is a property of *when* pending applies, not *what* it contains, and stays valid no matter how many units remain in the pending document. Confirmed no ambiguity here.

## 5. What happens when the last pending change is cancelled

**"A scheduled document identical to the in-force document" is not a state the system currently produces or expects to persist, and existing code actively collapses toward `pending = nil` instead.**

Evidence:
- `ConfigurationSaveRouter.route` explicitly checks for this: `guard scheduledResult != immediate else { return routed }` (`ConfigurationSaveRouter.swift:63`) — if the router's own computed scheduled document turns out equal to the immediate document, it returns with `pending == nil`, never writing an equal-but-present pending. This is the one existing precedent for "the last change cancelled out" and it clears `pending` entirely rather than leaving a no-op pending document.
- `cancelScheduledChange()` itself always sets `pending: nil` (`AppModel.swift:632`), never conditionally.
- `AppModel.scheduledChanges` (`AppModel.swift:684-687`) and `ruleIDsPendingRemoval` (`AppModel.swift:693-697`) both guard on `configurationFile?.pending` being non-nil and return `[]`/`[]` otherwise — an *equal* non-nil pending would not be filtered out by these accessors; `ScheduledChangeWording.changes(from:to:)` given two equal documents does correctly compute an empty list (confirmed by `testAnIdenticalDocumentChangesNothing`, `Tests/PauseAppTests/ScheduledChangeWordingTests.swift:60`), so the banner/notice would silently render nothing even with a non-nil-but-equal pending. But `RulesView.pendingChangeStartDay`-gated banner section (`RulesView.swift:54-58`) and the picker's diff logic (`AppModel.swift:521-533`) rely on `configurationFile.pending != nil` as their signal for "something is scheduled" in other places (e.g., `applyPickerSelection`'s in-force-mirroring picker selection logic reads `configuration.targets`, which is `inForce`, so it wouldn't be confused by an equal pending — but `pendingChangeStartDay` would still be non-nil, meaning the *row would still render faded/pending* even though nothing differs). **So leaving an equal-but-present pending document would produce a UI inconsistency**: `pendingChangeStartDay` non-nil (drives banner section visibility) while `scheduledChanges`/`ruleIDsPendingRemoval` report empty — banner section appears with a "no changes" sentence, which is a real defect risk if per-app cancel does the lazy thing (rebuild-and-leave-present).

**What the rest of the system assumes:**
- `ShieldReconciler.reconcile` and `unshield`/`forceShield` all take an already-resolved `ConfigurationDocument` (`Sources/Shared/ShieldReconciler.swift:59-70`, `128-138`, `144-152`) — they never see `ConfigurationFile.pending` directly. Callers (`AppModel.reconcileShieldsIfAuthorized`, `AppModel.swift:986-1005`; `AppModel.reconcileSessionsIfAuthorized`, `AppModel.swift:1027-1079`) pass `configuration`, the already-`inForce`-resolved document. **The shield/monitor path is entirely indifferent to whether pending is nil, present-and-different, or present-and-equal** — it only ever reads the resolved document. So an equal-but-present pending is harmless to shield reconciliation and the monitor extension (`Sources/MonitorExtension/MonitorExtension.swift`), which never touches `ConfigurationFile` directly either — it goes through `SessionReconciliationService`.
- `registerDailyReset()` (`AppModel.swift:1014-1025`) reads `configuration.settings.resetMinuteOfDay` — again the resolved in-force document, indifferent to pending's presence.
- **So the only real constraint against leaving an equal pending document is the UI-affordance inconsistency above (banner shows with nothing to say), not any storage or reconciliation invariant.** The cleanest, least-surprising choice for a per-app cancel is: after rebuilding the scheduled document minus one unit, compare it to the in-force document, and if equal, clear `pending` to `nil` exactly as the router already does at `ConfigurationSaveRouter.swift:63`. This reuses an established pattern rather than inventing a new "empty but present" state.

## 6. Existing test coverage (what a redesign must not break)

**Router / per-unit scheduling** — `Tests/SharedTests/ConfigurationSaveRouterTests.swift`:
- `testATighteningEditAppliesImmediately` (9-25), `testALooseningEditIsScheduledForTheNextLogicalDay` (27-44), `testATighteningEditClearsAScheduledChange` (46-65), `testASecondLooseningEditReplacesTheFirstRatherThanQueueing` (67-86), `testAnAddedAppIsCoveredTodayWhileADroppedOneWaits` (88-103).
- **Multi-app independence, directly relevant to per-app cancel**: `testAScheduledRemovalSurvivesASaveAboutAnotherApp` (105-125) and `testAScheduledAllowanceSurvivesASaveAboutAnotherApp` (127-148) — these pin that an unrelated save doesn't disturb another app's already-scheduled change. `testASaveAboutAnAppReplacesWhatWasScheduledForIt` (150-169) pins that a save about the *same* app supersedes its own prior schedule.
- `testASaveThatDefersNothingLeavesTheCandidateAsEffective` (171+, truncated in read).

**`ConfigurationFile.inForce`/day resolution** — `Tests/SharedTests/ConfigurationFileTests.swift`: `testTheEffectiveDocumentAppliesWhenNothingIsPending` (9), `testThePendingDocumentAppliesOnItsStartDay` (27), `testThePendingDocumentStillAppliesAfterItsStartDay` (39), `testTheEffectiveResetDefinesTheDayThatSelectsThePending` (55), `testThePendingArrivesOnceTheEffectiveResetHasPassed` (92).

**Document diff / wording** — `Tests/PauseAppTests/ScheduledChangeWordingTests.swift`: `testDroppingAnAppReadsAsARemoval` (14), `testAddingAnAppReadsAsAnAddition` (24), `testAnAllowanceNamesOnlyTheFieldThatMoved` (34), `testAPauseDurationChangeIsItsOwnChange` (50), `testAnIdenticalDocumentChangesNothing` (60) — **directly relevant**: pins that an equal before/after produces an empty change list, which is the behavior a per-app cancel's "collapse to nil when equal" logic depends on. `testARemovalIsReadBeforeAnAddition` (66), `testARemovalNamesTheAppAndTheDay` (78), `testAnAdditionNamesTheApp` (88), `testAnAllowanceReadsAsSessionsWhenOnlyTheCountMoved` (98), `testAnAllowanceReadsAsMinutesWhenOnlyTheLengthMoved` (117), `testAnAllowanceReadsBothFieldsWhenBothMoved` (136), `testThePauseDurationNeedsNoApp` (155), `testTwoChangesNameTheFirstAndCountTheOther` (165), `testFourChangesStayOneSentence` (181), `testNoNamedChangeFallsBackToTheBareNotice` (203).

**Model-level cancel and scheduling flows** — `Tests/PauseAppTests/AppModelFlowTests.swift`:
- `testCancellingAScheduledChangeLeavesTodaysRuleInForce` (275-294) — **the test to generalize** for per-app cancel; today it only covers the single-scheduled-change case and asserts the whole file's `pending` becomes `nil`.
- `testShorteningThePauseWaitsWhileLengtheningItAppliesAtOnce` (296-315), `testRemovingAnAppLeavesItsRuntimeUntilTheChangeTakesEffect` (317-334), `testDroppingAnAppFromThePickerKeepsItSelectedUntilTheRemovalLands` (336-353), `testTheRemovalTakesTheAppAndItsSelectionWhenItLands` (355+), `testATighteningSaveDefersNothingOfItsOwnWhileAChangeIsScheduled` (422).

No existing test exercises: two independent pending changes (one per app) both present simultaneously and one cancelled while the other survives — that scenario is implied reachable by the router tests (section 1) but never asserted end-to-end through `AppModel`. **This is the key gap a per-app cancel redesign must close with new tests**, since it's the exact scenario the feature targets and nothing today pins it.

## Docs vs. code

`docs/design/pause-app.md` and `docs/design/configurable-daily-reset.md` describe the deferred-change/loosening policy accurately and match the code (`ConfigurationSaveRouter`, `ConfigurationComparison`, `ConfigurationFile.inForce`) with no discrepancies found. Neither doc describes today's per-app UI (`pendingRemovalRow`, `ScheduledChangeNotice`) in enough detail to compare against a redesign — they're silent on cancellation granularity, which is consistent with cancellation today being document-wide.

## Bottom line

Per-app cancel is reachable. The data needed to reconstruct one app's prior state is always present in the in-force document (nothing is purged from `effective` until its own reset lands), and the identity model (`ruleID`-keyed units) is exactly what's needed to select and rebuild one unit. The hardest obstacle is not data loss — it's that **no existing function does a per-unit revert**; `cancelScheduledChange()` is document-wide by construction and `ConfigurationSaveRouter.route` is designed around candidate-vs-in-force loosening judgment, not "revert this one already-scheduled unit." A redesign needs: (1) a new function, `cancelScheduledChange(ruleID:)`-shaped, that takes the current pending document, replaces one unit with its in-force counterpart (or drops it if the unit was a pure addition), leaves every other unit and settings untouched, and collapses `pending` to `nil` if the result equals `effective` (reusing the equality check already at `ConfigurationSaveRouter.swift:63`); (2) a decision about settings (pause duration, reset minute) changes, which have no per-app row to live on and currently share the whole-document cancel — the report's redesign scope doesn't cover them; (3) new tests for the multi-pending-change-survives-a-per-app-cancel scenario, which nothing pins today.
