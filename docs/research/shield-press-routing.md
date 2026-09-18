# A shield press can land on the screen Pause was already showing

Pressing a shield's primary button opened Pause on its rules list instead of the countdown. The extension resolved the press correctly and handed off an intent; the app discarded it, because the activation that followed was not treated as a new one. The user is left looking at whatever screen Pause last showed — the rules list, or a rule editor — which is what the report described as "an apps setting page".

One press on the evening of 2026-08-24 is explained by that path and is measured end to end. A second press the same evening had no session either, and which screen it landed on is not determined by the archive; that question is open at the bottom of this note.

## Reproducing the evidence

The lines below come from a device log archive covering 2026-08-24 18:00 onward, collected and read with the commands in the root `CLAUDE.md`:

```bash
sudo /usr/bin/log collect --device-udid <device-udid> \
  --start "2026-08-24 18:00:00" --output /tmp/pause.logarchive

/usr/bin/log show /tmp/pause.logarchive \
  --predicate 'subsystem BEGINSWITH "com.koubalabs.pause"' --style compact
/usr/bin/log show /tmp/pause.logarchive \
  --predicate 'process == "Pause"' --style compact
```

The second predicate is what carries the process lifecycle — `com.apple.hangtracer` and the touch-event lines — and neither is under Pause's own subsystem.

## Observed: three presses, one session

Three `Shield action resolved: openPause` lines appear that evening, all from the same shield action extension process, PID 69410.

| Press | App process state | Outcome |
|---|---|---|
| 22:20:43.349 | PID 69380, foreground since 22:19:16, never backgrounded | No session followed. The press had no effect. |
| 22:41:53.435 | Cold launch — PID 69526 starts at 22:41:53.596 | No session. Foreground for 7.6s (to 22:42:01.237): two taps at 22:42:00.399 and .446, then a swipe-out gesture (touch events ~17ms apart, 22:42:01.100–.232). |
| 22:48:22.352 | Warm — PID 69526, backgrounded cleanly at 22:48:14.652 | Succeeded. Countdown ran ~21s; `session.b85fac20-880c-4a7c-adb4-f12bc8db5c8e` `intervalDidStart` at 22:48:44.272. |

Measured, and load-bearing for everything below:

- **The extension resolved `openPause` on all three presses**, from one extension process (PID 69410). iOS consulted Pause's shield action extension every time, so the system "Restricted" web-domain case — which never invokes the extension at all ([the platform evidence](screen-time-platform-evidence.md), "A shielded app's web domain is shielded too") — is not what happened here.
- **`com.apple.hangtracer` logs a background transition for this app reliably.** It fires five times for PID 69526: 22:42:01.237, 22:42:15.872, 22:48:14.652, 22:48:45.099, 22:48:49.678. For PID 69380 it fires **zero** times across that process's whole life, 22:19:16 to 22:24:47. Absence of the line is therefore a measurement, not a gap in instrumentation.
- **PID 69380 was being touched right up to the press.** Touch-event bursts at 22:19:51, 22:19:54, 22:20:01, 22:20:07, 22:20:27, 22:20:29, 22:20:31, 22:20:34, 22:20:36 and 22:20:41, then nothing until 22:21:04.959 — a 23-second gap spanning the 22:20:43 press.

## Tested: which press each fact separates

The three presses differ in exactly one respect that the archive can see — whether the app process had gone to the background before the press — and the outcomes split along it. 22:48:22 was preceded by a clean background transition and produced a session. 22:20:43 was preceded by none, on a process that had never backgrounded, and produced nothing. 22:41:53 launched a fresh process, which cannot have carried state from an earlier foreground.

The gap in touch events on PID 69380 places the user away from Pause across the press: last touch 22:20:41, press 22:20:43, next touch 22:21:04. The app was on screen and in use immediately before, went untouched while the shield was pressed, and was touched again 21 seconds later — the shape of leaving Pause to a shielded app, pressing the shield, and coming back to a Pause that had not moved.

