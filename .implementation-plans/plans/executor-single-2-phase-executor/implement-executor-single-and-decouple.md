# Implement `executor-single` + decouple `cog executor` stages from phases

> Plan: executor-single-2-phase-executor | Round: 1 of 1 | Complexity: L | Generated: 2026-06-22 | Repo: /workspaces/cog

## Context

`cog` ships an executor family of skills that run one prompt/plan through a coding agent. The existing `executor-lean` runs three phases: **plan → review-plan → execute**. We are adding **`executor-single`**, a leaner 2-phase routine — **plan → execute** — that drops the plan-review phase, as a native twin pair (`skills/claude/executor-single`, `skills/codex/executor-single`) plus a delegation launcher (`skills/claude/executor-single-codex`), mirroring the `executor-lean` trio.

Building this exposed two structural problems in `cog executor` that must be fixed in the same round:

1. **Stage ordinals are hardwired to phase meaning.** `lib/functions/fn_executor.sh` bakes `stage1=plan`, `stage2=reviewed-plan`, `stage3=execution` into artifact names, the stages array, summary rendering, and self-check schemas. A 2-phase executor cannot say "stage2 = execution" without forking. Fix: an executor declares its own ordered **phases**; ordinals become positions.
2. **Naming is incoherent.** `cog executor init --executor claude|codex-session` uses "executor" to mean the _coding agent_. But `executor-*` is a **skill/routine** in the prefix taxonomy, not an engine. Fix the CLI so identity is coherent across skills and script:
   - `--executor <executor-lean|executor-single>` = the routine/skill (selects the **flow**).
   - `--engine <claude|codex>` = the coding agent (selects plan engine + reviewer engine).
   - Remove `--plan-engine` (redundant: `--engine` always names the plan engine now).

Locked decisions: artifacts/summary JSON evolves to a **generic phase-keyed schema** (bumped to v2); ship the full `executor-single` trio and register `/executor-single` + `/executor-single-codex` in `queue-prompts`. `executor-lean` keeps identical runtime behavior under the new contract.

## Previous Rounds

This is the first round — no prior rounds.

## Scope of This Round

IN scope:

- Refactor `cog executor` core (`lib/functions/fn_executor.sh`, `lib/commands/cmd_executor.sh`): flow descriptor SoT, `--executor`(skill)/`--engine`(agent) split, drop `--plan-engine`, phase-keyed artifacts/summary v2, reviewer `none` for non-reviewed flows, queue-prompts entries.
- Migrate the three existing `executor-lean*` skills to the new `cog executor` call shape.
- Create the three new `executor-single*` skills.
- Update/extend `test/integration/cmd_executor.bats` (rename lean calls + add single-flow cases).
- Docs: new ADR, `docs/reference/cli-commands.md`, `docs/reference/skills.md`.

OUT of scope:

- `executor-prex`'s separate 4-stage hook-guard flow (`lib/commands/cmd_hook_guard.sh`, `stage1-plan.txt`…`stage4-review.md`) — it is not part of `cog executor`'s artifact system; leave it untouched.
- Any git operations.
- `runner-queue` resolver logic (the `queue-prompts` match rule is already generic; no resolver change is needed for a new `executor-*`).

## Current State

### Key Files

- `/workspaces/cog/lib/functions/fn_executor.sh` — executor SoT helpers. Hardwired 3-stage points:
  - `cog::fn::executor::artifact_name()` maps `stage1→stage1-plan.md`, `stage2→stage2-reviewed-plan.md`, `stage3→stage3-execution.md`, `summary→executor-summary.json`.
  - `cog::fn::executor::classify_input_json()` returns a hardwired `stages` array: `["stage2","stage3"]` for plan input, `["stage1","stage2","stage3"]` for prompt input.
  - `cog::fn::executor::artifacts_json()` emits fixed keys:

    ```text
    {stage1_plan, stage2_reviewed_plan, stage3_execution, summary}
    ```

  - `cog::fn::executor::plan_engine_for_executor()` maps `claude→claude`, `codex-session→codex` (the value being renamed away).
  - `cog::fn::executor::select_reviewer_json()` always returns `reviewer:/review-plan-lean` (`claude→review_engine codex`, `codex→review_engine claude`).
  - `cog::fn::executor::summary_json()` takes exactly 8 positional args (`$6/$7/$8` = stage1/2/3 status) and renders a fixed `stages:{stage1,stage2,stage3}` object; schema `cog.executor.summary.v1`.
  - `cog::fn::executor::queue_prompts_json()` lists 3 prompts: `executor-prex` (stage_model `executor-prex`), `executor-lean`, `executor-lean-codex` (both stage_model `executor-3-stage`).
