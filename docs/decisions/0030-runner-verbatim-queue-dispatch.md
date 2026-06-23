# ADR-0030: Runner Verbatim Queue Dispatch

## Context and Problem Statement

The queue format gives every item a `prompt:` field. The old `runner-queue` handled the two queue
levels differently: inner `rounds:` items were dispatched verbatim, while top-level `plans:` items
were parsed by `cog runner-queue-resolve-plan` to find an inner `queue-rounds.yaml`, and the selected
main prompt was not dispatched.

That asymmetry made the main queue depend on resolver knowledge of executor prompt shapes instead of
the queue's own command field.

## Considered Options

- Keep one mixed runner and extend its resolver.
- Keep one mixed runner but dispatch main prompts verbatim.
- Split the queue levels into separate runners and dispatch each selected prompt verbatim.

## Decision Outcome

Chosen option: **split the queue levels and dispatch each selected prompt verbatim**.

A `runner-*` selects a queue item and dispatches that item's `prompt:` verbatim to a queue-blind
subagent. The dispatched subagent may be an executor or a nested runner and does not read the parent
queue. Deterministic queue validation, status reconciliation, commit parsing, and guarded queue
prompt rewrites live in `cog`.

The current split is:

- `runner-all` drives the top-level `plans:` queue and dispatches main prompts such as
  `/runner-plan -ar @.implementation-plans/plans/<slug>/`.
- `runner-plan` drives one plan directory's `rounds:` queue and dispatches round prompts such as
  `/executor-prex -ar .implementation-plans/plans/<slug>/<round>.md`.

`runner-all` is prompt-opaque. A malformed selected prompt fails inside the delegated subagent; the
runner then fails closed because the main item cannot be reconciled to `done`. `runner-plan` validates
only its own `-ar @<plan-dir>` invocation target, using the flat plan-directory and queue validation
helpers already owned by `cog`.

## Consequences

- Good: both queue levels follow the same dispatch contract.
- Good: executor skills stay queue-blind, and nested runners are queue-blind to their parent queue.
- Good: adding a new executor no longer requires any main-queue resolver behavior.
- Bad: malformed main queue prompts fail at the delegated boundary rather than during main-queue
  selection.
- Bad: live main queue data must migrate from `/executor-* -ar @<plan-dir>/` prompts to
  `/runner-plan -ar @<plan-dir>/` prompts.

## Status

Accepted

Implemented by `runner-all`, `runner-plan`, `runner-all-setup`, `runner-plan-setup`,
`runner-commit-parse`, and `queue-prompt-set`.

## Related Decisions

- ADR-0008: deterministic mechanics live in `cog`.
- ADR-0011: directory plan queues use `queue-plans.yaml` and per-plan `queue-rounds.yaml`.
- ADR-0016: `runner-*` is the queue-orchestration prefix.
- ADR-0026: queue consumers are producer-blind.
- ADR-0029: main-plan completion is plan-owned and runner-reconciled.
