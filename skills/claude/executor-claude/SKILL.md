---
name: executor-claude
description: >
  Execute one prompt or implementation plan through the Claude executor flow:
  Claude plans when needed, Codex reviews Claude-made plans, then Claude implements
  the reviewed plan natively in session.
model: opus
effort: low
argument-hint: "<prompt-or-plan-path>"
disable-model-invocation: true
allowed-tools: Bash Read Write Edit Grep Glob
---

<!-- trigger-tests: "executor-claude", "execute one prompt through Claude", "execute one plan through Claude" -->

# Executor Claude

Execute one prompt or one implementation plan through the shared 3-stage executor flow:
Claude plans when needed, Codex reviews the Claude-made plan, then Claude implements
the reviewed plan natively in the current session. This skill owns sequencing and
judgment. Run directory setup, input classification, canonical artifact paths,
OTHER-engine reviewer selection, Codex invocation, and executor summaries stay
behind `cog`.

This mirrors `skills/codex/executor-codex-session/SKILL.md` with engine roles
inverted. Stage 3 is native Claude implementation in this session, not a Codex
call.

This skill uses the `executor-*` taxonomy prefix and does not carry the
`cog-skill` plan-emitter marker or the `cog-plan-mode-gate` Phase 0 marker.
All plan emission is delegated to `/plan-claude`, which carries its own Phase 0
plan-mode gate. Per
`docs/decisions/0015-plan-skills-not-in-plan-mode.md` and
`docs/reference/skill-contract.md` ("Plan-mode gate"), `cog skill-lint` requires
the gate stanza only for Claude skills carrying the plan-emitter marker.

## Inputs

`$ARGUMENTS` is either a prompt/task description or an existing readable regular
`.md` plan path.

Delegate classification and run setup to `cog executor`:

```bash
cog executor init --executor claude --input <prompt-or-plan> [--plan-engine claude] --json
```

For prompt input, omit `--plan-engine`; `cog executor init` resolves
`plan_engine=claude`, reviewer `/review-plan-codex`, and stages
`stage1,stage2,stage3`.

For plan input, pass `--plan-engine claude`. The path alone cannot prove which
engine made the plan, and this executor handles Claude-made plans reviewed by
Codex.

Stage 1 is skipped exactly when the init JSON reports `.input.kind` as `plan`. A
supplied path that is not a readable regular `.md` file is prompt text according
to `cog executor`; do not reimplement that check.

## Execution Discipline

Use foreground execution only; never background the Codex review, Claude
implementation, subagent work, or orchestration work. Each Codex call blocks
until `cog codex-runner` returns. Native effort is passed with `--effort`; do
not use legacy profile-based invocation.

Stage 2 runs Codex through `cog codex-runner run-exec --mode native --effort
high`. Stage 3 is implemented by Claude in the current session, not through
`cog codex-runner`.

Stage boundaries must verify durable postconditions before advancing. An output
artifact must exist and be non-empty before the next stage starts.

Do not run git commands unless the orchestrator or user explicitly authorizes
them.

## Bootstrap

Use the run directory and artifact paths returned by `cog executor init`. When
needed, confirm canonical paths with:

```bash
cog executor artifacts <run-dir> --json
```

Canonical artifacts for this executor are:

```text
stage1-plan.md
stage2-reviewed-plan.md
stage3-execution.md
executor-summary.json
```

For prompt input, `cog executor init` writes `request.md` under the run
directory.

For plan input, `cog executor init` writes `plan-source`, containing the
supplied plan path, and does not create `request.md`. Before building the Stage
2 prompt, create a non-empty `<run-dir>/request.md` that captures the original
task or supplied-plan source context. This run-scoped request artifact satisfies
`/review-plan-codex`'s orchestrator contract. All other deterministic artifact
path mechanics come from `cog`.

The Stage 2 Codex runner files are run-scoped capture files, not canonical
executor artifacts returned by `cog executor artifacts`:

```text
stage2-prompt.md
stage2-codex-output.md
stage2-events.jsonl
stage2-stderr.log
```

## Stage 1: Plan

Run this stage only when input kind is `prompt`.

Invoke `/plan-claude` natively in the current Claude session. Pass the output
path or otherwise instruct the plan to be written to
`<run-dir>/stage1-plan.md`, using the original request as the orientation. The
generated plan must include assumptions, ambiguities, dependencies, and risks.

