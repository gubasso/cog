# ADR-0008: Skill bodies stay probabilistic; deterministic mechanics live in cog

## Context and Problem Statement

`cog` skills already depended on deterministic CLI helpers, but the boundary was scattered across architecture notes and individual skill bodies. Without one enforced contract, shell parsing and workflow mechanics can accrete in prose, and command logic can be duplicated instead of shared.

## Considered Options

- Keep the premise as prose guidance only.
- Move all skill behavior into shell commands.
- Keep skills as orchestrators and enforce deterministic mechanics through `cog`.

## Decision Outcome

Chosen option: **keep skills as orchestrators and enforce deterministic mechanics through `cog`**. Skills own sequencing, judgment, and runtime-specific orchestration; deterministic routines live in `cog` subcommands and shared `cog::fn::*` helpers. `cog skill-lint` and pre-commit enforce the skill side of this contract.

This extends [ADR-0001](./0001-project-extraction.md), [ADR-0002](./0002-name-cog.md), and [ADR-0006](./0006-loader-based-architecture.md). The detailed contract lives in [Skill contract](../reference/skill-contract.md).

## Consequences

- Good: skill bodies stay reviewable and focused on judgment.
- Good: deterministic mechanics have one tested source of truth.
- Bad: some existing skill examples require cleanup or explicit lint exceptions.
- Bad: the premise heuristic may need tuning as legitimate orchestration idioms appear.

## Status

Implemented. Enacted by [`lib/commands/cmd_skill_lint.sh`](../../lib/commands/cmd_skill_lint.sh), the shared [`lib/functions/fn_skill.sh`](../../lib/functions/fn_skill.sh) helper, and the `skill-lint` hook in [`.pre-commit-config.yaml`](../../.pre-commit-config.yaml).
