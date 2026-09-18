# Pause App Design

## Terms

- **Rule** — the session allowance and session length attached to one app selected through Apple's picker.
- **Pause** — the foreground-only countdown that must finish before a session can begin.
- **Session** — a fixed wall-clock grant to enter one restricted app. Its time continues whether or not that app remains in use.
- **Window** — a recurring period when a rule refuses new sessions. A window does not shorten a session already granted.
- **Allowance day** (code: `logicalDay`) — the period between one configured daily reset and the next. Session allowances renew at its start.
- **Launch route** — an optional public URL that lets Pause return to a selected app automatically. Selection and enforcement do not depend on one.

## Goal

Pause interrupts reflexive entry into selected distracting apps, then limits how many entries are available in each allowance day. The smallest useful product is the complete action loop: blocked app, deliberate foreground pause, fixed session grant, and automatic re-blocking at expiry.

This is a personal app for one iPhone. It is not designed for the App Store, a second user, or another device.

## Scope

The current effort has three phases:

1. Build the core action loop with arbitrary app selection, independent per-app rules, a global pause duration, Instagram automatic return, manual return for other apps, and expiry enforcement.
2. Add daily reset times and per-app blocking windows without changing the session model.
3. Harden failures actually observed on the device and qualify the app on iOS 27.

Session history is a roadmap question, not a current feature. The product keeps no usage-minute analytics, trends, streaks, exports, dashboards, or permanent behavioral event model.

## Requirements Reconciliation

The product requirements remain the source of product behavior, with these approved refinements:

- Apple's picker may select any eligible installed app. Apple's label and icon identify it; there is no separate hand-maintained display-name list.
- Automatic return is independent of selection and enforcement. Instagram has the first launch route. Apps without a supported route receive a manual-return instruction after the grant.
- The pause advances only while Pause is active. Leaving the foreground, locking the phone, or interrupting the flow abandons the attempt and consumes no session.
- Every day resets at the same time, on a fifteen-minute grid, applying to all seven days. There is no weekday/weekend split.
- History is deferred to the roadmap so the implementation stays centered on behavior modification through the action loop.

"Immediately" at session expiry means the system-driven callback rather than zero latency. The old device spike measured the callback about three seconds after the named expiry; Phase 1 rechecks the behavior through the product flow.

## Reuse Boundary

The old `ios-pause-app-claude` repository is an evidence library, not the architecture of record. Reuse is allowed only when a component directly implements the current phase, has tests or recorded device evidence, is simpler to adapt than rebuild, and brings no speculative flexibility or unrelated feature surface.

Reuse or narrowly adapt:

- XcodeGen target and entitlement wiring for the app, shield configuration extension, shield action extension, device activity monitor extension, and pure Swift test target.
- Multiple-token persistence from `FamilyActivityPicker`.
- The shield action's token handoff through the App Group followed by `.openParentalControlsApp`.
- The pure session decision, allowance, open-session, and time-math concepts with only the tests that still prove current behavior.
- The measured session-expiry mechanism: a one-shot `DeviceActivitySchedule`, extended to the platform's fifteen-minute floor with `warningTime` carrying a shorter product session.

Do not carry forward:

- The spike UI, spike logs, notification workaround, or old source tree as a unit.
- A required hand-entered `AppIdentity` or URL scheme on every rule.
- Speculative activity-budget prediction, token-expiry heuristics, system-usage reporting, legacy-file migrations, or unused generality.
- The old single shared state file, whose atomic write prevents partial data but does not establish cross-process transaction safety.

## Components

The app has five units with narrow responsibilities:

- **Main SwiftUI app** — requests individual Family Controls authorization; presents Apple's picker; edits rules and global settings; runs the pause; grants sessions; and performs optional automatic return.
- **`PauseCore`** — pure Swift rules, allowance accounting, open-session state, reset math, and window containment. It imports no Screen Time framework and reads neither the clock nor storage directly.
- **Shield configuration extension** — renders Apple's app identity, the prospective session count, or one refusal reason. It reads shared state and does not write product state.
- **Shield action extension** — records the tapped `ApplicationToken` as the latest shield intent and returns `.openParentalControlsApp`.
- **Device activity monitor extension** — reconciles open sessions against the current time and reapplies the correct shield set at session expiry and, in Phase 2, schedule boundaries.

There is no Device Activity report extension. Real usage minutes do not feed a requirement.

## Data Model

`PauseCore` keeps platform tokens outside the rule itself:

