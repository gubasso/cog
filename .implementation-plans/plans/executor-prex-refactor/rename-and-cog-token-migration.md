# Round 1: rename + cog token migration

> Plan: executor-prex-refactor | Round: 1 of 6 | Complexity: XL | Generated: 2026-06-19 |
> Repo: /workspaces/cog | Executor: prex (EF 1.5)

## Context

The highest-risk round: rename `/prex` → `/executor-prex` and migrate the cog-side `prex` tokens and
load-bearing artifact contracts without breaking the Stop gate or the live queue. Do this first so the
remaining rounds restructure a correctly-named, contract-stable skill.

## Previous Rounds

None (first round).

## Scope of This Round

**IN scope:**

- Rename `skills/claude/prex` → `skills/claude/executor-prex` (frontmatter `name: executor-prex`,
  update `trigger-tests`, keep `disable-model-invocation: true` and `allowed-tools`). Add the
  `superseded-by`/grandfather handling so the `skill-prefix-taxonomy` lint rule
  (`skill-taxonomy-governance`) is satisfied.
- Migrate cog-side `prex` tokens deterministically: `cog rundir prex`, `cog prex-parse-args`,
  `cog prex-tsk-resolve`, and `cog hook-guard prex-stop` (the Stop gate that reads `stage4-review.md`).
  Decide rename-vs-alias for the command modules (`cmd_prex_parse_args.sh`, `cmd_prex_tsk_resolve.sh`,
  `cmd_hook_guard.sh` token) — prefer renaming command modules to `executor_prex_*` with the
  user-facing dashed names updated, keeping behavior identical. Preserve the `stage4-review.md` and
  `review_loop_input.json` artifact-name contracts (the Stop gate depends on them) — migrate with
  tests, never silently.
- Queue-prompt compatibility: every existing `.implementation-plans/queue-plans.yaml` entry and many
  round prompts use `/prex …`. Provide a compatibility path so they keep resolving — either a `/prex`
  → `/executor-prex` alias, or migrate the live queue prompts. Document the choice; do not break
  in-flight queues.
- Update completion, man, `cli-commands.md`, root help snapshots, and every affected bats
  (`cmd_prex_*`, `cmd_hook_guard*`, rundir).

**OUT of scope:**

- Stage restructure + DRY wiring (Rounds 2–5).

## Deterministic vs Probabilistic

- Deterministic (cog): the token migration, artifact-name contracts, alias/queue compatibility, bats.
- Judgment: rename-vs-alias decision for command modules + queue prompts.

## Validation

- `cog skill-lint` green on `executor-prex` (taxonomy satisfied). `cog hook-guard prex-stop`
  equivalent still gates on `stage4-review.md`. The live queue's `/prex` prompts still resolve
  (alias) or are migrated. All affected bats green. `just lint` + `just test` green.

## Execution Discipline

One round per `/prex` session; flip `done` and stop. Commit with `/gc -a` afterward. After this round
lands, subsequent rounds may be invoked as `/executor-prex -ar <round-file>.md` (or `/prex` via the
alias).
