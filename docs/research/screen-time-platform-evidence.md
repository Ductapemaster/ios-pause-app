# What the Screen Time frameworks actually do

Measured behavior of `FamilyControls`, `ManagedSettings`, `ManagedSettingsUI` and `DeviceActivity`, kept in one place so the same questions are not re-derived every time the enforcement layer is touched. Apple documents little of this and some of it contradicts what the names suggest.

Every entry names how it was established. Anything that was not run says so — an inference from a declaration is marked as one, and a null result is stated as a null result rather than dressed up as a finding.

Three rigs stand behind everything below:

- **Device** — iPhone 16 Pro, iOS 26.6, Family Controls authorized. Runs of 2026-08-12, 08-13, 08-14 and 08-24.
- **Simulator** — iPhone 17 Pro, iOS 26.5, unauthorized. Runs of 2026-08-13 and 08-23. The frameworks do not function there: authorization never completes (below) and the picker shows categories with no apps. Some questions are answerable anyway — see the validation ordering below. iOS 26.5 is the newest simulator runtime this toolchain has: Xcode 26.6 ships the iOS 26.5 SDK, and `xcodebuild -downloadPlatform iOS -buildVersion 26.6` answers "iOS 26.6 is not available for download", so the simulator sits one minor version behind the device.
- **SDK reading** — `.swiftinterface` files shipped with Xcode 26.6, under `.../SDKs/iPhoneOS.sdk/System/Library/Frameworks/<framework>.framework/Modules/<framework>.swiftmodule/arm64e-apple-ios.swiftinterface`. Never executed. What a declaration does is inference; the name is suggestive, not evidence.

## What the simulator can and cannot exercise

Measured 2026-08-23, iPhone 17 Pro / iOS 26.5, from a probe running inside the app's own bundle so it carries the app group entitlement. Each surface was tried independently, so one refusal does not hide the next answer.

| Surface | Result |
|---|---|
| App group container — write then read | ok |
| `ApplicationToken` decoded from JSON, as the unit tests mint one | ok |
| `ManagedSettingsStore` — category shield written, read back, read back through a second handle, cleared | ok |
| `ManagedSettingsStore` — application shield set to a synthetic token | **silently dropped**, reads back as an empty set |
| `DeviceActivitySchedule.nextInterval` | resolves |
| `DeviceActivityCenter.startMonitoring`, 16-minute interval | throws `unauthorized` |
| `DeviceActivityCenter.startMonitoring`, 3-minute interval | throws `intervalTooShort` |
| `DeviceActivityCenter.activities` | empty |
| `AuthorizationCenter.authorizationStatus` | `notDetermined`, and the request never completes (above) |

Two things are worth separating here. **`ManagedSettingsStore` is not broken in the simulator** — a category shield writes, survives a second handle on the same named store, and clears. What fails is the token: assigning a fabricated `ApplicationToken` leaves the set empty, so the store accepts the write and keeps nothing. A real token comes only from the picker, and the picker needs an authorization that never completes.

That is the wall, and it is one wall rather than several. Everything that does not need a real token or a registered activity runs in the simulator: the rules engine, the runtimes, the JSON stores, the app group file lock and its contention, reconciliation ordering, and the shield's decision logic. Everything downstream of a token — a rendered shield, a shield button press, a `DeviceActivity` callback, and therefore any of the three extensions, which only launch when the system has a shield or an activity to hand them — is device-only. That last step is reasoned from the measurements above rather than attempted directly.

## Authorization presents its consent alert in the simulator and then never completes

Measured 2026-08-23, iPhone 17 Pro / iOS 26.5, through the app's own authorization gate driven by a UI test.

`AuthorizationCenter.shared.authorizationStatus` reads `notDetermined`, and `requestAuthorization(for: .individual)` presents the genuine system alert — `"Pause" Would Like to Access Screen Time`, offering Continue and Don't Allow. Tapping Continue leaves the app on its authorization gate, no error is presented, and a relaunch shows the gate again. The same call from a hosted unit test, where nothing exists to tap the alert, ran past a two-minute allowance without returning.

**The call does not fail — it does not come back.** That distinction matters for anything written against it: a caller waiting on `requestAuthorization` in the simulator waits forever rather than taking an error path. What holds the request open is not established; that it is still open is, from the gate's unlabelled button and the absent error.

This supersedes the earlier reading of "authorization fails", which named an error path that was never observed.

## The shield configuration extension's sandbox

**Reads from the App Group succeed inside the shield configuration extension — both its files and shared preferences. Writes do not land.** Measured on device, 2026-08-12, 08-13 and 08-20.

