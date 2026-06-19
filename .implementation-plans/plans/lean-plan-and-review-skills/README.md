# Lean plan + review-plan skills: plan-claude, plan-codex, review-plan-claude, review-plan-codex

> Complexity: L | Rounds: 4 | Generated: 2026-06-19 | Repo: /workspaces/cog | Executor: prex (EF 1.5)

## Problem Statement

Add four NEW lean, single-engine, interactive skills that behave like native plan mode — one per
engine for creating and for reviewing plans:

- `/plan-claude` — Claude builds a plan. Frontmatter `model: opus`, `effort: xhigh`. Plan-emitter →
  carries the plan-mode gate.
- `/plan-codex` — Codex builds a plan via the cog codex-session runner. Codex skill (frontmatter is
  `name` + `description` only); model default, native effort `high` passed through `cog codex-runner`.
- `/review-plan-claude` — Claude reviews a plan before implementation.
- `/review-plan-codex` — Codex reviews a plan before implementation (net-new; there is no Codex
  plan-reviewer today).

These are the lean tier (Q1): interview + back-and-forth, output ONE plan (or one annotated plan
review) to screen and save to the cog runtime dir (or a user-specified path). They DRY-reuse
`plan-writer`'s research/interview cog mechanics but do NOT emit the heavy `.implementation-plans/`
directory + queue format. They consume the persisted research shelf (one research helps the others)
and get inspired by `prex` Stage 1 (planning) and Stage 2 (plan review) and the existing
`plan-reviewer`. This sibling also retires the legacy `plan-reviewer` (reconciling the
`skill-taxonomy-governance` decision once the replacement exists).

## Strategy

Build the shared deterministic artifact mechanics once, then author the two planners, then the two
plan-reviewers, then retire `plan-reviewer` and run the gates.

1. `lean-plan-artifact-cog-commands` — `cog plan-doc` (planner artifact) + `cog plan-review` (reviewer
   artifact) command families sharing run-dir/output-path/save mechanics.
2. `plan-claude-and-plan-codex` — author the two planner skills.
3. `review-plan-claude-and-review-plan-codex` — author the two plan-reviewer skills.
4. `retire-plan-reviewer-and-gates` — retire/supersede `plan-reviewer`; trigger-tests; inventory;
   gates.

## Rounds

1. `lean-plan-artifact-cog-commands.md` — shared cog artifact commands + bats + surfaces.
2. `plan-claude-and-plan-codex.md` — `skills/claude/plan-claude` + `skills/codex/plan-codex`.
3. `review-plan-claude-and-review-plan-codex.md` — `skills/claude/review-plan-claude` +
   `skills/codex/review-plan-codex`.
4. `retire-plan-reviewer-and-gates.md` — retire `plan-reviewer`; trigger-tests; gates.

## Execution Commands

```bash
/prex -ar @.implementation-plans/plans/lean-plan-and-review-skills/
# or
/prex -ar .implementation-plans/plans/lean-plan-and-review-skills/lean-plan-artifact-cog-commands.md
```

## Execution Discipline

One `/prex` session per round; runs the first `todo` round, flips it `done`, and stops. Commit each
round with `/gc -a` afterward.

## Decisions & Constraints

- `Executor: prex (EF 1.5)`.
- Lean tier: ONE plan (or one plan-review) artifact, output to screen + saved to the cog runtime dir
  (default) or a user path. NO directory/queue format (that stays in `plan-writer`/`plan-writer-multi`).
- `/plan-claude` and `/review-plan-claude` are Claude plan-emitters that write a plan/annotated-plan to
  disk → carry `<!-- cog-skill: plan-emitter -->` + a Phase 0 `<!-- cog-plan-mode-gate -->` stanza
  (ADR-0015). `/plan-codex` and `/review-plan-codex` are Codex skills (gate-exempt).
- `model: opus` + `effort: xhigh` for `plan-claude` (the brief-set exception); other Claude skills
  follow `model-effort-policy.md` (never sonnet). Codex skills pass native effort `high` via
  `cog codex-runner --effort high`.
- All deterministic mechanics (run-dir, output-path resolution, save, validation, the
  orchestrator-invocation output contract) live in `cog`; skills carry only interview + judgment.
- Each new `SKILL.md` carries `trigger-tests` (Claude) and passes `cog skill-lint`. New cog commands
  sync `cli-commands.md`, man, completions, help snapshots, bats.

## Reconciliation (depends_on, no duplication)

- `depends_on: skill-taxonomy-governance` — names land under the taxonomy; the `plan-reviewer`
  retirement executes the decision recorded there.
- `depends_on: skill-research-shelf` — the skills READ the shelf instead of ad-hoc research.
- `depends_on: codex-native-effort-runner` — `plan-codex`/`review-plan-codex` call
  `cog codex-runner --effort high`, no `--profile`.
- `depends_on: cog-self-contained-skill-refs` — the Codex skills rely on the internalized cog
  orientation and do not read `codex-conventions.md`.
- Reuse `cog plan-slug` and the existing `plan-writer` interview/research helpers — do not duplicate.
- Consumed by `executor-single-agent-wrappers` (3-stage) and `executor-prex-refactor` (Stages 1/2).
