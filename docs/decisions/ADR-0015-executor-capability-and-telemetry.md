# ADR-0015: Use capability routing with append-only telemetry

## Context and Problem Statement

Executor selection needs an auditable capability model and evidence about whether assignments were well matched. Calibration must not rewrite historical outcomes automatically.

## Considered Options

- Static hand selection
- Self-adjusting automatic calibration
- Derived capability bands with append-only outcomes and human-gated calibration

## Decision Outcome

Chosen option: `Use derived capability bands with append-only outcomes and human-gated calibration` — it separates measurement from policy change.

## Consequences

- Routing can explain its selected executor.
- Calibration remains reviewable and historical outcomes stay immutable.

## Status

Implemented

Enacted by [executors](../explanation/executors.md), [plan vault](../explanation/plan-vault.md), and [match telemetry](../reference/match-telemetry.md).
