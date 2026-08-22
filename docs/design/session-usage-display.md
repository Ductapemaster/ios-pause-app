# Session usage in the app

The rules list names each app and its limit. It does not say how much of that limit is spent, so the only place the day's usage appears is the shield — which is reached by tapping the app, at the moment the information is least useful. This puts the count in the app.

## What the list shows

Each app row carries its usage as a trailing value, in the shape the settings rows below it already use:

```
Instagram                     2/4
TikTok                        3/3
X                             0/5
```

The numerator is sessions charged against the current allowance day; the denominator is the rule's `sessionsPerDay`. Session length leaves the row and stays in the editor, which is where it is set.

`3/3` states exhaustion on its own, so that state needs no separate treatment. An open session is not marked: it is charged at its start, so it already counts, and the target app is where its progress is visible.

A rule whose runtime cannot be read shows no number rather than a wrong one. The repair route that already exists for unreadable runtime is unchanged.

## The count cannot be read from disk

`RuleRuntime.sessionsStarted` is rolled over lazily — only when a session is evaluated or reserved. A record therefore keeps yesterday's count until something touches it, so an app left alone since a heavy day still reads `4` on disk when the true answer is `0`.

Any surface showing the count must resolve the allowance day itself and apply the rollover. `RuleLookup.evaluate` already does this: it takes the day, rolls the runtime to it, clears an expired session, and returns the normalised value. It writes nothing, so calling it for display is free of side effects.

Reusing it is the point. A lighter "just read the count" helper would be a second implementation of the rule that decides which day a session is charged to, and two implementations of that rule are what let the count renew at midnight under a configured reset of 06:00 — the defect the configurable-reset effort closed. One path with two callers cannot drift; two paths agree only until one is edited.

## Where it is computed

`RuleUsageReader` in `Sources/Shared/` pairs the configuration file with the runtime repository and returns the used count per rule, applying `RuleLookup.evaluate` to each. It is the sibling of `ShieldStateReader`, which does the same job for the shield: both take the file rather than a document, because the allowance day comes from the effective document's reset and only the file can pair the two.

Placing the loop here rather than in `AppModel` keeps it testable without a view model, and keeps the app's surface and the shield's surface built the same way.

## How it reaches the view

`AppModel` publishes the reader's result and the views read it, matching how every existing view gets its state — no view reaches the repository directly.

The snapshot is rebuilt where the app already re-syncs:

- on foreground, alongside the authorization, in-force configuration, and reset registration refreshes
- after a session is granted, which is the only event that raises a count
- after a configuration save, which can add, remove, or re-limit a rule

The count is therefore correct whenever the list is reached. It does not tick while the screen is open; nothing it displays changes on a timer, because a session is charged at its start rather than as it runs.

## What it costs

Rebuilding the snapshot is one file read and one lock acquisition per rule, synchronously, on the main thread. For a handful of apps this is small, but it is the same class of cost as [applying a picker selection](../ROADMAP.md), which holds the interface for the same reason. Neither is measured. If either is taken up, both move off the main thread together — splitting them would leave the codebase with two conventions for reaching the same files.

## Product requirements

Both surfaces and the relationship between them are stated in [the product requirements](../product-requirements.md), which are the source of truth for what the count is for.

## Testing

The reader is a pure function over a configuration file and a set of runtime records, so `SharedTests` covers it directly: a runtime carrying yesterday's label reads as `0` used, a runtime on the current allowance day reads its stored count, an exhausted rule reads its limit, and a missing runtime yields no count.

One case earns its place beyond the obvious: **the reader is tested at a non-zero reset**, with a runtime labelled to the previous allowance day and an instant after local midnight but before the reset. That is the shape of the defect the configurable-reset effort shipped and had to fix, and a suite that only ever exercises midnight cannot see it.

## Out of scope

**History.** The roadmap holds session history as an open question. This shows the current allowance day only and stores nothing new, so it neither answers that question nor forecloses it.

**Usage in the editor.** The list carries usage; the editor sets and shows session length. One home for each.

**A live session countdown.** The remaining minutes of an open session would be the app's only ticking value, and it would tick where nobody is looking — during a session the target app is in the foreground.
