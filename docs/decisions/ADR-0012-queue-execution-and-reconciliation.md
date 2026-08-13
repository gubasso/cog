# ADR-0012: Use prompt-opaque queues with reconciled completion

## Context and Problem Statement

Queue mechanics must select runnable work without interpreting prompt prose, and completion must be owned by the plan rather than inferred from a worker. Revisions need a clear mutable boundary.

## Considered Options

- Prompt-aware scheduling
- Worker-owned completion
- Prompt-opaque selection with plan-owned completion and reconciliation

## Decision Outcome

Chosen option: `Use prompt-opaque selection with plan-owned completion and reconciliation` — it keeps queue state deterministic and reviewable.

## Consequences

- Dependencies and empty outcomes are first-class.
- Completed history cannot be silently rewritten.

## Status

Superseded

Superseded by [ADR-0032](./ADR-0032-remove-the-plan-vault-and-the-round-layer.md) — cog no longer stores, queues, splits, or calibrates plans. The surfaces this record enacted are removed; the record is kept for its history.
