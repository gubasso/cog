# ADR-0022: Use hash-bound expiring approval

## Context and Problem Statement

A workflow must not accept an approval token that can be forged, replayed after the reviewed input changes, or retained indefinitely. The operator decision needs a deterministic verification record.

## Considered Options

- Boolean approval flags
- Unbound signed notes
- Hash-bound approval records with expiry

## Decision Outcome

Chosen option: `Use hash-bound approval records with expiry` — it binds authorization to the exact reviewed artifact and time window.

## Consequences

- Changed or stale work fails closed.
- Operators must reapprove materially changed work.

## Status

Implemented

Enacted by [orchestration](../explanation/orchestration.md) and [`cmd_gate.sh`](../../lib/commands/cmd_gate.sh).

Amended by [ADR-0033](./ADR-0033-bind-the-approval-gate-to-one-artifact.md) — the approval binds a named artifact rather than a queue round.
