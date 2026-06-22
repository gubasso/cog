---
name: executor-lean-codex
description: >
  Execute one prompt or implementation plan through the Codex-backed lean
  executor flow from Claude: Codex plans, Claude reviews, then Codex implements.
model: opus
effort: low
argument-hint: "<prompt-or-plan-path>"
disable-model-invocation: true
allowed-tools: Bash Read Write Agent Grep Glob
---

<!-- trigger-tests: "executor-lean-codex", "execute one prompt through Codex from Claude", "Codex plans and implements while Claude reviews" -->
<!-- cog-skill: plan-emitter -->
<!-- cog-plan-mode-gate -->

# Executor Lean Codex

## Phase 0: Plan Mode Gate

If Claude Code plan mode is active, STOP before parsing args, creating artifacts, delegating, or
invoking Codex. Tell the user to exit plan mode with `Shift+Tab` and re-invoke
`/executor-lean-codex`.

Execute one prompt or plan through the Codex-backed three-stage executor flow. Codex plans when
needed, Claude reviews the Codex-made plan through `/review-plan-lean`, and Codex implements the
reviewed plan. This launcher owns sequencing and postcondition checks; deterministic run setup,
artifact paths, Codex invocation, and summaries stay behind `cog`.

## Bootstrap

Delegate classification and run setup to:

```bash
cog executor init --executor codex-session --input <prompt-or-plan> [--plan-engine codex] --json
```

For prompt input, omit `--plan-engine`. For plan input, pass `--plan-engine codex`. Use the returned
run directory and artifact paths. If plan input skipped Stage 1, create a non-empty
`<RUN_DIR>/request.md` that records the supplied plan source and original request context before
Stage 2.

## Stage 1: Plan With Codex

Run only for prompt input. Write `<RUN_DIR>/stage1-prompt.md` with `$plan-one-lean`, the write
orientation from `cog codex-runner orientation write`, `--output <RUN_DIR>/stage1-plan.md`, and the
original request. Then run Codex in the foreground:

```bash
cog codex-runner run-exec --mode danger --access write --effort high --prompt <RUN_DIR>/stage1-prompt.md --output <RUN_DIR>/stage1-codex-output.md --events <RUN_DIR>/stage1-events.jsonl --stderr <RUN_DIR>/stage1-stderr.log --thread last
```

Verify `<RUN_DIR>/stage1-plan.md` exists and is non-empty before Stage 2.

## Stage 2: Review With Claude

Review the Codex-made plan through a foreground Agent delegation to `/review-plan-lean`. The Agent
prompt tells the subagent to read `$HOME/.claude/skills/review-plan-lean/SKILL.md` and invoke the
skill in orchestrator mode with exactly three absolute paths:

```text
1. plan-path: <RUN_DIR>/stage1-plan.md or the supplied plan path
2. request-path: <RUN_DIR>/request.md
3. output-path: <RUN_DIR>/stage2-reviewed-plan.md
```

Verify `<RUN_DIR>/stage2-reviewed-plan.md` exists and is non-empty before Stage 3.

## Stage 3: Implement With Codex

Write `<RUN_DIR>/stage3-prompt.md` with the write orientation, the reviewed plan verbatim, the
original request or supplied-plan context, the active repository constraints, and a required final
report covering files changed, deviations, commands run, and unresolved risks. Then run Codex in the
foreground:

```bash
cog codex-runner run-exec --mode danger --access write --effort medium --prompt <RUN_DIR>/stage3-prompt.md --output <RUN_DIR>/stage3-execution.md --events <RUN_DIR>/stage3-events.jsonl --stderr <RUN_DIR>/stage3-stderr.log
```

Verify `<RUN_DIR>/stage3-execution.md` exists and is non-empty.

## Summary

Emit the executor summary with the collapsed reviewer name:

```bash
cog executor summary --run-dir <RUN_DIR> --executor codex-session --input-kind <prompt|plan> --plan-engine codex --reviewer /review-plan-lean --stage1 <skipped|done|failed> --stage2 <done|failed> --stage3 <done|failed> --json
```

Stop the chain on any failed stage, preserve the run directory artifacts, and still emit the summary
when enough stage status is known.

## Guardrails

- Foreground only; never background Codex, Agent delegation, or orchestration work.
- Use native Codex effort through `--effort`; never use legacy profiles.
- Do not run git commands.
- Keep deterministic mechanics behind `cog executor`, `cog codex-runner`, and `/review-plan-lean`.
