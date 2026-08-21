# What the Screen Time frameworks actually do

Measured behavior of `FamilyControls`, `ManagedSettings`, `ManagedSettingsUI` and `DeviceActivity`, kept in one place so the same questions are not re-derived every time the enforcement layer is touched. Apple documents little of this and some of it contradicts what the names suggest.

Every entry names how it was established. Anything that was not run says so — an inference from a declaration is marked as one, and a null result is stated as a null result rather than dressed up as a finding.

Three rigs stand behind everything below:

- **Device** — iPhone 16 Pro, iOS 26.6, Family Controls authorized. Runs of 2026-08-12, 08-13 and 08-14.
- **Simulator** — iPhone 17 Pro, iOS 26.5, unauthorized, 2026-08-13. The frameworks do not function there: authorization fails and the picker shows categories with no apps. Some questions are answerable anyway — see the validation ordering below.
- **SDK reading** — `.swiftinterface` files shipped with Xcode 26.6, under `.../SDKs/iPhoneOS.sdk/System/Library/Frameworks/<framework>.framework/Modules/<framework>.swiftmodule/arm64e-apple-ios.swiftinterface`. Never executed. What a declaration does is inference; the name is suggestive, not evidence.

## The shield configuration extension's sandbox

**Shared-preferences reads from the App Group succeed inside the shield configuration extension. Its writes to the same suite do not land.** Measured on device, 2026-08-12 and 08-13.

The read was proven directly rather than inferred from an absence. The instrument was a tap counter held in the App Group's `UserDefaults` suite: the shield *action* extension increments it when the shield's primary button is pressed, and the *configuration* extension reads it and renders it into the shield's subtitle. Across five presses the rendered number climbed, so the configuration extension read back a value written by a different process.

Writes behave the other way, and not intermittently — on every render, across a session in which the shield action and monitor extensions wrote to that same suite normally, nothing the configuration extension wrote ever appeared.

The denial comes from the sandbox profile iOS assigns the shield configuration extension point (`managed-settings-shield-configuration`), not from the bundle's entitlements or signature. [The shield repair variant note](shield-repair-variant.md) has the discriminator: the same code, entitlements and container run under the shield action extension's `plugin` profile with file access permitted, and under the configuration extension's profile every file operation in the App Group container returns `EPERM`.

Two consequences worth carrying:

- The blocked screen is a **reader**. Whatever it displays has to be computed by another process and left where the profile permits it to be read.
- The shield action extension can hand an `ApplicationToken` forward through the App Group. It recorded the shielded token before returning and the app read it back on every press, on both response paths — which is how the app learns which app was shielded, since no `ShieldActionResponse` carries that identity.

## DeviceActivity scheduling

### `nextInterval` reads a schedule back without registering it

`DeviceActivitySchedule.nextInterval` is a property on the schedule value, not on a registered activity. It resolves with no authorization, no registration and no device — measured in the simulator, where authorization is impossible and every schedule read below was resolved anyway.

That makes it the instrument for schedule questions: what the system believes a schedule means can be read back directly as a `DateInterval`, instead of being inferred from when a callback happens to arrive. For schedules that *are* registered, `DeviceActivityCenter.schedule(for:)` and `.activities` report what is on file.

### Schedule validation runs before the authorization check

Measured in the simulator, 2026-08-13. `startMonitoring` was called with one-shot intervals of descending length, catching `DeviceActivityCenter.MonitoringError` on each and continuing:

```
16 min → unauthorized
15 min → unauthorized
14 min → intervalTooShort
10 min → intervalTooShort
 5 min → intervalTooShort
 2 min → intervalTooShort
```

Every one of those calls was unauthorized, yet the short ones came back `intervalTooShort` rather than `unauthorized`. The schedule is validated before authorization is consulted, which is why schedule-shape questions can be answered on a simulator that cannot authorize at all. Nothing registered, so no activity was left behind.

### The interval floor sits between 14 and 15 minutes; the ceiling is one week

The descending walk was repeated on device, authorized, 2026-08-14: 16 and 15 minutes accepted, 14, 10, 5 and 2 refused with `intervalTooShort`. **The floor is not an artifact of the unauthorized path** — the same boundary appears where registration actually succeeds.

