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