The Stage 2 plan input is:

- Prompt input: `<run-dir>/stage1-plan.md`.
- Plan input: the supplied plan path recorded by `cog executor init`.

After Stage 1, verify that `<run-dir>/stage1-plan.md` exists and is non-empty
before continuing.

## Stage 2: Review Plan

Claude-made plans are reviewed by Codex via `/review-plan-codex`. Use the
reviewer returned by `cog executor init`; for this executor, it must be
`/review-plan-codex`.

Build a prompt file under the run directory that instructs Codex to invoke
`/review-plan-codex` with exactly three absolute paths:

```text
1. plan-path: <stage1-plan.md or the supplied plan path>
2. request-path: <run-dir>/request.md
3. output-path: <run-dir>/stage2-reviewed-plan.md
```

The reviewer reads shared filesystem artifacts. Do not inline the full plan
into the prompt unless recovery requires it.

Run Codex in the foreground with native effort:

```bash
cog codex-runner run-exec --mode native --effort high --prompt <stage2-prompt.md> --output <stage2-codex-output.md> --events <stage2-events.jsonl> --stderr <stage2-stderr.log>
```

Treat `<run-dir>/stage2-reviewed-plan.md` as the authoritative review artifact.
The runner output is only Codex transcript/final-message capture. After the
Codex review returns, verify that `<run-dir>/stage2-reviewed-plan.md` exists and
is non-empty before continuing.

## Stage 3: Implement

Implement natively in the current Claude session. Read and follow
`<run-dir>/stage2-reviewed-plan.md` verbatim.

Carry only relevant session context:

- The reviewed plan from `<run-dir>/stage2-reviewed-plan.md`, verbatim.
- The original request or supplied-plan source context.
- A short statement that the reviewed plan supersedes any earlier plan.
- Current session constraints: do not run git commands unless explicitly
  authorized, follow `AGENTS.md` and `CLAUDE.md`, and stay inside the reviewed
  plan.
- A required final implementation report covering files changed, commands run,
  deviations, and unresolved risks.

After implementation, write the final implementation report to
`<run-dir>/stage3-execution.md`. Verify that it exists and is non-empty.

## Summary

Emit an executor summary after Stage 3 or after a terminal stage failure:

```bash
cog executor summary --run-dir <run-dir> --executor claude --input-kind <prompt|plan> --plan-engine claude --reviewer /review-plan-codex --stage1 <skipped|done|failed> --stage2 <done|failed> --stage3 <done|failed> --json
```

Status rules:

- Prompt input with successful planning uses `--stage1 done`.
- Plan input uses `--stage1 skipped`.
- If Stage 1 fails, do not run Stage 2 or Stage 3; emit the summary with
  failure statuses.
- If Stage 2 fails, do not run Stage 3.
- If Stage 3 fails, still emit the summary with `--stage3 failed`.

## Error Handling

At every boundary, verify the durable postcondition before advancing:

- Stage 1, when run: `stage1-plan.md` exists and is non-empty.
- Plan input: the supplied plan path exists and is readable before delegation.
- Plan input: `<run-dir>/request.md` exists and is non-empty before building the
  Stage 2 prompt.
- Stage 2: `stage2-reviewed-plan.md` exists and is non-empty.
- Stage 3: `stage3-execution.md` exists and is non-empty.
- Summary: `executor-summary.json` is written by `cog executor summary`.

On failure, stop the chain, preserve the run directory artifacts, and still emit
the executor summary using the status rules above. Do not infer status from
prose when a `cog` command reports structured output.

## Guardrails

- Foreground only; never background the Codex review, Claude implementation, or
  orchestration work.
- Native Codex effort only, via `--effort`.
- No legacy profile-based invocation anywhere.
- Do not instruct a runtime read of maintenance-reference conventions.
- Deterministic mechanics stay behind `cog executor`, `cog codex-runner`,
  `/plan-claude`, and `/review-plan-codex`.
- Do not use inline shell functions, loops, or text-parsing routines.
- Do not run git commands unless explicitly authorized.
- This skill executes one prompt or plan. It does not modify `cog executor`,
  `cog codex-runner`, the Codex sibling, or queue integration.