The read was proven directly rather than inferred from an absence. The instrument was a tap counter held in the App Group's `UserDefaults` suite: the shield *action* extension increments it when the shield's primary button is pressed, and the *configuration* extension reads it and renders it into the shield's subtitle. Across five presses the rendered number climbed, so the configuration extension read back a value written by a different process.

Writes behave the other way, and not intermittently — on every render, across a session in which the shield action and monitor extensions wrote to that same suite normally, nothing the configuration extension wrote ever appeared.

A refused write reads back as a successful one inside the same process, which is how this gets mis-measured. `UserDefaults.set` updates the process's own cache before the write is rejected, so a counter incremented and read back within one render climbs exactly as it would if the write had landed — and the extension process outlives individual renders, so it keeps climbing across several. Re-measured 2026-08-24: a counter rose 0 through 6 over renders spanning three minutes while the main app, reading the same key, saw `nil` throughout. The only reliable instrument is a second process reading the value, or the extension process restarting; a same-process read-back proves nothing.

The denial comes from the sandbox profile iOS assigns the shield configuration extension point (`managed-settings-shield-configuration`), not from the bundle's entitlements or signature. [The shield repair variant note](shield-repair-variant.md) has the discriminator: the same code, entitlements and container run under the shield action extension's `plugin` profile with file access permitted, and under the configuration extension's profile every file operation in the App Group container returns `EPERM`.

Two consequences worth carrying:

- The blocked screen is a **reader**. Whatever it displays has to be computed by another process and left where it can read it — which includes the container's own files, as long as nothing on the path takes the state lock, since `open(O_CREAT|O_RDWR)` on the lock file is itself a write.
- The shield action extension can hand an `ApplicationToken` forward through the App Group. It recorded the shielded token before returning and the app read it back on every press, on both response paths — which is how the app learns which app was shielded, since no `ShieldActionResponse` carries that identity.

## The monitor extension's sandbox

**File operations in the app group container succeed inside the DeviceActivity monitor extension.** Measured on device, 2026-08-20. This is the opposite of the shield configuration extension's result above, against the same container from a sibling bundle.

The instrument was `AppGroupSandboxProbe`, removed once this question was settled and recoverable from git history. It ran the sequence `AppGroupFileLock` depends on — `open(O_CREAT|O_RDWR|O_CLOEXEC)`, `flock(LOCK_EX)`, `write`, `flock(LOCK_UN)` — against a file of its own, and named the step and the errno of a refusal rather than the fact that one happened. It ran on every monitor callback ahead of any other work, so no missing configuration or unmatched rule could short-circuit it.

Four monitor readings across one three-minute session, from `sysdiagnose_2026.08.20_22-41-03-0700`:

```
22:36:50.973  monitor  intervalDidStart — daily-reset
22:36:50.974  monitor  app group file I/O permitted
22:37:14.713  action   app group file I/O permitted
22:37:36.843  monitor  intervalDidStart — session.dae32a7f…
22:37:36.843  monitor  app group file I/O permitted
22:40:39.290  monitor  intervalWillEndWarning — session.dae32a7f…
22:40:39.291  monitor  app group file I/O permitted
22:40:39.315  monitor  intervalDidEnd — session.dae32a7f…
22:40:39.315  monitor  app group file I/O permitted
```

The shield action extension's reading is the control: that extension already does container file I/O successfully, so a refusal there would have been evidence about the probe rather than about a sandbox. The other half of the control was a unit test establishing that the probe reported `permitted` only where the operations genuinely succeeded, and named the step and errno where they did not.

Across the whole run no entry at error level appeared from any `com.koubalabs.pause` subsystem, and no `SessionReconciliationIssue` was logged for any operation. The monitor reached its shield work rather than failing at the lock.

**Which sandbox profile the monitor extension point is assigned is not recorded.** The `runningboardd` extension-overlay entries that named the shield extensions' profiles are absent from this archive. The permission is measured; the profile that grants it is not, so the finding stands on behavior alone.

### `stopMonitoring` returns from inside its own callback in about 10 ms

Measured on device, 2026-08-23, with the call's entry and exit logged. From within `intervalWillEndWarning`, `DeviceActivityCenter.stopMonitoring` returned in 11 ms and the whole handler finished in 41 ms:

```
10:50:20.383  monitor  intervalWillEndWarning — begins
10:50:20.413  monitor  stopMonitoring — began
10:50:20.419  monitor  intervalDidEnd — begins on a second thread, takes the lock
10:50:20.424  monitor  intervalDidEnd — returns
10:50:20.424  monitor  stopMonitoring — returned, +0.011s
10:50:20.424  monitor  intervalWillEndWarning — returns, +0.041s
```

