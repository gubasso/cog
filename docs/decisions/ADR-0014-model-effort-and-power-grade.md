# ADR-0014: Use a governed model-effort power grade

## Context and Problem Statement

Orchestrators need a stable vocabulary for model capability, effort, and skill policy. The tier ladder must remain explicit and grounded in registered evidence.

## Considered Options

- Ad hoc model names in prose
- A single preferred model
- Named cells and tiers with source and skill registries

## Decision Outcome

Chosen option: `Use named cells and tiers with source and skill registries` — it makes routing and policy validation deterministic without removing the tier concept.

## Consequences

- Skill tiers can be linted and inspected.
- External capability facts require tracked evidence and revalidation.

## Status

Implemented

Enacted by [power grade](../explanation/power-grade.md) and [model-effort policy](../reference/model-effort-policy.md).