- `/workspaces/cog/lib/commands/cmd_executor.sh` — the `cog executor` subcommand. Hardwired points:
  - Self-checks (lines ~4-8):

    ```bash
    __cog_executor_artifacts_self_check='(.stage1_plan|type=="string") and (.stage2_reviewed_plan|type=="string") and (.stage3_execution|type=="string") and (.summary|type=="string")'
    ```

  - `__cog_executor_validate_reviewer()` accepts only `/review-plan-lean`.
  - `__cog_executor_validate_stage1_status()` (skipped|done|failed) vs `__cog_executor_validate_stage_status()` (done|failed).
  - `__cog_executor_init()` parses `--executor`/`--input`/`--plan-engine`; for plan input it _requires_ `--plan-engine`; rundir label is `executor-${executor}`.
  - `__cog_executor_summary()` requires all of `--stage1 --stage2 --stage3` and `--reviewer`; checks `reviewer == select_reviewer_json($plan_engine).reviewer`.
  - `__cog_executor_artifacts()` prints `STAGE1_PLAN/STAGE2_REVIEWED_PLAN/STAGE3_EXECUTION` keys.
  - `__cog_executor_usage()` documents `--executor <claude|codex-session>` and the 3-stage summary.
- `/workspaces/cog/skills/claude/executor-lean/SKILL.md` — calls `cog executor init --executor claude [--plan-engine claude]` and `cog executor summary --executor claude --plan-engine claude --reviewer /review-plan-lean --stage1 --stage2 --stage3`. Frontmatter: `model: opus`, `effort: low`, `disable-model-invocation: true`, `allowed-tools: Bash Read Write Edit Agent Grep Glob`. Stage 1 delegates planning to `/plan-one-lean` via the **Agent tool** (`subagent_type: general-purpose`). No plan-emitter marker.
- `/workspaces/cog/skills/codex/executor-lean/SKILL.md` — codex twin; minimal frontmatter (`name`, `description` only); calls `cog executor init --executor codex-session`. Stage 1 builds a `$plan-one-lean` prompt and runs it via `cog codex-runner run-exec --mode danger --access write
  --effort high`; durable-job poll with `cog codex-runner finalize --max-wall <secs>`.
- `/workspaces/cog/skills/claude/executor-lean-codex/SKILL.md` — Claude→Codex delegation launcher; uses `--executor codex-session`; carries `<!-- cog-skill: plan-emitter -->` + `<!-- cog-plan-mode-gate -->` markers and `trigger-tests`.
- `/workspaces/cog/test/integration/cmd_executor.bats` — integration tests. Relevant assertions:
  - init prompt → `.stages == ["stage1","stage2","stage3"]`, `.reviewer == "/review-plan-lean"`.
  - init plan input → `.stages == ["stage2","stage3"]`, `--plan-engine` required.
  - `classify-input "missing.md"` → `.kind=="prompt" and .stages==["stage1","stage2","stage3"]`.
  - `artifacts` → asserts `.stage1_plan/.stage2_reviewed_plan/.stage3_execution/.summary`.
  - `queue-prompts` → `(.prompts | length) == 3` and indexes `/executor-prex`, `/executor-lean`, `/executor-lean-codex`.
  - `summary --json` → `.schema=="cog.executor.summary.v1"`, `.stages.stage1.status`, `.reviewer=="/review-plan-lean"`; plus a rejects-unknown-reviewer test.
- `/workspaces/cog/lib/commands/cmd_skill_lint.sh` + `/workspaces/cog/lib/functions/fn_skill.sh` — skill linter. Relevant: `cog::fn::skill::classify_prefix` maps `executor-*`→`executor`; `cog::fn::skill::is_executor_intent` returns true when the file matches `^# Plan Review Execute` OR contains both `Codex plans` and `Codex implements`. The prefix-taxonomy rule is **Claude-only**; Codex skills are exempt. Plan-mode-gate is required only when the `<!-- cog-skill: plan-emitter -->` marker is present. Claude skills require a `<!-- trigger-tests: -->` comment; all skills: ≤500 lines, no emoji, every code fence has a language tag, no source-tree `skills/.../SKILL.md` path references in prose.
- `/workspaces/cog/install.sh` — installs skills by glob (`copy_tree skills/claude → ~/.claude/skills`, `copy_tree skills/codex → ~/.agents/skills`). No manifest; new skill dirs are picked up automatically.

### Existing Patterns

