# Round 2: stage restructure + Stage 1/2 DRY

> Plan: executor-prex-refactor | Round: 2 of 6 | Complexity: XL | Generated: 2026-06-19 |
> Repo: /workspaces/cog | Executor: prex (EF 1.5)

## Context

Fix the structure the user flagged: each stage gets its own clear top-level section, the lumped
`## Stage 2 Through Stage 5 Details` + `references/stage-2-through-5-details.md` split is eliminated,
and Stages 1–2 are DRY-wired to the new lean skills.

## Previous Rounds

Round 1 renamed `prex` → `executor-prex` and migrated cog tokens/contracts.

## Scope of This Round

**IN scope:**

- Restructure `skills/claude/executor-prex/SKILL.md` so each stage is its own real top-level section:
  `## Stage 1: Plan`, `## Stage 2: Review Plan`, `## Stage 3: Implement`, `## Stage 4: Review
  Implementation`, `## Stage 5: Optional Review Loop`. ELIMINATE
  `references/stage-2-through-5-details.md`: fold each stage's command shapes back into its own section,
  or, if a stage genuinely needs an overflow reference, give it its own well-scoped
  `references/stage-N-*.md` (never a multi-stage lump). Keep the SKILL under 500 lines (skill-lint);
  push long-form deterministic detail into cog/help, not prose.
- Stage 1 → delegate planning to `/plan-codex` (the new lean Codex planner) instead of the inline Codex
  planning prompt. Stage 2 → delegate plan review to `/review-plan-claude` instead of `plan-reviewer`,
  preserving the snapshot-pre/post + `verify-proof` + approval-loop contract.
- Run `cog skill-lint` (structural, plan-mode-gate as applicable, orchestration, premise).

**OUT of scope:**

- Stage 3 (Round 3), Stage 4 (Round 4), Stage 5 (Round 5).

## Deterministic vs Probabilistic

- Deterministic (cog): the snapshot/verify-proof contracts (unchanged); delegation plumbing via the new
  skills + `cog`.
- Judgment: section structure, what (if anything) needs an overflow reference, the delegation prose.

## Validation

- `references/stage-2-through-5-details.md` no longer exists; each stage has its own section. Stage 1
  references `/plan-codex`, Stage 2 references `/review-plan-claude` (no `plan-reviewer`). `cog
  skill-lint` green; SKILL under 500 lines. `just lint` + `just test` green.

## Execution Discipline

One round per `/prex` (or `/executor-prex`) session; flip `done` and stop. Commit with `/gc -a`
afterward.
