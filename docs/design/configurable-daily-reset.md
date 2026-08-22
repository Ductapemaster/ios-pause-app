# Configurable daily reset

The daily reset is fixed at midnight. This makes it a setting, on a fifteen-minute grid, applying to all seven days.

## Terms

- **Daily reset** — the moment each day when every app's session count returns to zero.
- **Allowance day** (code: `logicalDay`) — the stretch between one daily reset and the next. A session is charged to the allowance day it began in.
- **Session** — one granted period of access to a restricted app.
- **Deferred change** — a settings edit that would permit more app use waits for the next reset; one that permits less applies at once. This is what stops the allowance being edited around within a day.
- **Monitored activity** (Apple's `DeviceActivity`) — a registration asking iOS to wake the app at a scheduled time. Pause holds one for the reset, plus one per open session.

## What changes

One global setting: the time of day the reset happens, on a fifteen-minute grid — ninety-six positions from 00:00 to 23:45. It applies to all seven days.

The default is 00:00, which is what the app does today, so an install that never touches the setting sees no change in behaviour.

## Seven days, one time

The product requirements previously offered a weekday/weekend split, and the Phase 2 gate promised one. Both are withdrawn here rather than deferred: the split was the only thing that made an allowance day something other than one civil day long, and carrying it meant a stored shape that could hold states the screen could not produce, a longer editing screen, and one monitored activity per weekday instead of one in total. A single time keeps every allowance day the length of the civil day it begins on and leaves the activity budget free for the blocking periods that follow in their own effort.

## The allowance day

`LogicalDay.containing` takes the reset minute and answers one question: which allowance day does this instant belong to? The answer is the civil date of the most recent reset at or before that instant — so before the reset time, an instant belongs to yesterday's date.

Labelling by the starting date rather than storing the period's bounds is what keeps this a change to one function. `CalendarDay` keeps its shape, every stored per-app record stays readable, and no migration is needed. With one reset time for all days the label never misleads: each allowance day begins on the date it is named for and tracks that civil day — twenty-three or twenty-five hours across a daylight-saving change, because the boundary moves by elapsed seconds while `DailyResetScheduler` names a wall-clock time. Twice a year the wake and the boundary are an hour apart, which the idempotent repair path below absorbs.

## Which reset time defines the day

The reset time lives in the configuration, and deciding which configuration is in force needs the allowance day, which needs the reset time. The circle breaks on one rule: **the effective document's reset time defines the allowance day.**

That rule is not arbitrary. A reset change applies the moment it is saved, so the effective document always carries the current one. In the single case where a reset change is deferred — travelling with a tightening edit, the known limit below — the old reset governs until the scheduled change lands, which is what a deferred change is supposed to mean.

Mechanically this stays in one place. `ConfigurationFile` gains `inForce(at:calendar:)`, taking an instant rather than a day: it reads its own effective settings, resolves the allowance day, and then selects. Every caller that today computes a day and passes it in switches to passing the instant, so no component outside this type ever handles a reset minute.

## Storage compatibility

`GlobalSettings` gains a field, and files written by the current build do not carry it. Decoding therefore supplies `0` — midnight — for a missing value, so an existing install reads back exactly the behaviour it already has. This is the only compatibility step the change needs: `CalendarDay` and every per-app runtime record keep their shape.

## Applying a change

A reset-time change takes effect the moment it is saved. It does not defer.

**This is a deliberate loosening of the guarantee, not an oversight.** Session counts roll over whenever the allowance day's label changes (`RuleRuntime.rollOver`), and that test asks whether the label differs, not whether it is later. Moving the reset in either direction therefore relabels the period in progress and returns the day's session count to zero. Setting the reset to a few minutes from now and waiting is a way to refill the allowance, so the daily cap is advisory rather than enforced.

Accepted for what it saves: judging whether a reset-time change permits more use means reasoning about where the boundary lands relative to now, which is the fiddliest comparison in the settings and exists only to serve a case the user has to deliberately set out to reach. A guard is available later at the cost of one word — `rollOver` refusing to roll backwards — which would keep immediate application while stopping a relabel from handing back sessions.

## Waking up at the reset

`DailyResetScheduler` registers one repeating monitored activity whose interval begins at the reset. Today that is `00:00` to `23:59`, a schedule that stays inside one civil day. A reset at any other time makes the interval wrap past midnight, and iOS resolves a wrapping `intervalStart`/`intervalEnd` pair as the ~24-hour interval it names: a schedule with `intervalStart` at 06:00 and `intervalEnd` at 05:59 read back through `DeviceActivitySchedule.nextInterval` as a 23h59m span beginning at 06:00, the same shape a same-day control schedule resolved to — measured in the simulator, where `nextInterval` resolves on the schedule value itself with no authorization, no registration and no device ([the platform evidence note](../research/screen-time-platform-evidence.md) records the reading and the instrument). The primary implementation was used; the midnight-anchored fallback was not needed.

The risk fails safe whatever the answer. Reset reconciliation is idempotent and also runs whenever Pause opens, which is already the repair path for a phone that was switched off at the reset. A wrap that iOS refuses to honour costs a reset that lands late, not one that never lands.

## Known limits

**A reset change can be delayed by the edit it travels with.** Global settings are judged as one unit when deciding what defers, so a reset-time change saved in the same edit as a shortened pause countdown is deferred along with it. Splitting settings into two independently judged units would fix it and costs more than it buys; the failure delays a change rather than granting access early.

**A reset change drops a scheduled pause-duration change.** Settings are judged as one unit, so choosing a reset builds a candidate whose pause countdown is the one in force and the save replaces the whole unit. What is discarded is a deferred *shortening* of the countdown, so the pause stays as long as it was rather than shortening early.

**Fifteen-minute granularity needs a plain picker.** SwiftUI's `DatePicker` exposes no minute-interval setting, so the reset time is chosen from a list of the ninety-six valid positions rather than a time wheel. The stored value is a minute of the day, validated as a multiple of fifteen within range, so a value off the grid cannot reach disk.

## Testing

Boundary math is pure and belongs in `PauseCore`: an instant before, exactly at, and after the reset; the crossings at month end, year end, and a leap day; and a reset of 00:00 continuing to behave exactly as the current build does.

`GlobalSettings` rejects a reset minute that is out of range or off the fifteen-minute grid, alongside the existing pause-seconds validation.

The schedule probe settles the wrap question: a wrapping `intervalStart`/`intervalEnd` pair resolves to the ~24-hour interval it names, and the reading is in the platform evidence note.

One device check closes it: move the reset, and confirm the session count renews at the new time rather than at midnight.

## Out of scope

Blocking periods — the recurring stretches when an app cannot be entered at all — are the other half of the Phase 2 gate and are their own effort, designed separately. Nothing here depends on them, and keeping the reset change alone means a working phone between the two.
