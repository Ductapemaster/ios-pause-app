# CLAUDE.md — how to work in this repo

This repository contains Pause, a personal iOS app for deliberate, session-based access to selected apps. Overview and current state: see README.md (and `docs/` as the project grows).

## Roles

Dan is the user and product manager; Claude is the engineering manager and engineer. Dan has technology experience but does not write Swift and does not work in this codebase.

- **Consult Dan on product** — behavior, user experience, priority, severity, scope. Engineering choices sit with Claude: prefer deciding between implementations over putting them to him, and verify code behavior rather than asking him to confirm it.
- **Lead with what the user sees.** File and symbol references support a conclusion; they land better after it than as the question.
- **His reports are symptoms, not diagnoses** — reproduce and find the cause.
- **Verification falls to Claude** — Dan is not placed to catch a wrong claim about Swift, so check before asserting and separate measured from inferred.

## Conventions

- Treat `docs/product-requirements.md` as the product source of truth.
- Keep Apple platform and tooling choices explicit in implementation plans; none have been established in this fresh repository.

## Testing on the device

**When a change is built and ready to try on the phone, install it — don't stop at "here's the command."** The paired iPhone 16 Pro is `<device-id>`, `Local.xcconfig` carries the team ID, and the `Pause` scheme builds the app with all three extensions:

```bash
xcodegen generate
xcodebuild -project Pause.xcodeproj -scheme Pause \
  -destination 'id=<device-id>' \
  -derivedDataPath /tmp/pause-dd build
xcrun devicectl device install app \
  --device <device-id> \
  /tmp/pause-dd/Build/Products/Debug-iphoneos/Pause.app
```

Reinstalling over the existing build keeps the app-group container, so rules and runtimes survive. Confirm first only when something would actually be destroyed — a bundle ID change or a signing change that forces a delete.

Device checks are batched deliberately: `docs/ROADMAP.md` under Deferred lists what is owed on the current build, and they ride one trip to the phone. Name the ones the new build unblocks when handing it over.

## Reading the device's logs

**When the question is *when* something ran, read it off the device rather than asking Dan to watch for it.** Background callbacks — the daily reset, a session expiring, the monitor waking — fire at hours nobody should be awake for, and "the count had renewed by morning" cannot tell 05:00 from midnight. The extensions log at `.notice` so these lines survive into the log store, and `log collect` pulls them back:

```bash
sudo /usr/bin/log collect --device-udid <device-udid> \
  --start "2026-08-23 22:00:00" --output /tmp/pause.logarchive

/usr/bin/log show /tmp/pause.logarchive \
  --predicate 'subsystem BEGINSWITH "com.koubalabs.pause"' --style compact
```

Four things fail this before it works:
- **`/usr/bin/log`, spelled in full** — zsh has a `log` builtin that swallows the arguments.
- **`sudo` is required**, and it needs a terminal. Dan runs it with a `!` prefix, or approves the Touch ID prompt.
- **The phone must be cabled.** `devicectl list devices` saying `available (paired)` is network pairing and is not enough; it must read `connected`, or the collect fails with "Device not configured".
- **`--start` must precede the event.** An archive whose window ends before the callback holds no lines for it, which looks exactly like an extension that never woke.

An empty result is not evidence of failure on its own: the monitor extension only launches at a callback, so a window covering only idle hours is legitimately silent. Confirm the window contains the event before reading anything into a gap.

## Where things go

Create each doc straight into its home by what it is — the folder *is* its role, and it exists as soon as its first file does (don't pre-create `docs/`; a fresh repo is just this file + README.md):
- **CLAUDE.md** (this) — how to work here. Put a directive in the narrowest-scope CLAUDE.md that covers the work: this root file for repo-wide rules, a **`<component>/CLAUDE.md`** for one subsystem (create it if missing), not a README.
- **README.md** — what this is, how to run it, the directory map.
- **docs/README.md** — the durable overview: the model + the *why*; the docs landing page. Present tense — no dates, "done", or history (git holds how it got here).
- **docs/ROADMAP.md** — the single prioritized "what's next."
- **docs/status.md** — the resume pointer: `## Status — resume here` only, overwritten each checkpoint (never a dated ledger). Synthesis belongs in docs/README.md.
- **docs/design/`<x>`.md** — as-built design depth for a subsystem (design tied to one component's code lives with it, e.g. `<component>/ARCHITECTURE.md`).
- **docs/research/`<x>`.md** — an open investigation / unknown.
- **docs/archive/`<effort>`/** — a shipped effort's frozen design + plan + review, with a README breadcrumb.

A doc only *moves* when its state changes, riding an event you're already doing: a plan freezes into `docs/archive/<effort>/` when it ships, and its durable lessons fold up into `docs/README.md` then. Never annotate in place; relocate.

