# ADR-0007: Separate skill judgment from CLI mechanics

## Context and Problem Statement

Runtime skills are good at sequencing and judgment but repeated shell mechanics drift when copied into prose. Deterministic parsing and filesystem operations need executable owners.

## Considered Options

- Keep mechanics in skill prose
- Move all workflows into Bash
- Keep judgment in skills and deterministic routines in cog

## Decision Outcome

Chosen option: `Keep judgment in skills and deterministic routines in cog` — it assigns each kind of work to the medium that can verify it.

## Consequences

- Skills stay lean and reviewable.
- New repeated mechanics require a cog command or shared helper.

## Status

Implemented

Enacted by [skills and resources](../explanation/skills-and-resources.md) and [skill contract](../reference/skill-contract.md).
