---
name: executor-single-codex
description: >
  Execute one prompt or implementation plan through the Codex-backed single
  executor flow from Claude: Codex plans when needed, then Codex implements.
model: opus
effort: low
argument-hint: "<prompt-or-plan-path>"
disable-model-invocation: true
allowed-tools: Bash Read Write Agent Grep Glob
---

<!-- trigger-tests: "executor-single-codex", "execute one prompt through Codex single flow from Claude", "Codex plans and implements without plan review" -->
<!-- cog-skill: plan-emitter -->
<!-- cog-plan-mode-gate -->

# Executor Single Codex

## Phase 0: Plan Mode Gate

If Claude Code plan mode is active, STOP before parsing args, creating artifacts, delegating, or
invoking Codex. Tell the user to exit plan mode with `Shift+Tab` and re-invoke
`/executor-single-codex`.

Execute one prompt or plan through the Codex-backed two-stage executor flow. Codex plans when needed,
then Codex implements the plan. This launcher owns sequencing and postcondition checks;
deterministic run setup, artifact paths, Codex invocation, and summaries stay behind `cog`.

## Bootstrap

Delegate classification and run setup to:

```bash
cog executor init --executor executor-single --engine codex --input <prompt-or-plan> --json
```

Use the returned run directory and artifact paths. If plan input skipped Stage 1, create a non-empty
`<RUN_DIR>/request.md` that records the supplied plan source and original request context before
Stage 2.

## Stage 1: Plan With Codex

Run only for prompt input. Write `<RUN_DIR>/stage1-prompt.md` with `$plan-one-lean`, the write
orientation from `cog codex-runner orientation write`, `--output <RUN_DIR>/stage1-plan.md`, and the
original request. Then launch the durable Codex job and poll-and-classify with
`cog codex-runner finalize --max-wall <secs>`; the exit code is the signal (0 ok, 1 failed, 75 still
running), re-run finalize while it exits 75, and duration is never judged:

```bash
cog codex-runner run-exec --mode danger --access write --effort high --prompt <RUN_DIR>/stage1-prompt.md --output <RUN_DIR>/stage1-codex-output.md --events <RUN_DIR>/stage1-events.jsonl --stderr <RUN_DIR>/stage1-stderr.log --thread last --state <RUN_DIR>/stage1.longrun.json
cog codex-runner finalize --state <RUN_DIR>/stage1.longrun.json --max-wall 300
```

`--output` captures Codex's final message; the plan artifact `<RUN_DIR>/stage1-plan.md` is written by
`$plan-one-lean`. Verify it exists and is non-empty before Stage 2.

## Stage 2: Implement With Codex

Write `<RUN_DIR>/stage2-prompt.md` with the write orientation, the plan input verbatim, the original
request or supplied-plan context, the active repository constraints, and a required final report
covering files changed, deviations, commands run, and unresolved risks. Then launch the durable
Codex job and poll-and-classify with `cog codex-runner finalize --max-wall <secs>`; the exit code is
the signal (0 ok, 1 failed, 75 still running), re-run finalize while it exits 75, and duration is
never judged:

```bash
cog codex-runner run-exec --mode danger --access write --effort medium --prompt <RUN_DIR>/stage2-prompt.md --output <RUN_DIR>/stage2-execution.md --events <RUN_DIR>/stage2-events.jsonl --stderr <RUN_DIR>/stage2-stderr.log --state <RUN_DIR>/stage2.longrun.json
cog codex-runner finalize --state <RUN_DIR>/stage2.longrun.json --max-wall 300
```

Verify `<RUN_DIR>/stage2-execution.md` exists and is non-empty.

## Summary

Emit the executor summary with reviewer `none`:

```bash
cog executor summary --run-dir <RUN_DIR> --executor executor-single --engine codex --input-kind <prompt|plan> --reviewer none --stage1 <skipped|done|failed> --stage2 <done|failed> --json
```

Stop the chain on any failed stage, preserve the run directory artifacts, and still emit the summary
when enough stage status is known.

## Guardrails

- Codex runs are cog-owned durable jobs: `run-exec` launches, then poll-and-classify with
  `cog codex-runner finalize --max-wall <secs>`.
- Use native Codex effort through `--effort`; never use legacy profiles.
- Do not run git commands.
- Keep deterministic mechanics behind `cog executor` and `cog codex-runner`.
