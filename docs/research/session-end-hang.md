# The session-end lock-out

The defect behind two reported symptoms: a device that stops responding when a session ends, and a shield button that does nothing when pressed shortly afterwards. The mechanism is established and reproduced. No fix is written yet — [the plan](../plans/session-end-lock-contention.md) carries the work.

## The mechanism

When a session expires, `intervalWillEndWarning` takes the app group state lock and reconciles. It restores the shield within about 26 ms, which is the part the user is waiting on and it works. It then calls `DeviceActivityCenter.stopMonitoring` — still inside `stateLock.withLock` — and that call does not return from inside its own callback. It blocks until the DeviceActivity host tears the extension down, roughly 31 seconds later, holding the lock the whole time.

For those 31 seconds every other participant is locked out. `AppGroupFileLock` gives up after 2 seconds by design, so each one fails rather than hanging forever, and what the user sees depends on which one asked:

- The **shield action extension** fails with POSIX 60 `ETIMEDOUT` when the primary button is pressed. Before 2026-08-23 that produced `ShieldActionResponse.none` — a button that did nothing. It now closes the app, which is a different wrong answer and is itself on the fix list.
- The **`intervalDidEnd` handler**, which arrives 32 ms after the warning on a second thread of the same process, blocks on the lock for the full 31 seconds before doing its own work.

Two platform behaviours set this up, both recorded in [the platform evidence](screen-time-platform-evidence.md): both end callbacks arrive together for a short session, contrary to the scheduler's padding, and `stopMonitoring` does not return from within a callback.

## The reproduction

Reproduced deliberately on 2026-08-23 at 09:28, on a 3-minute Instagram session, with a sysdiagnose gathered two minutes later. Stay in the shielded app until the session expires, then press the primary button within 30 seconds of expiry. The full timeline sits in the platform evidence note.

Session length is the lever: shortening it is a tightening and applies at once, so a 1-to-3-minute session makes the wait short. Raising sessions per day is a loosening and defers to the next reset, so the day's remaining sessions bound how many attempts are available.

## The original report

The first sighting, on 2026-08-22 at about 23:51, was described as the whole phone freezing, recovering, and then Pause appearing to crash. The lock-out explains the freeze and the dead button. It does not by itself explain a device-wide freeze, and the apparent crash was not one: no crash, hang, or jetsam record exists for that window, and the Pause process ran continuously across it. Whether the device-wide symptom is the same defect seen from the outside, or something additional, is not settled.

## Capturing evidence

A sysdiagnose is the only route that works, and it must be gathered **within the hour** — the log archive retains no third-party subsystem entries beyond a short window, which is why a capture taken the next morning showed nothing of Pause at all:

```
xcrun devicectl device sysdiagnose --device <device-id> --destination <dir>
```

It needs no root, but the phone must be **unlocked and awake**; against a locked phone it waits indefinitely and produces nothing. `log collect --device-udid` is not an option — it needs root and then fails with `Device not configured` (ENXIO) even with the phone wired and `transportType: wired` confirmed.

Read `Shield render began` against `Shield render returned`, and `Monitor callback … for activity` against `… returned for activity`. An entry without its exit names what hung.
