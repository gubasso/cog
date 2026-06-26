---
name: executor-oneshot
description: >
  Execute one prompt or implementation plan through the Claude single executor
  flow: evaluate the input, prepare a good plan (generate when thin, cross-engine
  review when already detailed), then implement it natively in session.
model: opus
effort: medium
argument-hint: "<prompt-or-plan-path>"
disable-model-invocation: true
allowed-tools: Bash Read Write Edit Agent Grep Glob
---

<!-- trigger-tests: "executor-oneshot", "execute one prompt through Claude single flow", "execute one plan through Claude single flow" -->
<!-- cog-skill: input-fidelity -->

# Executor Single

<!-- cog-plan-mode-gate -->

**Phase 0 — Plan-mode gate.** If Claude Code **plan mode** is active (a system-reminder says plan
mode is on / that you must not make edits), **STOP** before any other work — parsing args,
researching, interviewing, delegating, or writing. Tell the user in one line to exit plan mode
(`Shift+Tab`) and re-invoke `/executor-oneshot`. Do not call `ExitPlanMode`, and do not silently continue.

Execute one prompt or one implementation plan through the gated 2-stage executor flow: an
input-evaluation gate guarantees a good plan, then Claude implements it natively in the current
session. This skill owns sequencing and judgment. Run directory setup, input classification, the
quality verdict, producer resolution, canonical artifact paths, and executor summaries stay behind
`cog`.

## Inputs

`$ARGUMENTS` is either a prompt/task description or an existing readable regular `.md` plan path.

Delegate classification and run setup to `cog executor`:

```bash
cog executor init --executor executor-oneshot --engine claude --input <prompt-or-plan> --json
```

Use the run directory and canonical artifact paths it returns (`prepared-plan.md`,
`execution-report.md`, `executor-summary.json`). For prompt input it writes `request.md`; for plan
input it writes `plan-source` with the supplied plan path.

## Input Evaluation (gate)

Determine whether the input already carries a good plan or needs one built. Delegate the verdict to
the canonical `assess-input` skill through the **Agent tool** (`subagent_type: general-purpose`): the
delegation prompt instructs the subagent to read `$HOME/.claude/skills/assess-input/SKILL.md` and
follow it, passing `--run-dir <run-dir>` and the original input verbatim and in full. The subagent
writes `<run-dir>/assess-input.json` and returns the route.

Read the route from `<run-dir>/assess-input.json` (`needs-plan` or `good-input`); confirm the verdict
with `cog assess-input validate <run-dir>/assess-input.json`. Resolve the prepare-stage producer for
that route:

```bash
cog executor prepare-step --executor executor-oneshot --engine claude --route <needs-plan|good-input> --json
```

It returns the producer skill, the engine it runs on, and the invocation lane.

## Stage 1: Prepare The Plan

Write the prepared plan to `<run-dir>/prepared-plan.md`.

- **`needs-plan` → generate (`/plan-oneshot`, Claude, Agent lane).** Delegate plan generation to a
  foreground Claude subagent through the Agent tool (`subagent_type: general-purpose`) that reads
  `$HOME/.claude/skills/plan-oneshot/SKILL.md` and follows it, passing `--output
  <run-dir>/prepared-plan.md` and the original request as orientation. The delegation prompt is an
  enrichment-only superset of the original input: include the original request verbatim and in full,
  plus relevant repo constraints, and never replace it with a summary. The subagent runs
  non-interactively, treating every interview decision as a skill-chosen best default and recording
  it. The generated plan must include assumptions, ambiguities, dependencies, and risks.

- **`good-input` → review (`/review-plan-oneshot`, Codex, cross-engine).** The existing plan is
  reviewed by the opposite engine for independence. Ensure `<run-dir>/request.md` exists (init writes
  it for prompt input; for plan input, create a non-empty `request.md` capturing the supplied-plan
  source context verbatim and in full, with only enriching repo constraints). Build a Codex prompt
  whose first line is the write orientation from `cog codex-runner orientation write`, followed by
  `$review-plan-oneshot` and three absolute paths — plan-path (the supplied plan path, or
  `<run-dir>/request.md` for inline-plan prompt input), request-path `<run-dir>/request.md`, and
  output-path `<run-dir>/prepared-plan.md`. Launch the durable job write-capable, then
  poll-and-classify (exit code is the signal: 0 ok, 1 failed, 75 still running; re-run finalize while
  it exits 75; duration is never judged):

  ```bash
  cog codex-runner run-exec --mode danger --access write --effort high --prompt <prepare-prompt.md> --output <prepare-codex-output.md> --events <prepare-events.jsonl> --stderr <prepare-stderr.log> --state <prepare.longrun.json>
  cog codex-runner finalize --state <prepare.longrun.json> --max-wall 300
  ```

After Stage 1, verify that `<run-dir>/prepared-plan.md` exists and is non-empty before continuing.

## Stage 2: Implement

Implement natively in the current Claude session. Read and follow `<run-dir>/prepared-plan.md`; when it
is an annotated review, implement the reconciled plan it specifies (apply APPROVED/MODIFIED/ADDED
guidance, skip REMOVED).

Carry only relevant session context:

- The prepared plan, verbatim.
- The original request or supplied-plan source context, verbatim and in full, with only enriching
  repo constraints added.
- Current session constraints: do not run git commands unless explicitly authorized, follow
  `AGENTS.md` and `CLAUDE.md`, and stay inside the prepared plan.
- A required final implementation report covering files changed, commands run, deviations, and
  unresolved risks.

After implementation, write the final implementation report to `<run-dir>/execution-report.md`. Verify
that it exists and is non-empty.

## Summary

Emit an executor summary after Stage 2 or after a terminal stage failure:

```bash
cog executor summary --run-dir <run-dir> --executor executor-oneshot --engine claude --route <needs-plan|good-input> --prepare <done|failed> --execution <done|failed> --json
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

- Keep the gate, plan preparation, Claude implementation, and orchestration foreground; never
  background them. Codex review runs as a cog-owned durable job.
- Native Codex effort only, via `--effort`.
- Do not run git commands unless explicitly authorized.
- Deterministic mechanics stay behind `cog executor`, `cog assess-input`, `cog codex-runner`,
  `/plan-oneshot`, and `/review-plan-oneshot`.
- This skill executes one prompt or plan.
