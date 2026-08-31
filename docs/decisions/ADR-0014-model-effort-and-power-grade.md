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

Superseded

Amended by [ADR-0032](./ADR-0032-remove-the-plan-vault-and-the-round-layer.md) — the tier ladder survives; the executor-capability routing half of the power grade does not.

Superseded by [ADR-0036](./ADR-0036-explicit-model-and-effort-at-every-delegation.md) — the tier ladder, the cell registries, and `cog power-grade` are removed; model and effort are stated explicitly at every delegation.
