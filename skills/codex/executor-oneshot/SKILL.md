---
name: executor-oneshot
description: >
  Execute one prompt or implementation plan through the Codex single executor
  flow: evaluate the input, prepare a good plan (generate when thin, cross-engine
  review when already detailed), then implement it via cog codex-runner.
---

<!-- cog-skill: input-fidelity -->

# Executor Single

Execute one prompt or one implementation plan through the gated 2-stage executor flow: an
input-evaluation gate guarantees a good plan, then Codex implements it. This skill owns sequencing and
judgment. Run directory setup, input classification, the quality verdict, producer resolution,
canonical artifact paths, Codex invocation, and executor summaries stay behind `cog`.

## Inputs

`$ARGUMENTS` is either a prompt/task description or an existing readable regular `.md` plan path.

Delegate classification and run setup to `cog executor`:

```bash
cog executor init --executor executor-oneshot --engine codex --input <prompt-or-plan> --json
```

Use the run directory and canonical artifact paths it returns (`prepared-plan.md`,
`execution-report.md`, `executor-summary.json`). For prompt input it writes `request.md`; for plan
input it writes `plan-source` with the supplied plan path.

## Execution Discipline

Every Codex run is a cog-owned durable job: `cog codex-runner run-exec` launches it with `--state` and
returns immediately, then poll-and-classify with one verb, `cog codex-runner finalize --max-wall
<secs>`. The exit code is the signal (0 ok, 1 failed, 75 still running); re-run finalize while it exits
75. Duration is never judged. Keep orchestration work foreground; never background it. Native effort is
passed with `--effort`.

## Input Evaluation (gate)

Determine whether the input already carries a good plan or needs one built. Delegate the verdict to the
canonical `assess-input` skill: build a prompt whose first line is the write orientation from `cog
codex-runner orientation write`, followed by `$assess-input`, `--run-dir <run-dir>`, and the original
input verbatim and in full. Launch it write-capable as a durable job so it can persist its verdict:

```bash
cog codex-runner run-exec --mode danger --access write --effort low --prompt <gate-prompt.md> --output <gate-output.md> --events <gate-events.jsonl> --stderr <gate-stderr.log> --state <gate.longrun.json>
cog codex-runner finalize --state <gate.longrun.json> --max-wall 300
```

Read the route from `<run-dir>/assess-input.json` (`needs-plan` or `good-input`); confirm with `cog
assess-input validate <run-dir>/assess-input.json`. Resolve the prepare-stage producer:

```bash
cog executor prepare-step --executor executor-oneshot --engine codex --route <needs-plan|good-input> --json
```

## Stage 1: Prepare The Plan

Write the prepared plan to `<run-dir>/prepared-plan.md`.

- **`needs-plan` → generate (`/plan-oneshot`, Codex).** Build a prompt whose first line is the write
  orientation, followed by `$plan-oneshot`, `--output <run-dir>/prepared-plan.md`, and the original
  task. The prompt is an enrichment-only superset of the original input: include the original task
  verbatim and in full, plus relevant repo constraints, and never replace it with a summary.
  `$plan-oneshot` saves its plan artifact to the output path. Launch write-capable, then
  poll-and-classify:

  ```bash
  cog codex-runner run-exec --mode danger --access write --effort high --prompt <prepare-prompt.md> --output <prepare-codex-output.md> --events <prepare-events.jsonl> --stderr <prepare-stderr.log> --state <prepare.longrun.json>
  cog codex-runner finalize --state <prepare.longrun.json> --max-wall 300
  ```

- **`good-input` → review (`/review-plan-oneshot`, Claude, cross-engine).** The existing plan is
  reviewed by the opposite engine for independence. This is a foreground Claude subagent delegation
  through the Task/Agent tool, not a `cog codex-runner` call. Ensure `<run-dir>/request.md` exists
  (init writes it for prompt input; for plan input, create a non-empty `request.md` capturing the
  supplied-plan source context verbatim and in full, with only enriching repo constraints). The
  delegation prompt instructs the Claude subagent to read
  `$HOME/.claude/skills/review-plan-oneshot/SKILL.md` and follow its Orchestrator Invocation Contract
  with three absolute paths — plan-path (the supplied plan path, or `<run-dir>/request.md` for
  inline-plan prompt input), request-path `<run-dir>/request.md`, and output-path
  `<run-dir>/prepared-plan.md` — and to return a one-line confirmation containing the output path.

After Stage 1, verify that `<run-dir>/prepared-plan.md` exists and is non-empty before continuing.

## Stage 2: Implement

Codex implements the prepared plan through `cog codex-runner` with native effort. Build a Stage 2
prompt under the run directory that carries only relevant session context:

- The prepared plan from `<run-dir>/prepared-plan.md`, verbatim. When it is an annotated review,
  implement the reconciled plan it specifies (apply APPROVED/MODIFIED/ADDED, skip REMOVED).
- The original request or supplied-plan source context, verbatim and in full, with only enriching
  repo constraints added.
- Current session constraints: do not run git commands unless explicitly authorized, follow
  `AGENTS.md` and `CLAUDE.md`, and stay inside the prepared plan.
- A required final implementation report covering files changed, commands run, deviations, and
  unresolved risks.

Run Codex with the write-capable `danger` sandbox; implementation must create and modify files. Launch
the durable job, then poll-and-classify:

```bash
cog codex-runner run-exec --mode danger --access write --effort medium --prompt <execution-prompt.md> --output <execution-report.md> --events <execution-events.jsonl> --stderr <execution-stderr.log> --state <execution.longrun.json>
cog codex-runner finalize --state <execution.longrun.json> --max-wall 300
```

Verify `<run-dir>/execution-report.md` exists and is non-empty.

## Summary

Emit an executor summary after Stage 2 or after a terminal stage failure:

```bash
cog executor summary --run-dir <run-dir> --executor executor-oneshot --engine codex --route <needs-plan|good-input> --prepare <done|failed> --execution <done|failed> --json
```

Status rules:

- The prepare stage always runs; report `--prepare done` on success.
- If Stage 1 fails, do not run Stage 2; emit the summary with failure statuses.
- If Stage 2 fails, still emit the summary with `--execution failed`.

## Error Handling

At every boundary, verify the durable postcondition before advancing:

- Gate: `<run-dir>/assess-input.json` exists and validates; the route is `needs-plan` or `good-input`.
- Stage 1: `prepared-plan.md` exists and is non-empty.
- Plan input: the supplied plan path exists and is readable before review or implementation.
- Stage 2: `execution-report.md` exists and is non-empty.
- Summary: `executor-summary.json` is written by `cog executor summary`.

On failure, stop the chain, preserve the run directory artifacts, and still emit the executor summary
using the status rules above. Do not infer status from prose when a `cog` command reports structured
output.

## Guardrails

- Codex runs are cog-owned durable jobs: `run-exec` launches, then poll-and-classify with
  `cog codex-runner finalize --max-wall <secs>`.
- Native effort only, via `--effort`.
- Do not run git commands unless explicitly authorized.
- Deterministic mechanics stay behind `cog executor`, `cog assess-input`, `cog codex-runner`,
  `/plan-oneshot`, and `/review-plan-oneshot`.
- This skill executes one prompt or plan.
