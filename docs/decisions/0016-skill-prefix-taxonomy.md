# ADR-0016: Skill Prefix Taxonomy

## Context and Problem Statement

Shipped skills need stable naming semantics before dependent rename work can proceed. This ADR records
the four-prefix skill taxonomy (with `review-plan-*` as a sub-namespace of `review-*`) as a governing
decision so every later sibling names skills against a fixed contract.

## Considered Options

- Keep skill prefixes informal.
- Define the four-prefix taxonomy in the skill contract only.
- Record the taxonomy in an accepted ADR and mirror it in the skill contract.

## Decision Outcome

Chosen option: **record the taxonomy in an accepted ADR and mirror it in the skill contract** — an ADR
gives the naming rule durable, citable authority; the contract gives it an enforcement home.

The prefixes and their required semantics:

- `plan-*` emits implementation plans.
- `review-*` reviews code against the codebase plus plan, and reviews plans before implementation.
- `review-plan-*` is the `review-*` sub-namespace for plan-before-implementation review skills.
- `executor-*` executes one plan/prompt at a time and may generate its own better internal plan before
  executing.
- `runner-*` orchestrates executors over a queue whose elements carry the executor-selecting prompt.

Governing rule: a skill's prefix must match what the skill actually does.

This ADR extends — it does not rewrite — [ADR-0014](0014-review-implementation-plans-boundary.md),
especially its `review-implementation-plans` rename/boundary decision. Under this taxonomy,
`plan-reviewer` is inconsistent because it reviews plans and therefore belongs under `review-plan-*`,
and `prex` is inconsistent because it is an executor slated for rename to `executor-prex`. Those
renames are deferred to dependent sibling rounds.

Related accepted skill governance, referenced not modified:
[ADR-0013](0013-model-effort-policy.md) and [ADR-0015](0015-plan-skills-not-in-plan-mode.md).

[ADR-0021](0021-twin-skill-naming-and-delegation-hints.md) extends this taxonomy with the native
twin versus delegation-launcher naming rule. It keeps these prefixes intact and defines when platform
tokens belong in the suffix.

## Consequences

- Good: future skill names follow a stable, citable contract.
- Good: plan-review skills get an explicit `review-plan-*` sub-namespace.
- Bad: existing inconsistent names (`plan-reviewer`, `prex`) remain until dependent rename rounds.

## Status

Accepted
