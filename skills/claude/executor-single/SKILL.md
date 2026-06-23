---
name: executor-single
description: >
  Execute one prompt or implementation plan through the Claude single executor
  flow: Claude plans when needed, then Claude implements the plan natively in
  session.
model: opus
effort: low
argument-hint: "<prompt-or-plan-path>"
disable-model-invocation: true
allowed-tools: Bash Read Write Edit Agent Grep Glob
---

<!-- trigger-tests: "executor-single", "execute one prompt through Claude single flow", "execute one plan through Claude single flow" -->

# Executor Single

Execute one prompt or one implementation plan through the shared 2-stage executor flow:
Claude plans when needed, then Claude implements the plan natively in the current session. This skill
owns sequencing and judgment. Run directory setup, input classification, canonical artifact paths,
and executor summaries stay behind `cog`.

## Inputs

`$ARGUMENTS` is either a prompt/task description or an existing readable regular `.md` plan path.

Delegate classification and run setup to `cog executor`:

```bash
cog executor init --executor executor-single --engine claude --input <prompt-or-plan> --json
```

Stage 1 is skipped exactly when the init JSON reports `.input.kind` as `plan`. A supplied path that
is not a readable regular `.md` file is prompt text according to `cog executor`; do not reimplement
that check.

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
original task or supplied-plan source context when the implementation prompt needs that context.

## Stage 1: Plan

Run this stage only when input kind is `prompt`.

Delegate plan generation to a foreground Claude subagent through the Agent tool
(`subagent_type: general-purpose`). The delegation prompt instructs the subagent to read
`$HOME/.claude/skills/plan-one-lean/SKILL.md` and follow it end-to-end, passing
`--output <run-dir>/stage1-plan.md` and using the original request as the orientation. The subagent
runs non-interactively: it treats every interview decision as a skill-chosen best default and records
it. The generated plan must include assumptions, ambiguities, dependencies, and risks.

The Stage 2 plan input is:

- Prompt input: `<run-dir>/stage1-plan.md`.
- Plan input: the supplied plan path recorded by `cog executor init`.

After Stage 1, verify that `<run-dir>/stage1-plan.md` exists and is non-empty before continuing.

## Stage 2: Implement

Implement natively in the current Claude session. Read and follow the Stage 2 plan input.

Carry only relevant session context:

- The plan input, verbatim.
- The original request or supplied-plan source context.
- Current session constraints: do not run git commands unless explicitly authorized, follow
  `AGENTS.md` and `CLAUDE.md`, and stay inside the plan.
- A required final implementation report covering files changed, commands run, deviations, and
  unresolved risks.

After implementation, write the final implementation report to `<run-dir>/stage2-execution.md`.
Verify that it exists and is non-empty.

## Summary

Emit an executor summary after Stage 2 or after a terminal stage failure:

```bash
cog executor summary --run-dir <run-dir> --executor executor-single --engine claude --input-kind <prompt|plan> --reviewer none --stage1 <skipped|done|failed> --stage2 <done|failed> --json
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

- Keep Claude implementation and orchestration foreground.
- Do not run git commands unless explicitly authorized.
- Deterministic mechanics stay behind `cog executor` and `/plan-one-lean`.
- This skill executes one prompt or plan.
