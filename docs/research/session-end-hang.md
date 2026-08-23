# The session-end lock-out

The defect behind two reported symptoms: a device that stops responding when a session ends, and a shield button that does nothing when pressed shortly afterwards. The mechanism is established, reproduced, and fixed.

The fix released the app group state lock before the expiry callback calls `DeviceActivityCenter.stopMonitoring`. Measured on 2026-08-23 after the change, the stop returns in 11 ms and the whole handler finishes in 41 ms, against 31 seconds before it. The shield's primary button acts during the window that used to swallow it.

## The mechanism

When a session expires, `intervalWillEndWarning` takes the app group state lock and reconciles, restoring the shield within about 26 ms. It then calls `stopMonitoring`. While that call was made with the lock still held, the handler did not return for 31 seconds — the DeviceActivity host tore the extension down before it finished — and the lock stayed held throughout.

For those 31 seconds every other participant was locked out. `AppGroupFileLock` gives up after 2 seconds by design, so each one failed rather than hanging forever, and what the user saw depended on which one asked:

- The **shield action extension** failed with POSIX 60 `ETIMEDOUT` when the primary button was pressed, which is what made the button dead.
- The **`intervalDidEnd` handler**, which arrives 32 ms after the warning on a second thread of the same process, blocked on the lock for the full 31 seconds before doing its own work.

**It is a deadlock, and Pause builds every side of it.** The host's own log shows the chain ([the platform evidence](screen-time-platform-evidence.md) carries the traces): the stop cancels the activity's pending end alarm, and cancelling it makes the host deliver `intervalDidEnd` — to a second thread of the same extension process, milliseconds later, while the warning handler still holds the lock. That callback blocks on the lock, and the stop does not return until it has been delivered and run. The warning cannot release the lock until the stop returns.

Off the lock the same call costs 11 ms, because `intervalDidEnd` takes the lock immediately, finishes, and lets the stop complete.

That the stop waits on the callback it triggers is a reading of the ordering rather than something the host states, but the sequence repeats across all three sessions of the day.

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
