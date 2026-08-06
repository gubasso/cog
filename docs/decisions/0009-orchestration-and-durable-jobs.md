# ADR-0009: Use bounded orchestration and durable jobs

<!-- markdownlint-configure-file { "MD043": { "headings": ["# ADR-0009: Use bounded orchestration and durable jobs","## Context and Problem Statement","## Considered Options","## Decision Outcome","## Consequences","## Status"] } } -->

## Context and Problem Statement

Agent orchestration needs clear isolation boundaries, a fixed depth budget, and durable recovery for long-running work. Duration alone cannot decide whether work should be delegated.

## Considered Options

- Background recursive agents
- Inline everything
- Inline same-context work, delegate true boundaries, and persist long jobs

## Decision Outcome

Chosen option: `Inline same-context work, delegate true boundaries, and persist long jobs` — it keeps context intentional and recovery mechanical.

## Consequences

- Foreground delegation remains the isolation primitive.
- Durable runner state is required for recoverable long jobs.

## Status

Implemented

Enacted by [orchestration](../explanation/orchestration.md) and [orchestration contract](../reference/orchestration-contract.md).
