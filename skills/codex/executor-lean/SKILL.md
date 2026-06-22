---
name: executor-lean
description: >
  Execute one prompt or implementation plan through the Codex-session executor flow:
  Codex plans when needed, Claude reviews Codex-made plans, then Codex implements the
  reviewed plan via cog codex-runner.
---

# Executor Codex Session

Execute one prompt or one implementation plan through the shared 3-stage executor flow:
Codex plans when needed, Claude reviews the Codex-made plan, then Codex implements the
reviewed plan. This skill owns sequencing and judgment. Run directory setup, input
classification, canonical artifact paths, Codex invocation, and executor summaries stay
behind `cog`.

## Inputs

`$ARGUMENTS` is either a prompt/task description or an existing readable regular `.md`
plan path.

Delegate classification and run setup to `cog executor`:

```bash
cog executor init --executor codex-session --input <prompt-or-plan> [--plan-engine codex] --json
```

For prompt input, omit `--plan-engine`; `cog executor init` resolves
`plan_engine=codex`, reviewer `/review-plan-lean`, and stages
`stage1,stage2,stage3`.

For plan input, pass `--plan-engine codex`. The path alone cannot prove which engine
made the plan, and this executor handles Codex-made plans reviewed by Claude.

Stage 1 is skipped exactly when the init JSON reports `.input.kind` as `plan`. A
supplied path that is not a readable regular `.md` file is prompt text according to
`cog executor`; do not reimplement that check.

## Execution Discipline

Every Codex run is a cog-owned durable job: `cog codex-runner run-exec` launches it with `--state`
and returns immediately, then poll-and-classify with one verb,
`cog codex-runner finalize --max-wall <secs>`. The exit code is the signal (0 ok · 1 failed · 75
still running); re-run finalize while it exits 75. A coding agent runs as long as it needs — duration
is never judged. Keep orchestration work foreground; never background it yourself. Native effort is
passed with `--effort`; do not use legacy profile-based invocation.

Stage boundaries must verify durable postconditions before advancing. An output artifact
must exist and be non-empty before the next stage starts.

## Bootstrap

Use the run directory and artifact paths returned by `cog executor init`. When needed,
confirm canonical paths with:

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

For prompt input, `cog executor init` writes `request.md` under the run directory.

For plan input, `cog executor init` writes `plan-source`, containing the supplied plan
path, and does not create `request.md`. Before Stage 2, create a non-empty
`<run-dir>/request.md` that captures the original task or supplied-plan source context.
This run-scoped request artifact satisfies `/review-plan-lean`'s orchestrator
contract. All other deterministic artifact path mechanics come from `cog`.

## Stage 1: Plan

Run this stage only when input kind is `prompt`.

Build a prompt file under the run directory whose literal first line is `$plan-one-lean`,
followed by `--output <run-dir>/stage1-plan.md`, the original task, and the request to
report any assumptions, ambiguities, dependencies, and risks. `$plan-one-lean` saves its
own plan artifact to `<run-dir>/stage1-plan.md` through `cog plan-doc`.

Use native effort with the write-capable `danger` sandbox through `cog codex-runner`.
`$plan-one-lean` saves its plan artifact through `cog plan-doc`, which a read-only sandbox
blocks. The runner's `--output` captures Codex's final message in a separate
`<run-dir>/stage1-codex-output.md` file, leaving the plan artifact untouched. Launch the durable job,
then poll-and-classify:

```bash
cog codex-runner run-exec --mode danger --access write --effort high --prompt <stage1-prompt.md> --output <stage1-codex-output.md> --events <stage1-events.jsonl> --stderr <stage1-stderr.log> --state <stage1.longrun.json>
# Re-run while it exits 75 (still running). Duration is never judged; exit code is the signal: 0 ok, 1 failed, 75 still running.
cog codex-runner finalize --state <stage1.longrun.json> --max-wall 300
```

The Stage 2 plan input is:

- Prompt input: `<run-dir>/stage1-plan.md`.
- Plan input: the supplied plan path recorded by `cog executor init`.

## Stage 2: Review Plan