```text
AppRule
  id: UUID
  sessionsPerDay: Int
  sessionLengthMinutes: Int
  windows: [Window]                 // Phase 2; empty in Phase 1

GlobalSettings
  pauseSeconds: Int
  resetMinuteOfDay: Int             // Phase 2; 0 (midnight) in Phase 1

RuleRuntime
  logicalDay: CalendarDay
  sessionsStarted: Int
  openSession: OpenSession?

OpenSession
  activityName: String
  expiresAt: Date
  state: provisional | active

RuleTarget
  ruleID: UUID
  applicationToken: ApplicationToken
  launchRoute: LaunchRoute?         // Instagram first; nil is valid
```

Apple's token provides the display surface through its system label and icon. A rule remains valid without a launch route.

Each rule gets its own small runtime record. The main app updates a rule when it grants or rolls over a session; the monitor clears that rule's expired session.

Shared App Group state is split by ownership:

- Configuration and target mapping: written by the main app; read by every component.
- One runtime record per rule: written by the main app for grants and by the monitor for expiry reconciliation.
- Latest shield intent: written by the shield action extension and consumed by the main app.

Every app and extension process coordinates shared state through one App Group lock file, `pause-state-v1.lock`. Darwin `flock` provides cross-process exclusion, and a process-local recursive lock allows storage methods to nest inside a larger transaction without deadlocking. The same lock covers configuration and runtime reads and writes, failed-grant markers, and Managed Settings shield snapshots and changes.

A compound operation holds the lock from its initial read through its final runtime, marker, monitoring, and shield decision. Session preparation includes activity registration, provisional runtime reservation, selected-app unshielding, and any synchronous rollback or stop repair; the lock is released before an external app launch. Monitor callbacks use the same lock, so a callback observes either the state before preparation or the stored new expiry, never the gap between registration and reservation. Framework calls that synchronously reenter on the same thread can take the recursive lock; cross-thread callback behavior during `startMonitoring` and `stopMonitoring` remains part of the signed-device gate.

Lock acquisition waits are bounded. The request is non-blocking, retried against a two-second deadline on a monotonic clock, and fails with `ETIMEDOUT` — well inside the ten-second scene-update watchdog, so contention becomes an error a caller can report rather than a kill. Contention is the only condition retried; a descriptor-level failure surfaces at once. Lock acquisition and transaction-body failures remain visible to the caller. Once the body has completed, unlock and file-descriptor close are best-effort cleanup: reporting a release failure as a failed transaction would invite a retry or rollback after shared state had already committed. The implementation still attempts both operations, and closing the descriptor releases the kernel lock if explicit unlock failed.

JSON files still use atomic replacement inside the transaction so a process interruption cannot leave a partial document. Product state does not use `UserDefaults` except for the narrow shield intent whose action-extension write was measured on device in the old spike.

JSON files under one lock are the settled storage design, not an interim one. SQLite was weighed and declined: its write-ahead journal coordinates through cross-process shared memory, which interacts badly with iOS file protection while the device is locked — precisely the situation the monitor and shield extensions run in. That is a live hazard traded for correct locking and real transactions, which this design already approximates by holding one lock across a compound operation, and it would add a schema and migrations to carry. The decision stands unless a failure appears that files under a lock cannot address.

## Core Entry Flow

1. Opening a restricted app shows the custom shield. The shield names the app using Apple's metadata and shows which session would be granted next.
2. Continue makes the action extension write the token and return `.openParentalControlsApp`. The selected app stays shielded behind Pause.
3. Pause matches the token to its rule and evaluates the rule. A blocked window or exhausted allowance refuses entry with one reason. Otherwise the foreground-only countdown begins.
4. Leaving the active scene before the countdown finishes abandons the attempt. Pause clears the intent and creates no session state.
5. Use registers the expiry activity before changing the shield. A registration or persistence failure leaves the target blocked and consumes no session.
6. Pause writes a provisional session and reserves one allowance, removes that token from the shield set, then attempts the launch route when one exists.
7. A successful automatic handoff marks the session active. An explicit launch failure rolls back the allowance and session, stops monitoring, and reapplies the shield. If the process ends after unshielding but before receiving the callback, recovery treats the provisional session as active and charged; this fails toward preserving the limit rather than granting unbounded access.
8. Without a launch route, Use completes the grant and presents a manual-return instruction. The button is the successful start because iOS exposes no public operation that opens an arbitrary `ApplicationToken`.
9. At expiry, the monitor checks the stored `expiresAt`, reconstructs shields from configured targets minus still-open sessions, reapplies them, and clears the expired session.

The monitor treats every callback as a prompt to reconcile, not proof that a particular boundary has passed. The main app performs the same reconciliation on launch. This repairs missed or duplicated callbacks the next time either component runs.

## Session Expiry

Sessions use wall-clock schedules, never usage thresholds:

