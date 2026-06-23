# ADR-0029: Plan-Owned Main-Plan Completion, Runner-Reconciled

## Context and Problem Statement

The historical `runner-queue` previously claimed sole ownership of the top-level `queue-plans.yaml` `done` flip and
applied it with a strict `cog queue-status-set --schema plans --from todo --to done` guard. But the
plan's final round step — authored by the plan producer and run by a queue-blind `executor-*` as
opaque plan content — already flips that same top-level entry. The strict guard then failed because
the entry was no longer `todo`, surfacing a contract deviation even though the end-state was correct.
The same plan must also stay completable by an independent `/executor-*` call with no runner present.

## Considered Options

- Keep runner sole owner; strip the top-level flip from the plan template.
- Plan-owned flip; runner reconciles idempotently (ensure-done), fixing a missed flip.
- Branch in skill prose: read status, then conditionally flip.

## Decision Outcome

Chosen option: **Plan-owned flip, runner-reconciled** — the plan's final step flips the top-level
entry; the runner then *ensures* `done` idempotently via `cog queue-status-set ... --idempotent`,
accepting an already-`done` entry as a no-op, fixing a missed `todo → done`, and failing closed on
any other state. The reconcile is deterministic state mechanics, so it lives in `cog`, not prose
branching (ADR-0008). This keeps both queue levels symmetric (plan-owned flip, runner-verified) and
makes a plan self-sufficient under an independent executor run.

This does not violate ADR-0026 producer-blindness: the executor still names no producer and reads no
queue — the flip is plan data it runs opaquely. It is orthogonal to the ADR-0012 revision boundary.

## Consequences

- Good: Independent executor runs that flip the top-level entry no longer conflict with the runner.
- Good: Inner-round and main-plan completion follow one symmetric ownership model.
- Good: The generic `executor-*` skills stay queue-blind.
- Bad: `cog queue-status-set` carries a second status-write mode (`--idempotent`).

## Status

Implemented

- `lib/commands/cmd_queue_status_set.sh` (`--idempotent`)
- `skills/claude/runner-all/SKILL.md` (main queue reconcile after delegated `runner-plan`)

Supersedes the prose-only "main-plan `done` is always runner-owned" claim previously asserted only in
the historical `runner-queue`; no prior ADR established it. ADR-0030 records the current split-runner
dispatch shape.
