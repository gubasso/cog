# ADR-0010: Use gated executor preparation and cog-owned artifacts

## Context and Problem Statement

Executors receive prompts of varying quality and produce artifacts that later stages must trust. Preparation, terminalization, and collision handling need one deterministic contract.

## Considered Options

- Execute every input immediately
- Let skills write stage artifacts directly
- Gate input quality and make cog own durable artifacts

## Decision Outcome

Chosen option: `Gate input quality and make cog own durable artifacts` — it makes transitions verifiable and prevents partial ownership.

## Consequences

- Thin prompts receive a plan before execution.
- Artifact paths and terminal states are checked mechanically.

## Status

Implemented

Enacted by [executors](../explanation/executors.md) and [`cmd_executor.sh`](../../lib/commands/cmd_executor.sh).