- Commands: handler `cog::cmd::executor`; helpers `cog::fn::executor::*`; line-2 `: 'desc: ...'` sentinel must stay. JSON via `cog::fn::json_emit "<self-check>" "$json"`; file-first writes via `cog::fn::json_write_fragment`. Errors via `cog::fn::error_raise`.
- Skill model/effort policy: `model: sonnet` is forbidden; use `model: opus` + `effort: low` (`docs/reference/model-effort-policy.md`). Codex twins carry only `name` + `description`.
- Native twins share one base name across `skills/claude/` and `skills/codex/`; the `-codex` suffix is reserved for the Claude launcher that runs Codex under the hood (`docs/decisions/0021-twin-skill-naming-and-delegation-hints.md`).
- `cog executor artifacts <run-dir>` takes only a run-dir; to make it flow-aware without changing the signature, persist the executor identity into run-dir state at `init` time (the same way `__cog_executor_init_write_state` already writes `input-kind`, `request.md`, `plan-source` via `cog::fn::rundir_path`).

## Implementation Steps

### First Step: Mark this round as started

In this plan's `queue-rounds.yaml`, set this round's (`item: implement-executor-single-and-decouple`) `status` to `doing`.

### Step 1: Flow descriptor SoT + engine helpers (`lib/functions/fn_executor.sh`)

Add the single source of truth keyed by **executor skill name**:

- `cog::fn::executor::flow_json <executor-name>` returns ordered phases + a `reviewed` flag. Reject unknown executors via `cog::fn::error_raise "InvalidInput"`.
  - `executor-lean` → `reviewed:true`, phases:

    ```text
    [{ordinal:stage1, phase:plan,      artifact:stage1-plan.md,          skippable:true},
     {ordinal:stage2, phase:review,    artifact:stage2-reviewed-plan.md, skippable:false},
     {ordinal:stage3, phase:execution, artifact:stage3-execution.md,     skippable:false}]
    ```

  - `executor-single` → `reviewed:false`, phases:

    ```text
    [{ordinal:stage1, phase:plan,      artifact:stage1-plan.md,      skippable:true},
     {ordinal:stage2, phase:execution, artifact:stage2-execution.md, skippable:false}]
    ```

  - `skippable:true` marks the **plan** phase (skipped on plan input) — derive it from `phase==plan`, not from the ordinal.
- Replace `cog::fn::executor::plan_engine_for_executor` with `cog::fn::executor::validate_engine <claude|codex>` (plan_engine = engine; reject other values).
- Rework `cog::fn::executor::select_reviewer_json` into reviewer derivation from `engine` + `flow.reviewed`: reviewed flows → `review_engine = other(engine)`, `reviewer = /review-plan-lean`; non-reviewed → `review_engine = none`, `reviewer = none`.
- Make `cog::fn::executor::artifact_name <executor-name> <ordinal>` read the flow descriptor (so `executor-single stage2` → `stage2-execution.md`). Keep the `summary` artifact name (`executor-summary.json`) flow-independent.

### Step 2: Engine/flow-agnostic classify-input (`lib/functions/fn_executor.sh`)

Change `cog::fn::executor::classify_input_json` to return only `{kind, value, plan_path}` (drop the hardwired `stages` array — stage selection moves to `init`, which knows the executor). Keep the existing classification rule: an existing readable regular `.md` file is `plan`; everything else, including a missing `.md` path, is `prompt`. Update the `classify-input` subcommand output (`__cog_executor_classify_input`) to stop printing `STAGES=`.

### Step 3: Phase-keyed artifacts v2 (`lib/functions/fn_executor.sh` + `cmd_executor.sh`)

- `cog::fn::executor::artifacts_json <run-dir>` resolves the executor from run-dir state (Step 5 persists it) and emits:

  ```text
  {schema:"cog.executor.artifacts.v2", executor, phases:[{ordinal,phase,artifact,path}], summary}
  ```

  where `path` = `cog::fn::rundir_path <run-dir> <artifact>`.
- Update the self-check in `cmd_executor.sh`:

  ```bash
  __cog_executor_artifacts_self_check='(.schema=="cog.executor.artifacts.v2") and (.phases|type=="array") and (.summary|type=="string")'
  ```

- Rewrite `__cog_executor_artifacts()` non-JSON output to iterate `phases[]` (e.g. emit one `PHASE_<ORDINAL>=<path>` line per phase plus `EXECUTOR_SUMMARY=`), dropping the fixed `STAGE2_REVIEWED_PLAN` line.

### Step 4: Phase-keyed summary v2 (`lib/functions/fn_executor.sh` + `cmd_executor.sh`)

