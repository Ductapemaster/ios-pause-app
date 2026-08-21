# Per-app rule changes

A saved edit is judged one app at a time. Adding an app to Pause takes effect at once even when the same trip through the picker drops another, and a change scheduled for one app survives a later decision about a different one. This replaces the rule in [deferred rule changes](deferred-rule-changes.md) that an edit is judged whole; everything else in that design stands, including what counts as loosening and when a deferred change lands.

## Terms

Carried over from [deferred rule changes](deferred-rule-changes.md): effective configuration, pending configuration, logical day, start day, in force, loosening. New here:

- **Unit** — the thing a save is judged on: one rule together with the target naming its app, keyed by `AppRule.id`. Global settings are one further unit, because `pauseSeconds` belongs to no app.
- **Touched** — a unit the candidate document states differently from the document in force. It is how a save's intent is read: a save rebuilds the whole document, so what it left alone is what it had no opinion about.
- **Carried forward** — an untouched unit taking its scheduled form rather than its in-force one, so that a decision about one app leaves another app's schedule alone.

## Why the whole-document rule goes

The existing design judges an edit whole and gives its reason: applying part of an edit now and part tomorrow "would mean storing a difference rather than a document, and the added machinery is not worth the precision."

That reason does not apply to a split by unit. Both halves come out as complete `ConfigurationDocument`s, `configuration.json` keeps the shape it has, and every reader still resolves what applies through `inForce(on:)`. Nothing stores a difference. What the split costs is a comparison run per unit instead of once, over data the comparison already walks rule by rule.

What the whole-document rule costs is visible in two places:

- A picker trip that adds one app and drops another covers neither until the reset. The add is a tightening; making it wait permits app use that nobody asked to permit.
- Any save rebuilds the document from the rules in force, so it silently replaces a change scheduled for an unrelated app.

## The unit's two questions

A save has three inputs — the document **in force**, the **candidate** the screen built, and the **pending** document if one exists — and produces the two documents the file holds. Each unit is decided independently, and each decision answers two questions in order.

**What does this unit want to become?** If the candidate states the unit differently from the in-force document, this save decided about it, and the candidate's form wins. Otherwise the save had no opinion, and the unit takes its pending form if one is scheduled, and its in-force form if not.

**When does it get there?** If that form loosens against the in-force form, the new effective document keeps the in-force form and only the new pending document carries the change. If it does not loosen, both documents take it.

The new pending document therefore holds everything anyone has asked for, and the new effective document holds that same thing minus whatever loosens. Where they come out identical nothing is scheduled and the pending slot clears — which also clears a pending document whose start day has already arrived, since it is in force by then and both documents take it.

A carried-forward unit's change starts on the day after the save rather than the day after it was first scheduled. Those are the same day in every reachable case: a pending start day is always the day after its own save, so a still-future one is tomorrow already, and an arrived one is in force and no longer scheduled.

## Worked cases

Instagram's removal is scheduled; the picker is then used to add TikTok.

| Unit | Touched | Becomes | Today | Tomorrow |
|---|---|---|---|---|
| Instagram | no | its scheduled form: removed | covered | removed |
| Facebook | no | unchanged | covered | covered |
| TikTok | yes | added | **covered** | covered |

Instagram is scheduled to go to five sessions; the picker is then used to add TikTok.

| Unit | Touched | Becomes | Today | Tomorrow |
|---|---|---|---|---|
| Instagram | no | its scheduled form: 5 sessions | 3 sessions | 5 sessions |
| TikTok | yes | added | **covered** | covered |

Instagram is scheduled to go to five sessions; the rule editor is then used to set it to four.

| Unit | Touched | Becomes | Today | Tomorrow |
|---|---|---|---|---|
| Instagram | yes | 4 sessions | 3 sessions | 4 sessions |

The last case is the one that keeps last-write-wins where it belongs. A save that states an opinion about an app replaces what was scheduled for that app, and only for that app.

## What changes in the code

