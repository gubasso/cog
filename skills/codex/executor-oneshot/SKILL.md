---
name: executor-oneshot
description: >
  Execute one prompt or implementation plan through the Codex single executor
  flow: Codex plans when needed, then Codex implements the plan via
  cog codex-runner.
---

<!-- cog-skill: input-fidelity -->

# Executor Single

Execute one prompt or one implementation plan through the shared 2-stage executor flow:
Codex plans when needed, then Codex implements the plan. This skill owns sequencing and judgment.
Run directory setup, input classification, canonical artifact paths, Codex invocation, and executor
summaries stay behind `cog`.

## Inputs

`$ARGUMENTS` is either a prompt/task description or an existing readable regular `.md` plan path.

Delegate classification and run setup to `cog executor`:

```bash
cog executor init --executor executor-oneshot --engine codex --input <prompt-or-plan> --json
```

Stage 1 is skipped exactly when the init JSON reports `.input.kind` as `plan`. A supplied path that
is not a readable regular `.md` file is prompt text according to `cog executor`; do not reimplement
that check.

## Execution Discipline

Every Codex run is a cog-owned durable job: `cog codex-runner run-exec` launches it with `--state`
and returns immediately, then poll-and-classify with one verb,
`cog codex-runner finalize --max-wall <secs>`. The exit code is the signal (0 ok, 1 failed, 75 still
running); re-run finalize while it exits 75. Duration is never judged. Keep orchestration work
foreground; never background it yourself. Native effort is passed with `--effort`.

Stage boundaries must verify durable postconditions before advancing. An output artifact must exist
and be non-empty before the next stage starts.

## Bootstrap

Use the run directory and artifact paths returned by `cog executor init`. When needed, confirm
canonical paths with:

```bash
cog executor artifacts <run-dir> --json
```

Canonical artifacts for this executor are:

```text
stage1-plan.md
stage2-execution.md
executor-summary.json
```

For prompt input, `cog executor init` writes `request.md` under the run directory.

For plan input, `cog executor init` writes `plan-source`, containing the supplied plan path, and does
not create `request.md`. Before Stage 2, create a non-empty `<run-dir>/request.md` that captures the
original task or supplied-plan source context.

## Stage 1: Plan

Run this stage only when input kind is `prompt`.

Build a prompt file under the run directory whose literal first line is `$plan-oneshot`, followed
by `--output <run-dir>/stage1-plan.md`, the original task, and the request to report any
assumptions, ambiguities, dependencies, and risks. The prompt is an enrichment-only superset of the
original input: include the original task verbatim and in full, plus relevant repo constraints, and
never replace it with a summary. `$plan-oneshot` saves its own plan artifact to
`<run-dir>/stage1-plan.md` through `cog plan-doc`.

Use native effort with the write-capable `danger` sandbox through `cog codex-runner`. Launch the
durable job, then poll-and-classify:

```bash
cog codex-runner run-exec --mode danger --access write --effort high --prompt <stage1-prompt.md> --output <stage1-codex-output.md> --events <stage1-events.jsonl> --stderr <stage1-stderr.log> --state <stage1.longrun.json>
cog codex-runner finalize --state <stage1.longrun.json> --max-wall 300
```

The Stage 2 plan input is:

- Prompt input: `<run-dir>/stage1-plan.md`.
- Plan input: the supplied plan path recorded by `cog executor init`.

Verify that the Stage 2 plan input exists and is non-empty before continuing.

## Stage 2: Implement

Codex implements the Stage 2 plan input through `cog codex-runner` with native effort. Build a
Stage 2 prompt under the run directory that carries only relevant session context:

- The plan input, verbatim.
- The original request or supplied-plan source context, verbatim and in full, with only enriching
  repo constraints added.
- Current session constraints: do not run git commands unless explicitly authorized, follow
  `AGENTS.md` and `CLAUDE.md`, and stay inside the plan.
- A required final implementation report covering files changed, commands run, deviations, and
  unresolved risks.

Run Codex with the write-capable `danger` sandbox. Implementation must create and modify files,
which read-only sandboxes block. Launch the durable job, then poll-and-classify:

```bash
cog codex-runner run-exec --mode danger --access write --effort medium --prompt <stage2-prompt.md> --output <stage2-execution.md> --events <stage2-events.jsonl> --stderr <stage2-stderr.log> --state <stage2.longrun.json>
cog codex-runner finalize --state <stage2.longrun.json> --max-wall 300
```

Verify `<run-dir>/stage2-execution.md` exists and is non-empty.

## Summary

Emit an executor summary after Stage 2 or after a terminal stage failure:

```bash
cog executor summary --run-dir <run-dir> --executor executor-oneshot --engine codex --input-kind <prompt|plan> --reviewer none --stage1 <skipped|done|failed> --stage2 <done|failed> --json
```

Status rules:

- Prompt input with successful planning uses `--stage1 done`.
- Plan input uses `--stage1 skipped`.
- If Stage 1 fails, do not run Stage 2; emit the summary with failure statuses.
- If Stage 2 fails, still emit the summary with `--stage2 failed`.

## Error Handling

At every boundary, verify the durable postcondition before advancing:

- Stage 1, when run: `stage1-plan.md` exists and is non-empty.
- Plan input: the supplied plan path exists and is readable before implementation.
- Stage 2: `stage2-execution.md` exists and is non-empty.
- Summary: `executor-summary.json` is written by `cog executor summary`.

On failure, stop the chain, preserve the run directory artifacts, and still emit the executor summary
using the status rules above. Do not infer status from prose when a `cog` command reports structured
output.

## Guardrails

- Codex runs are cog-owned durable jobs: `run-exec` launches, then poll-and-classify with
  `cog codex-runner finalize --max-wall <secs>`.
- Native effort only, via `--effort`.
- Do not run git commands unless explicitly authorized.
- Deterministic mechanics stay behind `cog executor` and `cog codex-runner`.
- This skill executes one prompt or plan.