Apple's discussion of [`MonitoringError.intervalTooShort`](https://developer.apple.com/documentation/deviceactivity/deviceactivitycenter/monitoringerror/intervaltooshort) reads "The minimum interval length for monitoring device activity is fifteen minutes", and [`intervalTooLong`](https://developer.apple.com/documentation/deviceactivity/deviceactivitycenter/monitoringerror/intervaltoolong) gives the other end: "The maximum interval length for monitoring device activity events is one week". The floor is measured and documented; the one-week ceiling is documented only — no interval near it has been registered here.

### A weekday mask resolves to the weekday it names

Measured in the simulator on Thursday 2026-08-13 at 13:26. Seven schedules, each naming one weekday in both `intervalStart` and `intervalEnd`, 09:00 to 17:00, `repeats: true`:

```
weekday 1 → Sun 2026-08-16 09:00:00 → Sun 2026-08-16 17:00:00 (480 min)
weekday 2 → Mon 2026-08-17 09:00:00 → Mon 2026-08-17 17:00:00 (480 min)
weekday 3 → Tue 2026-08-18 09:00:00 → Tue 2026-08-18 17:00:00 (480 min)
weekday 4 → Wed 2026-08-19 09:00:00 → Wed 2026-08-19 17:00:00 (480 min)
weekday 5 → Thu 2026-08-13 09:00:00 → Thu 2026-08-13 17:00:00 (480 min)
weekday 6 → Fri 2026-08-14 09:00:00 → Fri 2026-08-14 17:00:00 (480 min)
weekday 7 → Sat 2026-08-15 09:00:00 → Sat 2026-08-15 17:00:00 (480 min)
```

A weekday component in a `DateComponents` is honoured rather than ignored: every mask lands on the day it names, at the times it names. Weekday 5 is the day the read happened on, and it resolved to *that* day's 09:00–17:00 — an interval already several hours under way when it was read. **`nextInterval` reports an interval that is already running rather than skipping to the next week's occurrence.**

### Open: does one schedule span several weekdays?

Whether a single schedule whose `intervalStart` and `intervalEnd` name *different* weekdays covers one continuous multi-day interval, or a per-day mask repeated on each weekday in between, is not measured.

The device evidence leans towards the continuous span. A schedule running weekday 2 09:00 to weekday 6 17:00 reported `intervalDidStart` at 18:37 on a Wednesday. Because that callback tracks the interval rather than the registration (below), its arrival means the moment sat inside the schedule's interval — which a continuous Monday-to-Friday span contains and a per-day 09:00–17:00 mask does not. That is one observation reasoned from a second finding, not a direct reading.

The experiment that settles it outright: resolve `nextInterval` on a single schedule whose start names weekday 2 and whose end names weekday 6, and read whether the returned `DateInterval` runs Monday to Friday or covers one day. It needs no authorization, no registration and no device, and is a minute's work in a probe.

## Callback semantics

### `intervalDidStart` tracks the interval, not the `startMonitoring` call

Measured on device, 2026-08-14, authorized. A one-shot 16-minute interval was registered 43 seconds before its named start:

```
08:56:16.845  app      interval16 — registered
08:57:02.822  monitor  intervalDidStart — interval16
09:13:03.023  monitor  intervalDidEnd — interval16, +3.0s against its named end
```

The start callback arrived at the interval's start — 46 seconds after the `startMonitoring` call, not milliseconds after it. This run is the discriminator: every schedule registered before it had the current moment already inside its interval, so "fires on registration" and "fires when the interval begins" made identical predictions. Here they differ, and the interval wins. (The end callback landed 3.0s after the instant the schedule named.)

Registering a schedule whose interval is already under way therefore still produces an immediate `intervalDidStart` — the interval has begun, as far as the system is concerned. `stopMonitoring` behaves symmetrically: it is followed by `intervalDidEnd` within milliseconds, seen across six start/stop pairs on one activity and again when a rebuild tore an activity down.

The corollary is what a monitor has to be written against: **an immediately arriving `intervalDidStart` or `intervalDidEnd` says nothing about whether a session began or expired.** The handler checks interval membership itself; it cannot read the callback as "the window just began" or "the window just ended".

