# Post-session cooldown

A session ends and the shield returns with its primary button live, so the app can be re-entered by pressing straight through the screen that just reported the session over. The cooldown is a stretch following a session during which no new session can start.

## Terms

- **Cooldown** — the stretch after a session ends during which that app refuses a new session.
- **Session** — one granted period of access to a restricted app. Its length is fixed when granted.
- **Daily reset** — the moment each day when every app's session count returns to zero.
- **Allowance day** (code: `logicalDay`) — the stretch between one daily reset and the next.
- **Deferred change** — a settings edit that would permit more app use waits for the next reset; one that permits less applies at once.
- **Blocking period** — a recurring stretch when an app cannot be entered at all. Phase 2, designed separately.

## What changes

One global setting: the cooldown length in minutes, from 0 to 10, applying to every covered app. It runs per app — finishing an Instagram session cools down Instagram, and the other covered apps are unaffected.

The cap is 10 because the cooldown's job is to break the reflex at the moment it is strongest, when the shield has just returned and the reflex is to press through it. Spacing sessions across a day is a blocking period's job, and Phase 2 covers that with a schedule the monitor can wake on.

The default is 0, which switches the feature off, so an install that never touches the setting behaves exactly as it does today.

## Why a cooldown rather than a re-entry rule

The rule this replaces — leave the app and come back before starting again — is not expressible. It needs a mark that the user's own action clears, so it depends on the shield action extension running, and dismissing the shield by swiping the app away runs nothing. The shield configuration extension cannot clear the mark itself: its sandbox refuses every write in the App Group container.

A cooldown asks only whether a moment has passed, which the configuration extension answers from a stored timestamp and its own clock. Nothing has to run for a cooldown to end.

## The check

The cooldown is one guard in `RulesEngine.decision`, after the allowance guard:

1. A session is already open — refuse.
2. The allowance is spent — refuse.
3. The cooldown has not elapsed — refuse.
4. Allowed.

Its position is not a display preference between two refusals that both apply. A cooldown is meaningless for an app with no sessions left, so the question only arises once a session is available to start. That also settles what the daily reset does to a cooldown in progress without any handling of its own: the reset returns the allowance, which makes the cooldown question live again, and the same stored timestamp answers it.

`RulesEngine.decision` takes `GlobalSettings` alongside the rule and runtime. Its one production caller is `RuleLookup.evaluate`, which is reached from `RuleLookup.resolve`, `AppModel`, and `RuleUsageReader`. All three hold the effective document already, so the setting travels the path the reset minute travels: read from the document in force, never assembled by a component of its own.

## The stamp

`RuleRuntime` gains `lastSessionExpiry: Date?`, written in `clearExpiredSession` from the session's own `expiresAt` rather than from the current instant.

That distinction is what makes the cooldown correct under a late or missed callback. The monitor can be delivered its expiry callback late, or miss it entirely and have the app repair the runtime at its next launch; stamping the current instant would extend the cooldown by however long the repair took. A session's stored expiry is already authoritative in this design and is never recomputed, so anchoring to it makes the cooldown's end a pure function of stored values regardless of when reconciliation ran. The behaviour is reachable by unit test, and no part of it needs a device.

Two behaviours follow from where the stamp is written, with no code of their own:

- **A rolled-back grant cools nothing.** `rollBackReservedSession` is a separate method from `clearExpiredSession` and leaves no stamp, so a launch failure that refunds the session starts no cooldown.
- **A cooldown survives the daily reset.** `rollOver` zeroes the session count and does not touch the stamp.

## Storage compatibility

`GlobalSettings` gains a field and `RuleRuntime` gains an optional one. Files written by the current build carry neither. Decoding supplies `0` for the missing cooldown length and `nil` for the missing expiry, which reads back as the current behaviour: no cooldown configured, and no session yet stamped. No migration is needed.

## Applying a change

A cooldown change is judged by the rule that governs every other allowance edit. Lengthening a cooldown permits less use and applies at once; shortening it permits more and waits for the next daily reset.

`ConfigurationComparison.isLoosening(from:to:)` already treats `GlobalSettings` as a unit and gains one comparison — `after.cooldownMinutes < before.cooldownMinutes`. The existing scheduled-change machinery carries the rest, and the settings screen locks the control while a change is pending, as it does for the pause duration.

## What the shield says

The subtitle reads `Cooling down until 3:42 PM.`, with the end time formatted for the locale, above a single `Close` button — the same shape every other refusal takes.

The shield states an end time rather than a running countdown. `ShieldConfiguration` is returned once per render and no API updates a shield already standing, so a countdown would hold whatever second it was built with. This is read from the SDK's shape rather than measured; a shield observed to re-render live would make a countdown available later, and nothing here forecloses it.

`ShieldPrimaryAction` needs no change. It routes any decision that is not `allowed` to `dismiss`, so the button closes the shielded app.

## Known limits

**Repairing a runtime clears its cooldown.** `resetRuntime` writes a fresh record, which drops the stamp along with the session count. The same holds for an app removed from Pause and added again. Both are deliberate actions that already hand back the day's full allowance, so the cooldown is the smaller of the two losses.

**The rules list does not show cooldown state.** It answers how much of the day's allowance is left, and a transient gap is not that. The shield is where a refusal is read, at the moment it applies.

**The cooldown length is global rather than per app.** One length covers every rule, which is the smaller setting and the one the other two globals are shaped like. Making it per app is a later change the model already accommodates: the stamp is stored per rule, so only where the length is read would move.

## Testing

Cooldown behaviour is pure and belongs in `PauseCore`: a session refused inside the gap, allowed once past it, refused for the whole gap when the gap spans a daily reset, absent after a rolled-back grant, and inert when the length is 0. The boundary is tested at the instant the cooldown elapses as well as either side of it.

`GlobalSettings` rejects a cooldown length outside 0 to 10, alongside the existing pause-seconds and reset-minute validation.

No device check is owed. Every claim here is Pause's own arithmetic over stored values, and the device is for observing what iOS does.

## Out of scope

Blocking periods are the other half of the Phase 2 gate and are their own effort. They share the shape of a cooldown — entry refused for a stretch — and join as a further guard in the same decision, but they need a recurring schedule and a monitored activity per weekday so the monitor can re-shield at a boundary. A cooldown needs neither, which is why it ships without them.
