# Plan: end the session-end lock-out

Fixes the defect in [the session-end lock-out](../research/session-end-hang.md): a framework call that never returns, made while the app group state lock is held, excludes every other participant for 31 seconds. Read that note first — it carries the mechanism and the reproduction.

Three tasks, ordered by what each one buys. Task 1 ends the lock-out; tasks 2 and 3 remove the conditions that made it reachable and stop it lying to the user when something else does fail. Each lands as its own commit with a failing test written first.

## Task 1 — take the framework call out of the lock

The lock protects the JSON state in the app group container. `stopMonitoring` touches none of it, so holding the lock across that call buys nothing and costs everything.

Move the `stopMonitoring` call in `SessionReconciliationCoordinator.reconcile` (the `intervalWillEndWarning` branch, currently after `applyShields`) outside the locked region, so the lock is released once the shield write has committed. The coordinator does not own the lock — `SessionReconciliationService.reconcile` wraps the whole pass in `stateLock.withLock` — so the split has to happen at the service boundary: the coordinator returns what still needs stopping, and the service stops it after the lock is dropped.

- [x] Test: a reconciliation whose trigger is `intervalWillEndWarning` releases the state lock before `stopMonitoring` is invoked. Assert on ordering with a lock whose acquisition is observable, not on a timing threshold.
- [x] Test: a second participant can take the lock while `stopMonitoring` is still blocked.
- [x] Move the call; keep the existing behaviour that it runs only when shields applied and the callback could stop.

**Verification is on the device, not in tests.** Repeat the reproduction and confirm the shield action succeeds during the 31-second window instead of failing at 2 seconds. Done on 2026-08-23: the primary button acts during the window.

## Task 2 — stop calling `stopMonitoring` from inside its own callback

Even off the lock, the call still blocks the handler for the extension's remaining life, and an app extension runs on a runtime budget the system enforces.

The open question is what to do instead, and it should be settled before code is written: whether the activity needs an explicit stop at all once its interval has ended, or whether the stop can be deferred to the app's next foreground pass. `docs/research/screen-time-platform-evidence.md` records that `stopMonitoring` is followed by `intervalDidEnd` within milliseconds, which is a reason to be careful — a stop issued from the end-of-interval path may be re-entering the same callback.

- [ ] Confirm by instrumenting `stopMonitoring`'s entry and exit that it is in fact the blocking call. The current attribution is inferred from the code path and the 2 ms gap between the host's invalidation and the handler's return, not measured.
- [ ] Decide whether the stop is needed at all, and record the reasoning in the platform evidence note.
- [ ] Implement whatever that decides.

## Task 3 — separate a failure from a refusal in the shield action

`ShieldPrimaryAction.resolve` maps every thrown error to `.dismiss`, so a transient lock timeout closes the shielded app as though the day's allowance were spent. A refusal is a decision about sessions; an error means we do not know. They must not share an outcome.

- [ ] Test: a lock timeout does not resolve to `.dismiss`.
- [ ] Test: a genuine refusal — allowance spent, session already open — still resolves to `.dismiss`. This is the behaviour shipped on 2026-08-23 and must not regress.
- [ ] Add a third outcome for a failure and map it in the extension. Leaving the shield up is the safe answer; closing the app is not, because the user may well have a session available.
