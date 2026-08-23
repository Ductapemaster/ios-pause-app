# The device hang when a session ends

Open investigation. The root cause is not established, and no fix for it has been written. A sysdiagnose from 2026-08-23 09:02 settled several questions and closed off two lines of enquiry.

## What was observed

Reported on 2026-08-22, on the build from `feat/session-usage-display`. An Instagram session was in progress and reached its end near midnight. The shield should have reappeared at that moment. Instead the phone became unresponsive — not Instagram alone, the device. It recovered on its own after a delay, returning to the home screen. Opening Instagram again showed the shield present but still frozen. Pause then appeared to crash and the phone returned to the home screen.

It happened twice, near midnight and again on the session that crossed it. Neither the hang nor the apparent crash had been seen before, and this was the first time the path had been exercised.

## What the system log establishes

Pause never crashed. No Pause crash report exists in the incident window, on the Mac or inside the sysdiagnose, and no hang or spin report either — reports from 00:17, 00:41 and 01:04 all synced, so the window is covered. The 01:04 jetsam event lists 431 processes and neither Pause nor its extensions appear, so it was not a memory kill. The process itself, pid 56674, ran continuously from 23:51:12 until after 00:09, moving between `running-active` and `running-suspended` throughout.

Whatever ended the app in view was therefore not a termination. What Dan saw as a crash has to be explained some other way — the shield dismissing, or the interface recovering — and the app's own continuity is the evidence against the obvious reading.

The system-side timeline for the grant is intact:

- **23:51:11** — `ShieldConfigExtension` launches under `ManagedSettingsAgent` and renders
- **23:51:12** — `ShieldActionExtension` launches; SpringBoard launches Pause (pid 56674)
- **23:51:33** — `MonitorExtension` launches under `UsageTrackingAgent` (pid 56679), and stays alive to 00:04:24
- **23:58, 00:00, 00:04, 00:08** — Pause cycles active/suspended
- **00:08:11** — `FamilyControls.ActivityPickerExtension` opens inside Pause, closing at about 00:09:11

## What is ruled out

**The reset boundary is not involved.** The daily reset is configured at **05:00**, not midnight: the archive shows the only `daily-reset` callbacks at 04:59:02 (`intervalDidEnd`) and 05:00:02 (`intervalDidStart`). Midnight is an ordinary civil-date boundary here, carrying no allowance renewal. Any explanation resting on the reset firing at midnight is therefore excluded.

The session-count work is not implicated. Its commits (`295a15c`, `a9c123a`, `003a273`, `54d17d3`) touch `AppModel.swift` and `RulesView.swift` only — the in-app views, nothing on the monitor or shield path.

A wrapping `DeviceActivitySchedule` is not implicated. `DeviceActivitySessionScheduler.absoluteComponents` builds both `intervalStart` and `intervalEnd` from absolute components including era, year, month and day, so a session spanning midnight describes a real interval. The wrap-to-24-hours behaviour in [the platform evidence](screen-time-platform-evidence.md) applies to the daily reset's repeating schedule, registered from bare hour and minute — not to a session.

No unbounded loop exists on the end-of-session path. `SessionReconciliationCoordinator.reconcile`, `SessionReconciliationService`, `ShieldReconciler.reconcile` and `RuleLookup` are all bounded by the configured rule count, and `AppGroupFileLock` bounds its own acquisition at two seconds.

## What the archive cannot show, and why

Pause's own logging for the incident is unrecoverable. The archive retains **no third-party subsystem entries at all** in that window: a count of every non-Apple subsystem between 23:45 and 00:15 returns zero, against 220,606 total lines. The `MonitorExtension` process is visible there only through Apple's own `containermanager` subsystem, which records app-group lookups at 23:51, 23:56, 23:57, 23:58, 00:03 and 00:04.

This matters for how the evidence is read. The monitor's `Monitor callback …` lines are absent from that window, and the temptation is to conclude the callbacks never fired — the extension logs at `notice` on entry, before any container work, and that logging was present in the build that was running. But the retention gap explains the absence on its own, so it is not evidence either way. The same gap explains why the container lookups appear without them.

Retention is short for non-Apple subsystems, so **an archive gathered hours later cannot answer this**. The capture has to happen close to the event.

## What to do at the next occurrence

Gather a sysdiagnose **promptly** — within the hour, not the next morning:

```
xcrun devicectl device sysdiagnose --device <device-id> --destination <dir>
```

It needs no root, but it does need the phone **unlocked and awake**; against a locked phone it waits indefinitely without producing an archive. The on-device equivalent is Volume Up + Volume Down + Side held for about a second, which syncs to the Mac by itself.

`log collect --device-udid` is not an option: it needs root and then fails with `Device not configured` (ENXIO) even with the phone wired and `transportType: wired` confirmed. It is not the cable and not the password.

Then read, in the fresh archive:

- `Shield render began` against `Shield render returned` — an entry without its exit identifies a hung render. This pair exists only in builds from 2026-08-23 onward and is confirmed working (08:45:11, resolving in 10 ms).
- `Monitor callback … for activity` against `… returned for activity`.

## The open lead

The FamilyControls picker opened inside Pause at 00:08:11, minutes after the reported hang. [The roadmap](../ROADMAP.md) already records that applying a picker selection blocks the main thread — each added app takes a file-lock cycle plus a JSON encode and atomic write, `configurationStore.save` takes another, and `ShieldReconciler.reconcile` holds the lock while re-reading every target's runtime — and notes that measuring it is the cheap first move if a hang is ever reported. One now has been.

This is a lead, not a conclusion, and the timing is against it as an explanation of the *first* hang: Dan describes the freeze as beginning when a session ended, which the log places around 23:51, not 00:08. It is worth measuring on its own merits regardless.