`ConfigurationSaveRouter.route` keeps its signature. It already receives the candidate, the whole `ConfigurationFile` — which carries both the in-force and the pending document — and `now`, so the split is entirely internal to it. All four save paths gain the behavior at once and none of their callers change, `AppModel.applyPickerSelection` included.

- **`ConfigurationComparison`** — `isLoosening(from:to:)` already walks rules one at a time and OR's the results. Extract that per-unit judgment and the settings judgment as their own functions; the document-level function becomes their disjunction and keeps its callers.
- **`ConfigurationSaveRouter`** — build the two documents from the per-unit decision above.
- **`ScheduledChange.addition`** — keep it. A picker save can no longer schedule an addition, since an add tightens and lands immediately, but the case is still emitted by the branch that reads a re-pointed target as a removal and an addition together. That branch guards a change no screen can make; leaving it alone keeps this effort to the judgment and out of the notice's wording.

A latent fault closes with it. A deferred picker save writes an added rule's runtime immediately, while orphan cleanup keeps only the runtimes of rules the in-force document names — so the runtime of an added-but-deferred rule could be swept before its rule arrived. An add that applies at once is never in that window.

## What the app shows

The notice draws what one document does to another, so it follows the split without changing: with the adds already in the effective document, only the deferred units are left to name. A mixed picker save that used to name the drop and count the add alongside it now names the drop alone, and the app it added is simply covered.

One rule needs restating, and stating precisely. A deferred save leaves the rule editor open under the notice and an immediate save closes it; a save can now defer one part of itself and apply another. **The editor stays open when this save deferred something.** Not when something is merely scheduled: a save can now leave the slot occupied without having deferred anything itself, by carrying forward a change scheduled for an app it did not touch, and closing the editor is right there — the wait it would be showing is not the one the person just chose.

The test is one comparison. A save deferred part of itself exactly when the new effective document differs from the candidate it was handed, because the two can only differ on a unit this save touched: an untouched unit takes its in-force form in the effective document and already had that form in the candidate. The editor reads that rather than the pending slot, which stays what the notice is drawn from.

## What is not changing

- **One pending slot.** The file holds one pending document, and this design keeps it. Carrying units forward is what makes the single slot behave, not a reason to add a second.
- **Cancelling clears everything scheduled.** `cancelScheduledChange` writes the in-force document back over effective and clears the slot, even though the rules list presents a scheduled removal per row. Per-app cancel is coherent with this design and is deliberately left out of it: it is a change to what the screens offer rather than to how a save is judged.
- **What counts as loosening**, the reset event, the read sites, and migration are all as [deferred rule changes](deferred-rule-changes.md) has them.

## Testing

The judgment stays a pure function over value types, so the whole design is testable without a device.

- **Per-unit comparison** — one test per field in both directions; a unit added; a unit removed; a target re-pointed at another application; and the settings unit in both directions.
- **The router**, across the combinations that matter: touched against untouched, loosening against tightening, and a pending document present against absent. Specifically that an untouched unit's scheduled change survives a save about another unit; that a touched unit's scheduled change is replaced; that a mixed picker save writes the add to effective and the drop to pending in one call; and that identical documents clear the slot.
- **The document-level `isLoosening`** keeps its existing tests, which now exercise the disjunction over the extracted parts.

Above those, the existing save-path tests assert the split end to end: a picker save that adds and drops leaves the added app covered today.

## Known limits

**A re-pointed target cannot collide, because it cannot happen.** Two targets naming the same application would be a document the model permits and the shield could not resolve sensibly, and carrying a unit forward is the only way to build one — a scheduled re-point of an existing target onto a token that a later save adds as a new app. No screen can re-point a target: the picker rebuilds targets from the selected tokens, giving a new rule a new id, and the editor does not touch tokens. `isLoosening` guards re-pointing defensively, and this design inherits that guard without needing a rule for a collision no interface can produce.

**A save still states an opinion by rebuilding.** Touched is inferred from the candidate rather than declared by the screen. Two saves that arrive at the same document are indistinguishable, so a rule editor save that changes nothing counts as untouched and carries a scheduled change forward. That is the right answer for the case it appears in, and it is an inference rather than a statement of intent.
