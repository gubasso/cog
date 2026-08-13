# ADR-0032: Remove the plan vault and the round layer

## Context and Problem Statement

Cog stored plans in a repository-relative vault, ordered them in queues, split them into complexity-graded rounds, dispatched them through queue runners, and calibrated executor routing from telemetry keyed on `project_key + plan_slug + round_id`. That layer is unused: the plan producers, plan reviewers, and executors that people actually run take a single plan artifact and never read the vault. The layer still costs twenty-three commands, thirteen functions, fourteen skills, a skill class, and the records behind them.

## Considered Options

- Remove the vault, the queues, the round layer, and the telemetry that keys on rounds.
- Keep the layer and re-key telemetry onto a surviving identifier.
- Keep the layer unused and undocumented.

## Decision Outcome

Chosen option: `remove the vault, the queues, the round layer, and round-keyed telemetry` — nothing outside the vault depends on them, and re-keying telemetry would preserve a calibration loop no surviving skill consumes.

## Consequences

- Good: one plan is one artifact under the run-directory root, so no plan producer writes into the repository.
- Good: the surviving surface is smaller by twenty-three commands, thirteen functions, fourteen skills, and one skill class.
- Bad: executors stop recording outcome telemetry, and the historical calibration evidence is deleted rather than retired in place.
- Bad: requirement-ID stamping and round coverage lose their only callers and are gone; returning either is a new feature.

## Status

Implemented

Enacted by [slice 010](../plan/slices/010-plan-vault-retirement/README.md).

Supersedes [ADR-0011](./ADR-0011-plan-vault-storage-and-resolution.md), [ADR-0012](./ADR-0012-queue-execution-and-reconciliation.md), [ADR-0013](./ADR-0013-complexity-driven-round-sizing.md), and [ADR-0015](./ADR-0015-executor-capability-and-telemetry.md). Amends [ADR-0010](./ADR-0010-executor-preparation-and-artifacts.md) — executors no longer record telemetry — and [ADR-0014](./ADR-0014-model-effort-and-power-grade.md) — the power grade keeps its tier ladder and loses executor capability routing.
