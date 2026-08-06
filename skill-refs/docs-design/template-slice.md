<!-- markdownlint-disable-file MD041 -->

Copy this file into `<project>/docs/plan/slices/<id>-<slug>/README.md`. Commit it before the work starts. Keep the heading list exactly as it is so `MD043` can pin it. Do not add `tasks.md`, `requirements.md`, or any other sibling file unless the gate in [07 — Plan and Slices](./07-plan-and-slices.md) is met.

# <id> — {Short Title}

## Goal

{One sentence naming the observable outcome. Not the mechanism.}

## Appetite

{The fixed budget, in the project's chosen unit: calendar time, human review passes, or implementation sessions. Chosen before the design below.}

## Core

{The non-negotiable outcome this slice guarantees. Never cut. If this fills the whole appetite, the slice is mis-shaped — split it before starting.}

## In scope

- {Negotiable item, most valuable first}
- {Negotiable item}
- {Negotiable item, cut first}

## Out of scope

- {Explicit no-go}
- {Explicit no-go}

## Governed by

- `{path/to/docs/explanation/<subsystem>.md}` — {why this session needs it}
- `{ADR-NNNN}` — {the constraint it imposes}

## Acceptance

```text
{EARS assertion} -> {test name}
{EARS assertion} -> {test name}
```

## Rabbit holes

- {Known trap} — escape: {the pre-authorized response, decided now, not mid-work}

## Done when

{The objective completion condition: the named tests above pass unskipped, and the `milestones.md` line flips.}

## Revisions

{One line per change to Goal, Core, Appetite, or Acceptance after the work started: what changed, and what was learned that changed it. Empty until the first revision.}