**What blocks is not the call.** An earlier run the same morning, from the same log archive, held the app group state lock across the call and took 31 seconds:

```
09:28:24.319  monitor  intervalWillEndWarning — begins, takes the app group state lock
09:28:24.351  monitor  intervalDidEnd — begins on a second thread, blocks on the lock
09:28:33.909  shield   action fails, POSIX 60 ETIMEDOUT, at the lock's 2s deadline
09:28:55.309  monitor  intervalWillEndWarning — returns, +30.990s
09:28:55.338  monitor  intervalDidEnd — returns, having waited out the lock
```

The two runs differ in one thing: whether the lock was still held when `stopMonitoring` was called. Released first, the stop costs 11 ms; held across it, nothing moves until the host tears the extension down.

That the stop *waits on* the sibling callback is the reading, not a measurement. What supports it: `intervalDidEnd` runs entirely inside the stop's 11 ms, and the stop returns in the same millisecond that `intervalDidEnd` does. What would settle it is a run where the sibling callback is delayed by something other than the lock.

This supersedes the earlier entry claiming the call does not return from inside a callback, which was inferred from the code path and a 2 ms gap rather than measured.

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

### A wrapping `intervalStart`/`intervalEnd` pair resolves to the ~24-hour span it names

Measured in the simulator, 2026-08-22. A schedule with `intervalStart` at 06:00 and `intervalEnd` at 05:59 — the pair `DailyResetScheduler` registers for a reset away from midnight — read back through `nextInterval`:

```
WRAPPING nextInterval: Optional(2026-08-22 13:00:00 +0000 to 2026-08-23 12:59:00 +0000)
SAME-DAY nextInterval: Optional(2026-08-22 07:00:00 +0000 to 2026-08-23 06:59:00 +0000)
```

The device's local zone was UTC-7 that day, so the wrapping schedule resolved to 2026-08-22 06:00 local through 2026-08-23 05:59 local — a 23h59m span beginning at the named start, the same shape a same-day schedule (00:00–23:59, read alongside it as a control) resolves to. Nothing here suggested the pair was rejected, inverted, or truncated. `DailyResetScheduler.register(resetMinuteOfDay:)` registers the wrapping pair directly rather than pinning `intervalEnd` to `23:59`.

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

### The padded interval end is a separate alarm, and Pause's own stop cancels it

Measured on device, 2026-08-23, from the host's log rather than from Pause's. A session registers a padded interval — `intervalEnd` set past the true expiry, with `warningTime` bringing `intervalWillEndWarning` back to it — and the DeviceActivity host, `UsageTrackingAgent`, turns that into **two named XPC alarms**, one per moment. A 5-minute session registered at 10:45:17:

```
10:45:17.317  UserEventAgent  Registering job "…UsageTrackingAgent.alarm.end-…/p913" due in 900 seconds.
10:45:17.317  UserEventAgent  Registering job "…UsageTrackingAgent.end-warning-…/p913" due in 300 seconds.
```

300 s is the expiry; 900 s is the padded interval end. **The padding works.** When the warning fires, the host still holds the end where the schedule put it, and re-subscribes to that alarm:

```
10:50:20.334  UserEventAgent      Firing event "…end-warning-…/p913" which was due 2 sec ago.
10:50:20.377  UsageTrackingAgent  (UsageTracking) Next end date is: Sun Aug 23 11:00:18 2026
10:50:20.377  UsageTrackingAgent  Subscribed to event …alarm.end-…/p913 using token 221378
10:50:20.379  UsageTrackingAgent  Notifying extension … that session.06c73ade… will end
10:50:20.413  monitor             stopMonitoring began
10:50:20.417  UserEventAgent      Received request to remove alarm "…alarm.end-…/p913" with token 221378
10:50:20.418  UsageTrackingAgent  Notifying extension … that session.06c73ade… did end
10:50:20.424  monitor             stopMonitoring returned, +0.011s
```

**`intervalDidEnd` at expiry is Pause's own doing.** The end alarm is removed 4 ms after `stopMonitoring` begins, on the token it was re-subscribed to 40 ms earlier, and the "did end" notification follows 1 ms after the removal — inside the stop, before it returns. The same sequence appears in the two earlier sessions of the day: at 09:28:24.270 the host re-armed the end alarm for 717 seconds later, and 79 ms after that Pause's stop removed it.

That the removal is caused by `stopMonitoring` rather than merely following it is a reading of the ordering — the host logs the removal, not its reason — but the order, the shared token and the 4 ms gap repeat across all three sessions.