Codex-made plans are reviewed by Claude via `/review-plan-lean`. Use the reviewer
returned by `cog executor init`; for this executor, it must be `/review-plan-lean`.
This is a foreground Claude subagent delegation through Task/Agent, not a
`cog codex-runner` call.

Pass three absolute paths in the delegation prompt:

```text
1. plan-path: <stage1-plan.md or the supplied plan path>
2. request-path: <run-dir>/request.md
3. output-path: <run-dir>/stage2-reviewed-plan.md
```

The reviewer reads shared filesystem artifacts. Do not inline the full plan into the
delegation prompt unless recovery requires it. After the delegate returns, verify that
`<run-dir>/stage2-reviewed-plan.md` exists and is non-empty before continuing.

## Stage 3: Implement

Run implementation through `cog codex-runner` with native effort. Build a Stage 3 prompt
under the run directory that carries only relevant session context:

- The reviewed plan from `<run-dir>/stage2-reviewed-plan.md`, verbatim.
- The original request or supplied-plan source context.
- A short statement that the reviewed plan supersedes any earlier plan.
- Current session constraints: do not run git commands unless explicitly authorized,
  follow `AGENTS.md` and `CLAUDE.md`, and stay inside the reviewed plan.
- A required final implementation report covering files changed, commands run,
  deviations, and unresolved risks.

Run Codex with the write-capable `danger` sandbox. Implementation must create and
modify files, which the read-only `native`/`fallback`/`quick-auto` sandboxes
block. Launch the durable job, then poll-and-classify:

```bash
cog codex-runner run-exec --mode danger --access write --effort medium --prompt <stage3-prompt.md> --output <stage3-execution.md> --events <stage3-events.jsonl> --stderr <stage3-stderr.log> --state <stage3.longrun.json>
# Re-run while it exits 75 (still running). Duration is never judged; exit code is the signal: 0 ok, 1 failed, 75 still running.
cog codex-runner finalize --state <stage3.longrun.json> --max-wall 300
```

Do not send runtime instructions to read maintenance references. Include the needed
orientation in the prompt itself.

## Summary

Emit an executor summary after Stage 3 or after a terminal stage failure:

```bash
cog executor summary --run-dir <run-dir> --executor codex-session --input-kind <prompt|plan> --plan-engine codex --reviewer /review-plan-lean --stage1 <skipped|done|failed> --stage2 <done|failed> --stage3 <done|failed> --json
```

Status rules:

- Prompt input with successful planning uses `--stage1 done`.
- Plan input uses `--stage1 skipped`.
- If Stage 1 fails, do not run Stage 2 or Stage 3; emit the summary with failure statuses.
- If Stage 2 fails, do not run Stage 3.
- If Stage 3 fails, still emit the summary with `--stage3 failed`.

## Error Handling

At every boundary, verify the durable postcondition before advancing:

- Stage 1, when run: `stage1-plan.md` exists and is non-empty.
- Plan input: the supplied plan path exists and is readable before delegation.
- Stage 2: `stage2-reviewed-plan.md` exists and is non-empty.
- Stage 3: `stage3-execution.md` exists and is non-empty.
- Summary: `executor-summary.json` is written by `cog executor summary`.

On failure, stop the chain, preserve the run directory artifacts, and still emit the
executor summary using the status rules above. Do not infer status from prose when a
`cog` command reports structured output.

## Guardrails

- Codex runs are cog-owned durable jobs: `run-exec` launches, then poll-and-classify with `cog codex-runner finalize --max-wall <secs>`. The exit code is the signal (0 ok · 1 failed · 75 still running); re-run finalize while it exits 75, and duration is never judged. Keep orchestration work foreground; never background it.
- Native effort only, via `--effort`.
- No legacy profile-based invocation anywhere.
- Do not instruct a runtime read of maintenance-reference conventions.
- Deterministic mechanics stay behind `cog executor`, `cog codex-runner`, and
  `/review-plan-lean`.
- This skill executes one prompt or plan. It does not author `/executor-lean`, wire
  queue prompts, or implement runner integration.
