# Round 2: /plan-claude and /plan-codex skills

> Plan: lean-plan-and-review-skills | Round: 2 of 4 | Complexity: L | Generated: 2026-06-19 |
> Repo: /workspaces/cog | Executor: prex (EF 1.5)

## Context

Author the two lean planners on top of the Round-1 `cog plan-doc` mechanics. They behave like native
plan mode: research (via the shelf), interview/back-and-forth, then output ONE plan to screen + save.
Get inspired by `prex` "Stage 1: Plan With Codex".

## Previous Rounds

Round 1 built `cog plan-doc` / `cog plan-review` artifact mechanics.

## Scope of This Round

**IN scope:**

- `skills/claude/plan-claude/SKILL.md`: lean interactive planner. Frontmatter `name: plan-claude`,
  `model: opus`, `effort: xhigh`, `argument-hint`, `disable-model-invocation` per the family pattern,
  `trigger-tests`. Carries `<!-- cog-skill: plan-emitter -->` + a Phase 0 `<!-- cog-plan-mode-gate -->`
  stanza (STOP if Claude plan mode is active; do not call `ExitPlanMode`). Body = sequencing +
  judgment only: a dedicated research step that READS/records via `cog research-shelf` (reuse-or-
  refresh judgment), an interview loop (reuse `plan-writer` interview prose patterns via
  `AskUserQuestion`), then delegate all save mechanics to `cog plan-doc save`. Output: plan to screen
  + saved path (default runtime dir or a user path).
- `skills/codex/plan-codex/SKILL.md`: Codex twin lean planner. Codex frontmatter = `name` +
  `description` only. Model/effort are NOT in frontmatter; native effort `high` passes through
  `cog codex-runner --effort high`. Codex skills are gate-exempt. Same lean shape: research via the
  shelf contract, then produce the plan; save via `cog plan-doc save`.
- Run `cog skill-lint` on both (Claude structural + plan-mode-gate + prefix-taxonomy; Codex
  name+description rule).

**OUT of scope:**

- The two review-plan skills (Round 3).
- Wiring into executors/prex (siblings `executor-single-agent-wrappers` / `executor-prex-refactor`).

## Deterministic vs Probabilistic

- Deterministic (cog): all save/run-dir/output mechanics via `cog plan-doc` (Round 1).
- Judgment: the interview flow, research reuse-vs-refresh decision, plan content — all skill prose.

## Validation

- `cog skill-lint` green on both new skills; the plan-mode-gate rule passes for `plan-claude`. Skills
  contain no inline deterministic shell beyond `cog` calls. `just lint` + `just test` green.

## Execution Discipline

One round per `/prex` session; flip `done` and stop. Commit with `/gc -a` afterward.
