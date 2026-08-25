# Per-app scheduled change presentation

Shipped 2026-08-24. A pending change lives on the row of the thing it changes and is cancellable one app at a time, replacing a banner whose one cancel dropped every app's scheduled change.

- [plan.md](plan.md) — the six tasks, frozen as executed.

Three things shipped that the plan did not specify. The editor reseeds its controls from the document in force whenever the pending state changes, so a deferred save cannot leave the value just typed on screen under a locked control. The Day reset picker locks while a pause duration change is pending, because settings are judged as one unit and a reset-minute save would otherwise rebuild the settings from the in-force pause and discard the scheduled one. And the app picker adds only.

The design stays live as as-built in [docs/design/scheduled-change-presentation.md](../../design/scheduled-change-presentation.md), and the picker's rule in [docs/design/add-only-app-picker.md](../../design/add-only-app-picker.md).
