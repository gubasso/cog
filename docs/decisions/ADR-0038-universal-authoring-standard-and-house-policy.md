# ADR-0038: Separate the universal authoring standard from cog house policy

## Context and Problem Statement

Cog's skill-authoring rules mixed two kinds of rule: how to manufacture any Agent Skill, and how a skill earns membership in cog. Because they were mixed, the shipped authoring skill produced packages that could not run without cog installed, so cog became a dependency of every skill a user wrote anywhere.

## Considered Options

- Keep one combined standard and ship it as-is
- Ship the combined standard and let users ignore the cog parts
- Split the standard by owner, and vendor the universal half into the shipped package

## Decision Outcome

Chosen option: `Split the standard by owner, and vendor the universal half into the shipped package`.

`skill-refs/skill-authoring/universal/` owns the rules that hold for any Agent Skill in any project. It names no CLI, no framework, and no repository layout. `docs/reference/skill-contract.md` owns cog house policy: prefix taxonomy, class contracts, gate stanzas, cog command mechanics, and the lint rules enforcing them.

The shipped `skill-creator` package carries byte-identical copies of the universal corpus under its own `references/`, so it is self-contained. `cog skill-vendor check` recomputes the digests recorded in the package manifest and fails on drift, which keeps two copies without two owners.

Cog no longer ships an in-repo skill that authors cog skills. This repository's documents and gates are the authority.

## Consequences

- Good: a skill authored with the shipped package runs where cog is absent.
- Good: cog house policy can change without touching the product users install.
- Bad: the corpus exists in two places on disk, so it needs a gate rather than a convention.
- Bad: removing the in-repo creator made four commands unreachable, and they were swept.

## Status

Implemented

Enacted by [`skill-refs/skill-authoring/universal/`](../../skill-refs/skill-authoring/universal/standard.md), [`skills/skill-creator/`](../../skills/skill-creator/SKILL.md), and [`cmd_skill_vendor.sh`](../../lib/commands/cmd_skill_vendor.sh).