## Concluded: the `.unchanged` path

The 22:20:43 press hit `.unchanged`. Pause went `.inactive` when the user left it — the app switcher — but never `.background`, so `sceneDidLeaveForeground()` never ran, `hasHandledCurrentActivation` was never cleared, and the activation that followed the press returned before reading the intent at all.

The mechanism, in the order it runs:

- `Sources/Pause/PauseApp.swift:37-43` — the `.inactive` scene phase is deliberately ignored. The comment reads: "A banner, a Control Center pull, or the app switcher. The user has not left, so an in-progress countdown stands." Only `.background` calls `model.sceneDidLeaveForeground()`.
- `PauseActivationCoordinator.sceneDidLeaveForeground()` in `Sources/PauseCore/PauseCountdown.swift` is the only place `hasHandledCurrentActivation` is set back to `false`.
- `PauseActivationCoordinator.activate` opens with a guard that returns `.unchanged` while that flag is `true`. The build that took this press did not check for a waiting intent there, so with the flag still `true` from the earlier foreground the guard fired and the intent was left unconsumed.
- `Sources/Pause/AppModel.swift:248-249` — `.unchanged` returns from `sceneDidBecomeActive` without touching `entryRoute`, so the app keeps rendering whatever it was rendering.

That exclusion protects a running countdown from a notification banner or a Control Center pull, and it is right for that. It is wrong at this edge: a shield press arrives through the same `.inactive`-only path when Pause is already frontmost behind the app switcher, and there the press is real intent. The flag alone cannot tell the two apart. The intent store can: the shield action extension writes its intent before it asks iOS to bring Pause forward (`Sources/Shared/ShieldPrimaryAction.swift`, the `intentStore.write` in `resolve`), and a banner or a Control Center pull writes nothing.

So `activate` takes a `hasPendingIntent` check, and a waiting intent reopens an activation the flag marks handled. The app passes `ShieldIntentStore.hasPendingIntent`, which reads the key without consuming it. A return with nothing waiting stays `.unchanged`, which keeps a countdown through a banner. Pinned by `testAPendingIntentMakesAnUnbackgroundedReturnANewActivation` (the coordinator) and `testAShieldPressWhilePauseNeverBackgroundedOpensThePause` (the app model, through the real intent store). A second consequence follows from the same rule: a press on another app's shield while a countdown runs behind the app switcher replaces that countdown, so the most recent press wins.

Inferred, not measured: that the user reached the shielded app via the app switcher specifically. What is measured is that no `.background` transition occurred, which is what the `.unchanged` path requires; the app switcher is the ordinary way to produce that. The screen the user saw is inferred the same way — the touch bursts before the press are consistent with the rules list or a rule editor, and the app logs nothing that names the screen.

## Open: where the 22:41:53 cold launch landed

Unresolved. The press resolved `openPause` and started a fresh process, and no session followed, but the archive cannot say which screen came up.

A cold launch cannot hit `.unchanged` — the process is new and `hasHandledCurrentActivation` starts `false` — which leaves two candidates:

- **`.configuration`** — the intent read back as `nil`, so `activate` routes to the rules list (`Sources/PauseCore/PauseCountdown.swift:284-286`).
- **`.repair`** — the intent was older than the 30s maximum, or the configuration or the rule's runtime could not be read (`Sources/Pause/AppModel.swift:921-931` for the age check, `:944-966` for the runtime read).

The 7.6-second foreground with two taps and then a swipe-out fits either: a repair screen has a button to dismiss, and the rules list has rows.

What would discriminate them is a log line at the point the route resolves, naming the route and the reason it was chosen. The app logged no routing decision at the time, so the archive holds nothing to separate the two. That instrument now exists — `Entry route resolved:` at `.notice` under `com.koubalabs.pause` — and the next occurrence settles it.

- [ ] After the next shield press that fails to reach a countdown, collect the archive and read the `Entry route resolved:` line for the activation that followed it.