### `intervalWillStartWarning` fires at registration when its moment has already passed

Measured on device, 2026-08-14. A 15-minute interval carrying a 12-minute `warningTime`, registered about 55 seconds before its start:

```
09:34:05.5  app      warning3 — asked 09:35:00 → 09:50:00, warning 12 min before end
09:34:05.5  app      warning3 — expecting the monitor at 09:38:00
09:35:02.2  monitor  intervalDidStart — warning3
09:38:03.0  monitor  intervalWillEndWarning — warning3, +3.0s against its named end
```

`intervalWillStartWarning` arrived at registration, 55 seconds before the interval's 09:35:00 start. A 12-minute start-warning on an interval that begins in under a minute points into the past, and a warning whose moment has already passed fires immediately.

It is a separate callback from the end warning, so it costs nothing on its own — but **a monitor must key on *which* warning arrived, not on a warning arriving.**

## ManagedSettings: tokens, limits and the shield surface

### `tokensDidExpire` exists in the SDK and has never been seen to fire

`ManagedSettingsStore.TokenExpiryMessage` (iOS 26.5) is declared:

```swift
extension ManagedSettingsStore {
  public struct TokenExpiryMessage: NotificationCenter.AsyncMessage {
    public typealias Subject = ManagedSettingsStore
    public static var name: Notification.Name
  }
}
// observed via the identifier `tokensDidExpire`
```

An observer ran on device across three launches, including two reinstalls, 2026-08-12 to 08-13. `tokensDidExpire` never arrived.

**Nothing was established about the notification.** The shield applied and the shield's primary button worked after both reinstalls, so the tokens were still valid and there was no expiry to report — the trigger never occurred, so the observer was never tested. Whether the notification fires on a reissue, and whether it names which tokens expired, remains unmeasured.

The null result does carry one thing, mildly: it is evidence *against* reinstalling being a reliable trigger for a token reissue. Two reinstalls, no reissue.

### The shield's secondary button can carry a submenu

Inferred from the SDK, never run. `ManagedSettingsUI`'s interface file declares:

```swift
@available(iOS 26.4, *)
public let secondaryButtonSubmenuItems: [String]?
```

on `ShieldConfiguration`, paired with `ShieldAction.firstSecondarySubmenuItemPressed`, `.secondSecondarySubmenuItemPressed` and `.thirdSecondarySubmenuItemPressed` — so up to three named items, each with its own action case. Nothing here has displayed one, and how the submenu presents is unknown. What it settles is that the shield template is less fixed than "icon, title, subtitle, two buttons" implies.

### Reported limits, none verified here

Undocumented by Apple, widely reported, and **not measured on this device** — nothing here has approached any of the three. Recorded as raw numbers only:

| Limit | Reported value | Reported failure mode |
|---|---|---|
| Tokens per `ManagedSettingsStore` | 50 | silent |
| Named `ManagedSettingsStore`s | 50 | silent |
| Monitored activities | 20 | throws `excessiveActivities` |

`excessiveActivities` is a declared case of `DeviceActivityCenter.MonitoringError`, so the error is real; it is the ceiling of 20 that is unverified. The other two limits carry no signal at all if the report is accurate, which is the thing that makes them worth knowing rather than discovering.

## Launch handoff and shield persistence

**`ShieldActionResponse.openParentalControlsApp` brings the containing app forward in 0.5–0.6 s.** Measured on device across five presses and two builds, 2026-08-12 and 08-13: 0.5, 0.5, 0.5, 0.6, 0.5 seconds. For comparison, a notification bounce measured 7.5 s on the same device minutes apart — most of that the user noticing and tapping the notification, so it is the friction the bounce adds rather than a delay in any API.

**The shield survives behind the app that was opened.** Switching straight back to the blocked app shows the shield, and so does force-quitting the blocked app and opening it fresh. In this respect `.openParentalControlsApp` behaves as `.defer` does. Measured across the same five presses.

**A URL-scheme handoff wins the race against the shield.** `instagram://` opened 1.6 s after the token was removed from the store, with no shield reappearing on the race. Measured on device, iPhone 16 Pro / iOS 26.6.
