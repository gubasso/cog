# ADR-0018: Use safe multi-repository commit orchestration

## Context and Problem Statement

Commit workflows must preserve change provenance, validate messages, fan out per repository, and stop when undeclared dirty state appears. An empty change set must be a valid outcome.

## Considered Options

- One broad commit command
- Agent-authored direct git sequences
- Cog safety checks with per-repository workers and fix loops

## Decision Outcome

Chosen option: `Use cog safety checks with per-repository workers and fix loops` — it makes mutation scope explicit and recoverable.

## Consequences

- Conventional commit policy and provenance are deterministic.
- Operator recovery is required for destructive ambiguity.

## Status

Implemented

Enacted by [commit orchestration](../explanation/commit-orchestration.md) and [`cmd_gc_plan.sh`](../../lib/commands/cmd_gc_plan.sh).
