# ADR-0017: Govern skill authoring with deterministic lint

## Context and Problem Statement

Runtime skills need lean positive prose, producer-blind consumers, stage-agnostic identifiers, scratch conventions, gate references, and terminal contracts. Manual review alone cannot keep these rules aligned.

## Considered Options

- Review conventions informally
- Embed every check in each skill
- Centralize deterministic rules in cog skill-lint

## Decision Outcome

Chosen option: `Centralize deterministic rules in cog skill-lint` — it turns the runtime skill contract into an executable boundary.

## Consequences

- Authoring drift fails before shipping.
- The lint registry becomes a maintained source of truth.

## Status

Implemented

Enacted by [skills and resources](../explanation/skills-and-resources.md) and [skill contract](../reference/skill-contract.md).
