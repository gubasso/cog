# executor-prex refactor: rename prex, per-stage restructure, DRY-wire to the new skills

> Complexity: XL | Rounds: 6 | Generated: 2026-06-19 | Repo: /workspaces/cog | Executor: prex (EF 1.5)

## Problem Statement

`/prex` is the staged dual-agent executor (Codex plans → Claude reviews plan → Codex implements →
Claude reviews implementation → optional review loop). The user wants it refactored into the canonical
`executor-*` member:

1. **Rename** `/prex` → `/executor-prex`. This is the highest-risk part: cog-side `prex` tokens and
   load-bearing artifact contracts (`cog hook-guard prex-stop`, `cog rundir prex`, `cog prex-parse-args`,
   `cog prex-tsk-resolve`, and the `stage4-review.md` / `review_loop_input.json` artifact names) must
   migrate without breaking the Stop gate or the live `queue-plans.yaml` prompts (every existing entry
   uses `/prex …`).
2. **Restructure** the SKILL so each stage is its own clear top-level section. Today Stage 1 has a real
   section but Stages 2–5 are lumped behind `## Stage 2 Through Stage 5 Details` pointing at
   `references/stage-2-through-5-details.md` — the "not a good doc split" the user flagged. Eliminate
   that reference; give each stage a real section.
3. **DRY-wire** the stages to the new skills/commands:
   - Stage 1 → `/plan-codex` (instead of the inline Codex planning prompt).
   - Stage 2 → `/review-plan-claude` (instead of `plan-reviewer`).
   - Stage 4 → the refactored `review-code-deep` stage-4 contract.
   - Stage 5 → the refactored `review-loop` with `cog review-loop-input` + child-locate (no inline
     JSON literal / `find` prose).
   - Self-contained codex: native effort, no `--profile` (already swept upstream).

## Strategy

Highest-risk rename + contract migration first, then stage-by-stage restructure/DRY, then docs/tests.

1. `rename-and-cog-token-migration` — rename the skill + migrate cog `prex` tokens + queue-prompt
   compatibility.
2. `stage-restructure-and-stage1-2-dry` — per-stage sections; eliminate the lumped reference; Stage 1
   → `/plan-codex`, Stage 2 → `/review-plan-claude`.
3. `stage3-implement` — Stage 3 native-effort implement + resume fallback preserved.
4. `stage4-review-code-deep` — Stage 4 → refactored `review-code-deep`; preserve `stage4-review.md`.
5. `stage5-review-loop` — Stage 5 → refactored `review-loop` + `cog review-loop-input`.
6. `docs-tests-cleanup` — surfaces, gates, residue checks.

## Rounds

1. `rename-and-cog-token-migration.md`
2. `stage-restructure-and-stage1-2-dry.md`
3. `stage3-implement.md`
4. `stage4-review-code-deep.md`
5. `stage5-review-loop.md`
6. `docs-tests-cleanup.md`

## Execution Commands

```bash
/prex -ar @.implementation-plans/plans/executor-prex-refactor/
# or
/prex -ar .implementation-plans/plans/executor-prex-refactor/rename-and-cog-token-migration.md
```

## Execution Discipline

One `/prex` session per round; runs the first `todo` round, flips it `done`, stops. Commit each round
with `/gc -a` afterward.

Note on self-reference: this plan refactors the very executor that runs it. Through this plan's rounds,
keep `/prex` working — Round 1 provides a compatibility path (alias or queue-prompt migration) so the
runner and the live queue keep functioning while the rename lands. If a later round can no longer be
driven by `/prex` because of the rename, invoke it directly with the post-rename
`/executor-prex -ar <round-file>.md`.

## Decisions & Constraints

- `Executor: prex (EF 1.5)`.
- `stage4-review.md` and the `review_loop_input.json` name are load-bearing for `cog hook-guard
  prex-stop`; migrate them with tests, never silently. Preserve the triage vocabulary
  (FIXED/NEEDS_DISCUSSION/ACKNOWLEDGED/QUESTION/DISMISSED) and the snapshot/verify-proof contracts.
- Deterministic mechanics stay in `cog` (this skill is a thin orchestrator); only sequencing + judgment
  stay prose. Do not reintroduce inline multi-line shell for setup/parse/gate/proof.
- Foreground, env-first, never background Codex (ADR-0010). Codex calls go through `cog codex-runner`
  with native effort (no `--profile`); rely on the internalized cog orientation (no runtime
  `codex-conventions.md` read).
- New/changed cog command surfaces sync `cli-commands.md`, man, completions, help snapshots, bats. Do
  not run git commands inside round bodies.

## Reconciliation (depends_on, no duplication)

- `depends_on: lean-plan-and-review-skills` — Stage 1 calls `/plan-codex`, Stage 2 calls
  `/review-plan-claude`.
- `depends_on: review-deep-loop-refactor` — Stage 4 uses the refactored `review-code-deep`; Stage 5
  uses the leaned `review-loop` + `cog review-loop-input`.
- `depends_on: codex-native-effort-runner` — the prex call sites are already on native effort
  (mechanically swept there); this plan does the structural wiring.
- `depends_on: skill-taxonomy-governance` — the `executor-*` rename + `superseded-by` grandfathering
  for the old `prex` name.
- Independent of `executor-single-agent-wrappers` (both are executors; parallel after shared deps).
