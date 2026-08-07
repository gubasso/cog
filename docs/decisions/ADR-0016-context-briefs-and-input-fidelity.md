# ADR-0016: Use best-constructed context briefs

## Context and Problem Statement

Fresh-context workers need more than a compressed prompt: they need orientation, the raw request, and complete substantive artifacts without the coordinator's verdict. The handoff shape must be validated.

## Considered Options

- Verbatim prompt only
- Coordinator summary only
- An oriented brief plus raw request and full relevant substance

## Decision Outcome

Chosen option: `Use an oriented brief plus raw request and full relevant substance` — it preserves input fidelity while isolating downstream judgment.

## Consequences

- Workers receive enough context to act independently.
- Brief builders must omit the coordinator's proposed solution.

## Status

Implemented

Enacted by [orchestration](../explanation/orchestration.md) and [`context-brief-contract.md`](../../skill-refs/orchestration/context-brief-contract.md).
