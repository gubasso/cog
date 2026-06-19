# Round 3: /review-plan-claude and /review-plan-codex skills

> Plan: lean-plan-and-review-skills | Round: 3 of 4 | Complexity: L | Generated: 2026-06-19 |
> Repo: /workspaces/cog | Executor: prex (EF 1.5)

## Context

Author the two lean plan-reviewers on top of the Round-1 `cog plan-review` mechanics. They review ONE
plan before concrete implementation (not code). Get inspired by `prex` "Stage 2: Review The Plan In
Claude" and the existing `plan-reviewer` judgment axes.

## Previous Rounds

Round 1 built `cog plan-review`. Round 2 authored `plan-claude` + `plan-codex`.

## Scope of This Round

**IN scope:**

- `skills/claude/review-plan-claude/SKILL.md`: lean Claude plan-reviewer. Body = judgment +
  sequencing: research via the shelf (reuse-or-refresh); review against correctness, completeness,
  feasibility, currency, security, idiomatic-fit, scope boundaries, missing dependencies, testability,
  deterministic/probabilistic-boundary compliance, executor suitability — inherited from
  `plan-reviewer` + prex Stage 2; delegate all artifact mechanics to `cog plan-review` (incl. its
  Orchestrator Invocation Contract). Frontmatter `name: review-plan-claude`, `model: opus`, `effort`
  per `model-effort-policy.md`, `trigger-tests`. Because it writes an annotated-plan artifact to disk,
  carry `<!-- cog-skill: plan-emitter -->` + the Phase 0 `<!-- cog-plan-mode-gate -->` stanza.
- `skills/codex/review-plan-codex/SKILL.md`: Codex twin plan-reviewer (net-new — none exists today).
  Codex frontmatter = `name` + `description` only; native effort `high` via `cog codex-runner`;
  gate-exempt. Same lean review shape; reuse the shelf research and `cog plan-review`.
- Run `cog skill-lint` on both.

**OUT of scope:**

- Retiring `plan-reviewer` (Round 4).
- Executor/prex wiring (dependent siblings).

## Deterministic vs Probabilistic

- Deterministic (cog): artifact mechanics + orchestrator output contract via `cog plan-review`.
- Judgment: the review axes, severity, and annotation decisions — all skill prose.

## Validation

- `cog skill-lint` green on both; plan-mode-gate passes for `review-plan-claude`; the Orchestrator
  Invocation Contract (two abs paths → written artifact) is exercised by a smoke check. `just lint` +
  `just test` green.

## Execution Discipline

One round per `/prex` session; flip `done` and stop. Commit with `/gc -a` afterward.