- `cog::fn::executor::summary_json` takes `run-dir, executor, engine, input_kind, reviewer` plus a per-ordinal status map (variable length). Build the `stages` object from the flow's ordinals + the provided statuses; render `phase` and `artifact` per ordinal. Bump schema to `cog.executor.summary.v2`; update `__cog_executor_summary_self_check` accordingly.
- `__cog_executor_summary()`: parse `--executor`(skill) + `--engine`; accept `--stage1 --stage2` (+`--stage3` only for lean). Required stage flags = the flow's ordinals. Validation derives from the flow: the **plan** phase accepts `skipped|done|failed`; other phases `done|failed`. The reviewer must equal the flow-derived reviewer — generalize `__cog_executor_validate_reviewer` to accept `none` (for non-reviewed flows) and `/review-plan-lean` (for reviewed flows), and compare against the value derived from `engine` + `flow.reviewed`.

### Step 5: init rename + persist identity (`lib/commands/cmd_executor.sh`)

- `__cog_executor_init()`: parse `--executor <skill-name>` + `--engine <claude|codex>`; **remove** `--plan-engine` and its plan-input requirement. Validate executor via `flow_json`, engine via `validate_engine`.
- Persist `executor` and `engine` to run-dir state files (extend `__cog_executor_init_write_state`, reusing `cog::fn::rundir_path`). Change the rundir label to `"${executor}-${engine}"`.
- Compute `stages` (ordinals to run) from the flow: all ordinals for `kind==prompt`; drop the `skippable` (plan) ordinal for `kind==plan`.
- init JSON emits `{executor, engine, plan_engine, review_engine, reviewer, flow, stages, phases,
  artifacts}` (keep `review_engine`/`reviewer` as strings — `"none"` for single — so the init self-check `(.review_engine|type=="string")` still holds).

### Step 6: Usage + queue-prompts (`cmd_executor.sh`, `fn_executor.sh`)

- Rewrite `__cog_executor_usage()` to document `--executor <skill> --engine <claude|codex>` and the flow-driven summary (`--stage1 --stage2 [--stage3]`, `--reviewer <none|/review-plan-lean>`). Keep the line-2 `desc:` sentinel unchanged so `--help`, the man page, and help snapshots stay stable.
- Add to `cog::fn::executor::queue_prompts_json`:

  ```text
  {skill:"executor-single",        slash:"/executor-single",        accepts:["<prompt>","<plan.md>"], target_argument:null, stage_model:"executor-2-stage"}
  {skill:"executor-single-codex",  slash:"/executor-single-codex",  accepts:["<prompt>","<plan.md>"], target_argument:null, stage_model:"executor-2-stage"}
  ```

### Step 7: Migrate the `executor-lean` trio (skills)

In `skills/claude/executor-lean/SKILL.md`, `skills/codex/executor-lean/SKILL.md`, `skills/claude/executor-lean-codex/SKILL.md`: replace `--executor claude` → `--executor executor-lean --engine claude`; `--executor codex-session` → `--executor executor-lean --engine codex` (the launcher and codex twin use `--engine codex`). Remove every `--plan-engine` flag and the "path can't prove the engine" prose. Lean artifact names and behavior are unchanged.

### Step 8: New `executor-single` skills

- `skills/claude/executor-single/SKILL.md` (engine claude). Frontmatter mirrors `executor-lean` (`model: opus`, `effort: low`, `disable-model-invocation: true`, `allowed-tools: Bash Read Write Edit Agent Grep Glob`) + a `<!-- trigger-tests: "executor-single",
  ... -->` comment. No plan-emitter/gate markers (planning is delegated). Body: Stage 1 delegates to `/plan-one-lean` via the Agent tool (`--output <run-dir>/stage1-plan.md`), skipped when `input.kind==plan`; Stage 2 implements natively and writes `<run-dir>/stage2-execution.md`. Calls `cog executor init --executor executor-single --engine claude` and `cog executor summary --executor executor-single --engine claude --reviewer none --stage1 --stage2`.
- `skills/codex/executor-single/SKILL.md` (engine codex). Minimal frontmatter (`name`, `description`). Stage 1: `$plan-one-lean` prompt via `cog codex-runner run-exec --mode danger
  --access write --effort high` → `stage1-plan.md`; durable-job poll with `finalize --max-wall`. Stage 2: execution prompt via `cog codex-runner ... --effort medium` → `stage2-execution.md`. Include the phrases `Codex plans` and `Codex implements` so `is_executor_intent` keeps the `executor-*` prefix coherent.
- `skills/claude/executor-single-codex/SKILL.md` (Claude→Codex launcher, engine codex). Read `skills/claude/executor-lean-codex/SKILL.md` first and mirror its frontmatter and marker choices (including the plan-emitter + `cog-plan-mode-gate` markers if the lean launcher carries them) and `trigger-tests`. Runs the codex single-flow; init/summary use `--executor executor-single --engine codex`.