- For a session of at least fifteen minutes, register a one-shot interval ending at `expiresAt`; `intervalDidEnd` prompts reconciliation.
- For a shorter session of length `L`, register a fifteen-minute interval with `warningTime` equal to `15 - L` minutes; `intervalWillEndWarning` prompts reconciliation at the product expiry.
- The monitor compares `Date()` with the stored expiry before acting. Registration, teardown, or early-warning callbacks cannot end a session early.
- After a short-session warning, the monitor attempts to stop that activity. If iOS keeps the interval registered until its fifteen-minute end, correctness is unchanged; only one activity slot remains occupied longer.

Phase 1 repeats the old three-minute and sixteen-minute device checks through the product flow. A callback arriving within five seconds of the named expiry passes; any later than thirty seconds blocks the phase.

## Daily Resets and Windows

The reset is a setting, on a fifteen-minute grid, applying to all seven days, defaulting to midnight — [its own design](configurable-daily-reset.md) carries the detail. An instant belongs to the period beginning at the most recent reset: today's if that time has passed, otherwise yesterday's, so every allowance day runs the length of the civil day it begins on. A session is charged to the allowance day in which it began and stays open across the next reset.

A window has a start time, end time, and weekday set. Its start is inclusive and end exclusive. An overnight window's weekday names the day on which it begins.

Windows gate entry only. When a window begins, the monitor shields targets without open sessions; a session granted before the boundary remains unshielded until its own expiry. One weekly activity is registered per selected weekday for each distinct window. Registration errors are surfaced rather than predicted with a speculative capacity model.

## Failure Behavior

All enforcement failures bias toward keeping the target blocked:

- Authorization not approved: show setup state; do not create rules or claim enforcement.
- Rule or token missing for a shield intent: keep the shield and show a recoverable error in Pause.
- Rule decision refused: keep the shield and show the window or allowance reason.
- Expiry registration failed: keep the shield and consume no session.
- Provisional-state persistence failed: keep the shield and consume no session.
- Automatic route failed explicitly: roll back the provisional grant and re-shield.
- Runtime record corrupt or unreadable: keep the affected target shielded and expose a repair action; never silently reset its allowance.
- Selection token no longer works: ask for re-selection when the failure is observed. Do not build a heuristic detector before a reproducible signal exists.

Removing a rule intentionally removes its shield, stops its monitored activities, and deletes its runtime. Editing a rule never changes the length or accounting of a session already open.

## Testing

Pure behavior uses XCTest in the simulator:

- Allowance counting and independent rules.
- Fixed session length and expiry comparison.
- Foreground pause cancellation as an app-state reducer.
- Provisional grant commit and rollback.
- Daily rollover under a configured reset time.
- Same-day, overnight, reset-crossing, daylight-saving, and time-zone window cases.
- Sessions surviving reset and window boundaries.
- Atomic state round trips and visible corrupt-state failures.

Screen Time behavior is physical-device-only. Each phase has a written acceptance run on the iPhone 16:

- Authorization, multiple app selection, persistence, shield application, and rule removal.
- Shield intent to Pause, repeated Continue presses, foreground interruption, and refusal reasons.
- Instagram automatic return plus a manual-return target.
- Three-minute and sixteen-minute expiry, main-app termination during a session, and launch reconciliation after a missed callback.
- Phase 2 reset and window boundaries on both sides of their configured minute.

Old tests are ported only with the behavior they still prove. Temporary probes are deleted once their question is answered; the product does not retain a diagnostics feature.

## Phase Gates

### Phase 1 — Core Action Loop

Phase 1 is complete when the product UI can select multiple arbitrary apps, configure each rule, enforce the foreground pause, grant independent fixed sessions, return automatically to Instagram, support manual return elsewhere, refuse exhausted allowances, and re-shield at expiry on the physical phone. Midnight is the daily reset. No history or windows are present.

### Phase 2 — Time-Based Rules

Phase 2 is complete when the daily reset is configurable to any fifteen-minute position, applying to all seven days, rules support multiple blocking windows, and active sessions survive both kinds of boundary. The time-math test matrix and physical-device boundary checks pass.

### Phase 3 — Observed Resilience and iOS 27

Phase 3 addresses authorization loss, stale selections, reboot recovery, corrupt state, and interrupted grants only through failures reproduced during Phases 1 and 2. After iOS 27 is released, the complete device checklist runs again. Compatibility code is added only where the run exposes a regression.

## Roadmap

Explore whether basic session history improves behavior modification enough to justify a product feature. The decision starts from the user question it would answer, not from the availability of events to store.

## Constraints

- Deployment target: iOS 26.5 or later; iPhone only.
- Development environment: Xcode 27.0 (iOS 27.0 SDK) and Swift 6.
- Public APIs only. No private framework calls or extension-launch workarounds.
- Physical-device checks use the personal iPhone; the simulator cannot establish Screen Time behavior.
- No App Store distribution, onboarding, sharing, subscriptions, minute-based limits, usage-metered sessions, earn-back challenges, or accountability features.