This supersedes an earlier entry claiming both end callbacks arrive together for a short session, which read the second callback as the platform's and concluded that a padded `intervalEnd` cannot be relied on to defer `intervalDidEnd`. It can. What arrives at expiry is the echo of the stop.

The consequence for a monitor is unchanged in one respect and reversed in another: the two handlers **do** run concurrently on different threads of one process, so anything taking a cross-process lock still contends with itself — but that concurrency is something the warning handler triggers, not something the schedule imposes.

### The warning is delivered two to three seconds late

Measured on device, 2026-08-23, across two sessions. `UserEventAgent` states the slip itself — `Firing event "…end-warning-…" which was due 2 sec ago` — and the callback reaches the extension a further ~50 ms later: an expiry of 09:28:21 was delivered at 09:28:24.319, and one of 10:50:17 at 10:50:20.383.

The scheduler's five-second lateness check (`DeviceActivitySessionScheduler.register`) bounds the *representable* expiry — how faithfully the schedule can name the instant — and does not see this delivery slip, which lands on top of it. A session therefore runs two to three seconds past its stated length before the shield returns.

### The monitor extension is launched once per session, not once per callback

Measured on device, 2026-08-23. `launchd` spawned `MonitorExtension` at the session's `intervalDidStart` and the same process served the warning and the end five minutes later:

```
10:45:17.235  launchd  Successfully spawned MonitorExtension[59190] because launch job demand
```

Each callback takes a fresh RunningBoard `com.apple.extension.session` assertion against the live process rather than relaunching it. The host is `UsageTrackingAgent`, one process per install. What ends the extension's life is the host tearing it down — which is what bounded the 31-second deadlock rather than any timeout of Pause's own.

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

### A shielded app's web domain is shielded too, by a shield this app cannot configure

Shielding an `ApplicationToken` shields that app's associated web domains along with it. LinkedIn was covered as an app rule, and `www.linkedin.com` in a browser returned the system's "Restricted" screen — the Screen Time hourglass, one `OK` button, no app name and no session count. Content & Privacy Restrictions were off on the device, so nothing else on the phone asked for the block, and it tracks the rule: it is Pause's shield reaching the domain.

Pause never names a domain. `ShieldReconciler` writes `shield.applications` and nothing else — no `shield.webDomains`, no category policy. The extension of an app shield to its domains is iOS's, applied to whatever sits in the application set.

**The extension is never consulted for that shield.** Measured on device, 2026-08-24. A probe build overrode both `configuration(shielding webDomain:)` variants and `handle(action:for webDomain:)`, each logging its inputs at `.notice` and returning a title of `PAUSE PROBE`. Installed 22:52:31; `www.linkedin.com` reloaded on a killed tab and its button pressed. The screen stayed on the system's "Restricted" and the log archive holds no line from either override:

```
2026-08-24 23:41:03.121 ShieldConfigExtension [shieldconfig:shield] Shield render began
2026-08-24 23:41:03.129 ShieldConfigExtension [shieldconfig:shield] Shield resolved: 1 session left today
2026-08-24 23:41:03.129 ShieldConfigExtension [shieldconfig:shield] Shield render returned
```

Those three lines are an app shield rendering from the probe build in the same window, which is what makes the silence a finding rather than a dead install. A web-domain shield derived by association is the system's own surface: it does not reach this app's `ShieldConfigurationDataSource` for its appearance, and a press on it does not reach the `ShieldActionDelegate`.

What follows for the product is that a browser is a dead end. The shield refuses the domain, states no reason Pause chose, and offers no route into a pause or a session — the only way in is the app icon. Whether a granted session lifts the domain along with the app is not measured. The domain is shielded by association with a token a grant removes, so the association tracking that removal is the expectation, and an association applied in one direction only would leave the domain blocked through a session that is running.

**A domain shielded deliberately is a separate question, unmeasured.** `shield.webDomains` takes `Set<WebDomainToken>` and the picker's Web Domains section supplies the tokens, which `RulesView` currently discards. Whether a domain Pause puts there consults these same overrides — the case the hooks presumably exist to serve — has not been run. Nothing above bears on it.

The SDK shape, read from `.swiftinterface` and never executed, is what a design would have to work with:

```swift
public struct WebDomain {
  public let domain: String?
  public let token: WebDomainToken?
}
public typealias WebDomainToken = Token<WebDomain>
```

`WebDomain` carries a readable domain string; `WebDomainToken` is opaque, and no declaration in `ManagedSettings` maps one back to the `ApplicationToken` it was derived from. The action delegate receives the token alone, with no domain string, so the surface that would have to identify a rule is the one with least to identify it by.

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
