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

Superseded

Superseded by [ADR-0032](./ADR-0032-remove-the-plan-vault-and-the-round-layer.md) — cog no longer stores, queues, splits, or calibrates plans. The surfaces this record enacted are removed; the record is kept for its history.