### Step 9: Tests (`test/integration/cmd_executor.bats`)

- Rename all lean calls to `--executor executor-lean --engine <claude|codex>`; drop `--plan-engine`.
- Update the `classify-input` test (no `.stages` field).
- Update `artifacts` assertions to the v2 `phases` shape; update `summary` assertions to v2 schema (`.schema=="cog.executor.summary.v2"`, `.executor=="executor-lean"`, engine present). Keep the reviewer-reject test (lean still requires `/review-plan-lean`).
- `queue-prompts`: change `(.prompts | length) == 3` → `== 5`; assert `/executor-single` and `/executor-single-codex` are present.
- **Add** single-flow cases: init prompt (`stages==["stage1","stage2"]`, `reviewer=="none"`, `phases[1].artifact` ends `stage2-execution.md`); init plan-input (plan phase skipped → `stages==["stage2"]`); artifacts (`stage2-execution.md`); summary (`--executor executor-single
  --engine codex --reviewer none --stage1 done --stage2 done` → v2, `ok==true`).

### Step 10: Docs + ADR

- `docs/decisions/0027-executor-stage-phase-decoupling.md` (0026 is now taken; confirm the next free number at implement time and bump if taken). Record: ordinals decoupled from phases via per-executor flow descriptors; `executor=skill` / `engine=agent` naming; the `executor-single` 2-phase flow; artifacts/summary schema v2. Add the index line to `docs/README.md`.
- `docs/reference/cli-commands.md`: update the `cog executor` section (new `--executor`/`--engine` flags, removed `--plan-engine`, phase-keyed schema, `--reviewer none`); add `executor-single` / `executor-single-codex` to the queue-prompts examples.
- `docs/reference/skills.md`: add `skills/claude/executor-single`, `skills/claude/executor-single-codex`, `skills/codex/executor-single` to the `### executor-*` list.

### Step 11: Migrate any remaining consumers of the old contract

Before finishing, sweep for stragglers and migrate each:

```bash
rg -n 'stage2_reviewed_plan|stage3_execution|stage1_plan|--plan-engine|codex-session|executor\.summary\.v1|plan_engine_for_executor' lib/ skills/ test/ docs/ completions/ man/
```

Confirm `lib/functions/fn_review_loop_input.sh` and the `review_plan_implementation_*` tests only reference the literal `stage2-reviewed-plan.md` (lean) — those are unaffected. Update any other hit.

### Final Step: Update the queue

1. In this plan's `queue-rounds.yaml`, set round `implement-executor-single-and-decouple` `status` to `done`.
2. This is the final round, so in `.implementation-plans/queue-plans.yaml` set this plan's (`item: executor-single-2-phase-executor`) `status` to `done`. Leave the plan directory in place.

## Acceptance Criteria

- [ ] `cog executor init --executor executor-single --engine codex --input "do X" --json` reports `reviewer=="none"`, `stages==["stage1","stage2"]`, and a `phases` entry whose `artifact` ends with `stage2-execution.md`.
- [ ] `cog executor init --executor executor-lean --engine claude --input "do X" --json` reports `stages==["stage1","stage2","stage3"]` and `reviewer=="/review-plan-lean"` (no behavior change).
- [ ] Plan input skips the plan phase: single → `stages==["stage2"]`, lean → `["stage2","stage3"]`.
- [ ] `cog executor artifacts <run-dir> --json` emits `schema=="cog.executor.artifacts.v2"` with a `phases[]` array for both flows.
- [ ] `cog executor summary --executor executor-single --engine codex --input-kind prompt
      --reviewer none --stage1 done --stage2 done --json` returns `ok==true`, schema v2.
- [ ] `cog executor` rejects `--plan-engine` (flag removed) and accepts `--engine`.
- [ ] `cog executor queue-prompts --json` lists 5 prompts including `/executor-single` and `/executor-single-codex`.
- [ ] `cog skill-lint` passes on all three `executor-single*` and all three migrated `executor-lean*` `SKILL.md` files.
- [ ] `just test` passes (including the updated `test/integration/cmd_executor.bats`), and `just lint` passes.
- [ ] ADR `0027-executor-stage-phase-decoupling.md` exists and is indexed in `docs/README.md`; `cli-commands.md` and `skills.md` reflect the new flags and skills.
- [ ] This plan's `queue-rounds.yaml` shows round `implement-executor-single-and-decouple` as `done`.
- [ ] The top-level `.implementation-plans/queue-plans.yaml` shows this plan as `done`.

## Next Round

This is the final round.
