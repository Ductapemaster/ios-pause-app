# Pause iOS App — product requirements

## Audience

Designed for one individual. At this time, this application is not designed to be distributed to the App Store or other phones.

## The Goal

Reaching for a distracting app is usually reflex rather than decision. The app inserts a deliberate moment before entry, and caps how many times a day the reflex can be indulged. Additionally, it can provide scheduled access to sessions, and block access to selected apps altogether outside of a scheduled block.

## Choosing which apps are restricted

Any eligible installed app can be picked from the system's own picker. Pause uses Apple's label and icon for the selected app. Restricted apps are blocked by default.

## Configuring an app

- **Sessions per day** — how many times the app may be entered before the next day reset.
- **Session length** — how long one session runs, from a few minutes upward.

Optionally an app carries one or more **windows** — periods when it cannot be entered at all, each with a start, an end, and the weekdays it applies to.

Two global settings exist: 
1. **pause duration**: how long the user must "pause" before being allowed to enter an app.
2. **day reset**: when during each day the number of available sessions resets, chosen in fifteen-minute steps. The same time applies every day.

## Seeing the day's usage

Opening Pause shows, for each restricted app, how many sessions are charged against the current day beside the limit set for it — *"2/4"*. It covers the day in progress only; previous days are not kept. Session length is not shown here, because the app's own screen is where it is read and set.

The count answers the same question the blocked screen answers, at a different moment. In Pause it is read before reaching for the app, while the choice not to open it is still cheap. On the blocked screen it arrives once the reflex has already run, and what it informs is whether to spend a session or stop. Both surfaces resolve the same allowance, so they cannot disagree.

## Entering a restricted app

1. Tap the restricted app. It opens to a blocked screen naming which session this would be — *"Instagram — 3rd of 4 sessions today."*
2. Tap **Continue**. The Pause app comes forward with a breathe animation and countdown.
3. Tap **Use for X minutes**, where X is the session length for that app. Pause opens the target automatically when the target exposes a supported launch route; otherwise it grants the session and tells the user to return manually.
4. At expiry the app is blocked again, and reaching for it starts over at step 1.

**The screen informs with a count and refuses with a reason** — inside a window, or out of sessions for today.

## How a session behaves

- **Its length is fixed when granted**, and one session is charged from the available pool upon start.
- **Time burns whether or not the app is being used.**
- **Returning after session expiration finds the app blocked**, and entering again costs another session.
- **The block page returns immediately after the session ends**
- **Windows gate entry, not use.** A session granted at 08:55, before a window opens at 09:00, runs its full length.
- **A session spanning the day reset keeps running** and counts only against the day it started in.

## Roadmap

Explore whether basic session history would improve the behavior-modification loop enough to justify a product feature. History is not part of the initial implementation.

## Not building

Minute-based limits of any kind, earn-back challenges, accountability partners or sharing, subscriptions and onboarding, and usage-metered sessions — a session that pauses when you leave the app would be a meter rather than a grant.
