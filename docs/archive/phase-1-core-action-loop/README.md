# Phase 1 — Core Action Loop

Shipped and accepted 2026-08-21. Delivers the shield-pause-use loop end to end: Screen Time authorization and app selection, shielding with per-rule remaining counts, shield intent handoff, the foreground pause countdown, transactional session grants with rollback, expiry restoration, and the daily limit.

- [plan.md](plan.md) — the nine-task implementation plan, frozen as executed.
- [acceptance.md](acceptance.md) — the acceptance record: what the acceptance rests on, and what it leaves unverified. Its ten-step run-through is the **regression script** — the thing to run when a bug appears in the loop.

The standing architecture is not here: [docs/design/pause-app.md](../../design/pause-app.md) covers every phase and stays live.
