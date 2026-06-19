# Round 1: Taxonomy ADR and skill-contract reference

> Plan: skill-taxonomy-governance | Round: 1 of 3 | Complexity: M | Generated: 2026-06-19 |
> Repo: /workspaces/cog | Executor: prex (EF 1.5)

## Context

Record the four-prefix skill taxonomy as a governing decision so every later sibling names skills
against a stable contract. The taxonomy (from the user, verbatim semantics): `plan-*` emits
implementation plans; `review-*` reviews code-vs-codebase+plan AND reviews plans before
implementation (`review-plan-*` is its sub-namespace); `executor-*` executes one plan/prompt at a
time and may generate its own better internal plan before executing; `runner-*` orchestrates
executors over a queue whose elements carry the executor-selecting prompt.

## Previous Rounds

None (first round).

## Scope of This Round

**IN scope:**

- Write a new ADR `docs/decisions/00NN-skill-prefix-taxonomy.md` (next free number) defining the four
  prefixes and their semantics verbatim, the `review-plan-*` sub-namespace, and the rule that a
  skill's prefix must match what it does. Record that it extends — not rewrites —
  `model-effort-policy-and-rename`'s `review-implementation-plans` rename, and that `plan-reviewer`
  (reviews plans → belongs in `review-plan-*`) and `prex` (executor → `executor-prex`) are
  inconsistent and slated for rename in the dependent siblings. Reference, do not modify, ADR-0013
  (model/effort) and ADR-0015 (plan-mode gate).
- Add a "Prefix taxonomy" section to `docs/reference/skill-contract.md` capturing the four prefixes,
  the `review-plan-*` sub-namespace, and a forward pointer to the `skill-prefix-taxonomy` lint rule
  added in Round 2.
- Add the taxonomy as a non-negotiable to `AGENTS.md` and `CLAUDE.md`, mirroring the existing
  skill-contract non-negotiables block style.

**OUT of scope:**

- The `cog skill-lint` rule + classification helper (Round 2).
- Renaming any skill directory or creating any new skill (dependent siblings).
- Touching ADR-0015's plan-mode-gate behavior.

## Deterministic vs Probabilistic

- Deterministic (cog): none this round (documentation only).
- Judgment (skill/round): choosing the ADR number, exact wording, and the cross-references.

## Validation

- New/edited markdown fences declare a language. The ADR references existing accepted ADRs rather
  than deleting or rewriting them. `docs/README.md` index updated if it enumerates ADRs.
- `just lint` (markdownlint + any doc hooks) passes on the touched docs.

## Execution Discipline

One round per `/prex` session; flip this round `done` in `queue-rounds.yaml` and stop. Commit with
`/gc -a` afterward (this round runs no git).
