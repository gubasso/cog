# ADR-0014: Review Implementation Plans Boundary

> Note (ADR-0064): the `review-plan-implementation` boundary described here was renamed to `review-queue-rounds` and made vault-store-aware. This body is left as the historical record.

## Context and Problem Statement

ADR-0012 established a revision boundary that reconciles implementation-plan queues after committed runner work. That boundary was append-oriented: it could mark mutable items done, revise mutable prose, and append newly discovered work, but it did not review dependency wiring or physical queue order.

Execution order is derived from list position plus `depends_on`. If a revision pass discovers that remaining work now has different prerequisites, the boundary needs a deterministic way to update dependencies and then canonicalize order without hand-editing queue YAML.

## Considered Options

- Keep the ADR-0012 append-only revision boundary.
- Let the skill directly edit dependency lists and reorder queue YAML.
- Add deterministic `cog` queue helpers for dependency edits, graph validation, and reorder, then have the skill use those helpers.

## Decision Outcome

Chosen option: **Add deterministic queue helpers and expand the revision boundary**.

The project-local `.claude/skills/review-implementation-plans` boundary now performs two reviewed phases:

1. Reconcile plans against the current codebase, verify with `cog review-implementation-plans-verify`, and commit any drift with foreground `/gc -a`.
2. Review queue execution order and dependencies, adjust only mutable (`todo`/`backlog`) items via `cog queue-deps-set`, canonicalize physical order via `cog queue-reorder`, validate with `cog queue-graph-check`, verify again, and commit any drift with foreground `/gc -a`.

The model supplies judgment only by selecting dependency changes for mutable items. Physical order is derived deterministically by a stable topological sort of `depends_on`. `done` and `doing` items are not re-depended or moved.

This ADR supersedes [ADR-0012](./0012-plan-queue-revision-boundary.md). ADR-0012 remains accepted historical context for the original revision boundary.

## Consequences

- Good: Queue ordering and dependency drift are corrected before the next queued item is selected.
- Good: Queue mutation remains deterministic and guarded by `cog` subcommands rather than skill prose.
- Good: The two-commit cadence separates plan reconciliation drift from queue-ordering drift.
- Bad: A revision boundary can now produce up to two revision commits after one committed runner item.
- Bad: The queue helper surface and integration test matrix are larger.

## Status

Accepted
