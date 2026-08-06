# ADR-0013: Use complexity-driven recursive round sizing

<!-- markdownlint-configure-file { "MD043": { "headings": ["# ADR-0013: Use complexity-driven recursive round sizing","## Context and Problem Statement","## Considered Options","## Decision Outcome","## Consequences","## Status"] } } -->

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

Implemented

Enacted by [executors](../explanation/executors.md) and [`cmd_round_rightsize.sh`](../../lib/commands/cmd_round_rightsize.sh).
