# ADR-0013: Use complexity-driven recursive round sizing

## Context and Problem Statement

Large implementation plans need reviewable execution rounds without arbitrary line limits. Splits must preserve every requirement identity and terminate deterministically.

## Considered Options

- Fixed-size chunks
- Unbounded single rounds
- A rubric-driven binary split loop with requirement identities

## Decision Outcome

Chosen option: `Use a rubric-driven binary split loop with requirement identities` — it sizes work by implementation risk while proving coverage.

## Consequences

- Oversized rounds split until executable or irreducible.
- Cog owns queue state; models judge complexity and seam quality.

## Status

Superseded

Superseded by [ADR-0032](./ADR-0032-remove-the-plan-vault-and-the-round-layer.md) — cog no longer stores, queues, splits, or calibrates plans. The surfaces this record enacted are removed; the record is kept for its history.
