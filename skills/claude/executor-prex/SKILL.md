---
name: executor-prex
description: >
  Automated staged workflow: Codex plans, Claude reviews the plan, Codex implements,
  Claude reviews the implementation, and an optional review loop can validate the result.
  Use this when the user wants a dual-agent plan-review-execute flow, asks to have
  Codex plan and implement while Claude validates, or refers to a staged adversarial
  workflow between Claude Code and Codex. Accepts CLI-style flags: `-a`/`--auto`
  for auto-approve and `-ar`/`--auto-review` for auto-approve + review-loop.
argument-hint: "[-a|-ar] <task description>"
disable-model-invocation: true
allowed-tools: Bash Read Write Edit Agent Skill
---

<!-- trigger-tests: "executor-prex", "plan-review-execute", "have Codex plan and implement while Claude validates", "staged adversarial workflow" -->
<!-- cog-skill: plan-emitter -->
<!-- cog-plan-mode-gate -->

# Plan Review Execute

## Phase 0: Plan Mode Gate

If Claude Code plan mode is active, STOP before parsing args, researching, delegating, or writing.
Tell the user to exit plan mode with `Shift+Tab` and re-invoke `/executor-prex`.

Run a staged dual-agent workflow inside Claude Code:

1. Codex creates the implementation plan.
2. Claude reviews and corrects the plan.
3. Codex implements the reviewed plan.
4. Claude reviews the implementation and fixes minor issues.
5. An optional review loop validates the result via iterative Codex review and Claude fixes.

Stage 2 plan review and stage 5 review-loop handoff are delegated via the **Agent tool**
(`subagent_type: general-purpose`), not the Skill tool — see
`$(cog skill-refs path skills-and-orchestration.md)` (Dispatch vs Delegation). The
parent workflow owns sequencing, proof checks, lock handling, and failure handling. These Agent-tool
delegations work even when `/executor-prex` itself runs as a subagent: Claude Code supports nested
subagents (≥ v2.1.172), so a delegated `/executor-prex` (e.g. under `claude-delegate`) spawns its
stage 2/4/5 reviewers as foreground nested subagents.

This skill is a **thin orchestrator**: every deterministic mechanic (run-dir + lock setup, flag
parsing, codex-session preflight gating, delegation-proof validation) is a versioned
`cog` subcommand that emits parseable result lines; this body owns only the sequencing and
the judgment. See
`$(cog skill-refs path skill-authoring/skill-script-extraction.md)`
for the extraction rule and the output/status contract.

Codex invocation mechanics — durable-job launch, polling, finalize/cancel, and thread ID
extraction — are owned by the `cog codex-runner` surface (`run-exec`, `run-resume`,
`finalize`, `status`, `cancel`, `gate`, `orientation`, `explain-status`) used throughout this skill;
obtain Codex behavioral preambles from `cog codex-runner orientation <read-only|write>` and
interpret runner statuses with `cog codex-runner explain-status <status>`.

> **Execution discipline — env first; every Codex run is a durable job.** `/executor-prex` runs as an
> **in-session delegated subagent** (dispatched via the `claude-delegate` subagent by an orchestrator
> such as `runner-queue`) or standalone in an interactive session. The Claude-harness no-backgrounding
> guarantee comes from the `claude-session` env layer: `CLAUDE_CODE_DISABLE_BACKGROUND_TASKS=1`,
> asserted by the `cog preflight claude-env` check below. Every Codex stage is a **cog-owned durable
> job**: `cog codex-runner run-exec`/`run-resume` launch it with `--state` and return immediately,
> and `cog codex-runner finalize --max-wall <secs>` polls-and-classifies in one verb: it waits up to
> `<secs>`, then reports via its exit code — **0 = done & ok, 1 = done & failed, 75 = still running**.
> Re-run `finalize` while it exits 75; **duration is never judged**, and a long run is never a reason
> to split the round. The orchestrator's own tool calls stay in the foreground; cog owns the long
> process, and `finalize` reconstructs the result from durable state, so an interrupted poll loses
> nothing. Details are recorded in
> `$(cog skill-refs path orchestration/in-session-vs-headless-delegation.md)`.

Orchestration patterns shared with `review-loop` (proof-of- delegation, lock management, review-loop
handoff, verdict model) are documented in
`$(cog skill-refs path orchestration/<file>.md)` (e.g. `orchestration-patterns.md`,
`verdict-model.md`).
This skill is the reference implementation; the shared docs describe the contracts.

## Inputs

The workflow needs:

1. A task description. Sources, in order of precedence: `$ARGUMENTS`; otherwise the current
   conversation context.
2. A repository context summary sufficient for Codex to plan and implement.
3. `codex-session` installed and on `PATH`. `cog codex-runner` owns durable launch, resume,
   finalize/cancel/status, orientation, status explanation, account-aware wrapper setup, and effort
   selection (`high` for stage 1 planning via `/plan-one-lean`, `medium` for stage 3 implementation;
   escalate stage 3 to `high` only when the user asks for it).

If the task description is missing or materially ambiguous after reviewing the current conversation,
ask one focused clarifying question before starting stage 1.

## Bootstrap: Run Directory and Lock

This is the **first** operational step. `cog` must be on `PATH` (ensure `cog` is installed and on `PATH`). Verify it is present and current, then create the run directory and acquire the
workflow lock in one call:

```bash
command -v cog >/dev/null || {
  echo "executor-prex: missing CLI binary — ensure the cog CLI is installed and on PATH." >&2
  exit 1
}
cog require hook-guard codex-runner rundir lock preflight executor-prex-parse-args || {
  echo "executor-prex: stale installation of cog (missing required subcommands) — ensure the cog CLI is installed and on PATH." >&2
  exit 1
}
cog rundir executor-prex --lock --owner-pid "$PPID"
```

This prints two result lines:

```text
RUN_DIR=<path>
LOCK_FILE=<path>
```

Shell state does not persist between Bash tool invocations. Read `RUN_DIR` and `LOCK_FILE` from this
output and **substitute the literal paths** in every subsequent command. All `cog` calls
below use the bare command (it is on `PATH`); no library sourcing or path resolution is needed.

Immediately after creating the run directory, assert the session env guarantee before Stage 1.
Substitute the literal `RUN_DIR` and `LOCK_FILE` values from the `cog rundir` output:

```bash
cog preflight claude-env "$RUN_DIR/preflight-claude-env.json" \
  || { cog lock release "$LOCK_FILE"; exit 1; }
```

`cog preflight claude-env` fails closed when the env guarantee is absent: a correctly bootstrapped
`claude-session` keeps `CLAUDE_CODE_DISABLE_BACKGROUND_TASKS=1` in force and the check passes;
otherwise the `||` branch releases the lock and stops.

The lock file stores two lines — the `RUN_DIR` path and the owning Claude Code PID (`$PPID`). The
Stop hook uses the PID to scope enforcement: only the session that created the lock is blocked while
artifacts are incomplete; other sessions are never blocked. The hook auto-cleans orphaned locks
(dead owner PID or missing RUN_DIR), so manual cleanup is rarely needed. If a crash leaves a stale
lock, release the specific path shown in `LOCK_FILE`:

```bash
cog lock release "$LOCK_FILE"
```

Mid-workflow, the lock is released before pausing for user approval and reacquired afterward with
`cog lock release "$LOCK_FILE"` and
`cog lock acquire "$RUN_DIR" --owner-pid "$PPID"` (the latter reprints `LOCK_FILE=`). These
do not recreate the run directory.

Write the final task description to `$RUN_DIR/request.md`. Unless the user asks otherwise, keep all
stage outputs under `RUN_DIR` using these names:

- `stage1-plan.md` (plan artifact, written by `/plan-one-lean`)
- `stage1-codex-output.md` (Codex final message)
- `stage1-events.jsonl`
- `stage1.longrun.json` (durable job state)
- `stage2-reviewed-plan.md`
- `stage3-impl-report.txt`
- `stage3-events.jsonl`
- `stage3.longrun.json` (durable job state)
- `stage4-context.md`
- `stage4-findings.json`
- `stage4-proof.diff`
- `stage4-review.md`
- `review_loop_input.json` (produced only if stage 5 runs)
- `preflight.json` (codex gate output)

## Workflow Mode

Mode is selected via CLI-style flags on `$ARGUMENTS`. Supported modes:

| Mode                       | Flag                   | Stage 2 approval                                                 | Stage 5 trigger                                                         |
| -------------------------- | ---------------------- | ---------------------------------------------------------------- | ----------------------------------------------------------------------- |
| `manual` (default)         | (none)                 | Wait for explicit user approval                                  | User decides / auto-trigger heuristic                                   |
| `auto-approve`             | `-a`, `--auto`         | Display the complete reviewed plan, then proceed without waiting | User decides / auto-trigger heuristic                                   |
| `auto-approve-review-loop` | `-ar`, `--auto-review` | Display the complete reviewed plan, then proceed without waiting | Always run after stage 4 once all `NEEDS_DISCUSSION` items are resolved |

Parse the flags with one deterministic call, **after `RUN_DIR` is created** (Bootstrap above) and
**before any other workflow step**. Substitute the literal `$RUN_DIR` path and pass the raw
arguments as a single quoted argument:

```bash
cog executor-prex-parse-args "$RUN_DIR" "$ARGUMENTS"
```

This writes the resolved mode to `$RUN_DIR/mode` and the stripped task description to
`$RUN_DIR/task.txt`. It prints `MODE=` for immediate use, and **exits 2
on an unrecognized flag** (fail closed). The task text is word-split without glob expansion, so a
description containing `*` or `[...]` is preserved verbatim.

All downstream references to "the mode" mean the value in `$RUN_DIR/mode`. Read it whenever a later
stage needs it:

```bash
MODE="$(cat "$RUN_DIR/mode")"
```

Invocation examples:

- `/executor-prex refactor the foo module` — manual mode
- `/executor-prex -a refactor the foo module` — auto-approve
- `/executor-prex -ar refactor the foo module` — auto-approve + review-loop

## Pre-flight: Check Codex

Gate on Codex readiness before any `codex-session` call — a single deterministic call, no subagent.
`codex-session` must be available and healthy; if it is not, fail immediately (**fail closed**),
release the lock, and notify the caller. Do not retry automatically.

```bash
cog codex-runner gate codex "$RUN_DIR/preflight.json" || {
  cog lock release "$LOCK_FILE"
  exit 1
}
```

`gate` runs the codex preflight, writes the fragment to `preflight.json` (printing
`RESOLVED <path>`), then exits non-zero with a legible message on stderr unless
`codex_session.available` is `true` and `health` is `ok`. On non-zero exit, release the lock and
stop — do not continue to stage 1.

## Stage 1: Plan

Delegate planning to Codex's own `/plan-one-lean` skill. The parent orchestrator does **not** invoke
`/plan-one-lean` as a Claude skill or Agent delegation; it writes a thin Codex prompt to
`$RUN_DIR/stage1-prompt.md` and passes that prompt through `cog codex-runner run-exec`.

The Stage 1 prompt must tell Codex to run `/plan-one-lean`, save the lean plan to
`$RUN_DIR/stage1-plan.md`, and produce a numbered, reviewable implementation plan with assumptions,
ambiguities, dependencies, and risks. Include the original task and relevant repo constraints. The
only permitted write during this planning stage is the plan artifact under `RUN_DIR`.

Keep the prompt-file rule: write the complete Stage 1 prompt to `RUN_DIR` first, then pass it via
`--prompt`; never inline multi-line prompts directly in the Bash command.

```bash
cog codex-runner run-exec \
  --mode danger \
  --access write \
  --effort high \
  --prompt "$RUN_DIR/stage1-prompt.md" \
  --output "$RUN_DIR/stage1-codex-output.md" \
  --events "$RUN_DIR/stage1-events.jsonl" \
  --stderr "$RUN_DIR/stage1-stderr.log" \
  --thread last \
  --state "$RUN_DIR/stage1.longrun.json"
```

`--output` captures Codex's final message in `stage1-codex-output.md`; the plan artifact itself is
`stage1-plan.md`, written by `/plan-one-lean` through `cog plan-doc`. They are separate files, so the
runner output never overwrites the plan.

`run-exec` launches the Codex run as a cog-owned durable job and returns immediately. Poll-and-classify
it in one verb with `cog codex-runner finalize --max-wall <secs>`: the exit code is the signal
(0 = ok · 1 = failed · 75 = still running). Re-run finalize while it exits 75; duration is never judged:

```bash
# Re-run while this exits 75 (still running); exit code is the signal:
# 0 = done & ok, 1 = done & failed, 75 = still running. Duration is never judged.
cog codex-runner finalize --state "$RUN_DIR/stage1.longrun.json" --max-wall 300 \
  > "$RUN_DIR/stage1-runner.json"
```

Extract the planning thread ID and the planning account:

```bash
PLAN_THREAD_ID="$(jq -r '.thread_id' "$RUN_DIR/stage1-runner.json")"
printf '%s\n' "$PLAN_THREAD_ID" > "$RUN_DIR/plan-thread-id"

PLAN_ACCOUNT="$(jq -r '.account' "$RUN_DIR/stage1-runner.json")"
printf '%s\n' "$PLAN_ACCOUNT" > "$RUN_DIR/plan-account"
```

Use `tail -1`, not `head -1`: when the wrapper rotates accounts mid-run (429 failover), the events
stream carries one `thread.started` per attempt and only the **last** thread is the one that
completed the planning turn.

The `PLAN_THREAD_ID` and `PLAN_ACCOUNT` pair is reused in stage 3 to resume this session for
implementation pinned to its owning account. If stage 3 runs in a later Bash invocation, re-read
both from `$RUN_DIR/plan-thread-id` and `$RUN_DIR/plan-account` (or re-extract from
`stage1-events.jsonl`) before calling `cog codex-runner run-resume`.

Read `stage1-plan.md`, summarize the result briefly for the user, and move directly to stage 2.

## Stage 2: Review Plan

Delegate plan review via the **Agent tool** to `/review-plan-lean`, using its three-absolute-path
orchestrator contract:

1. plan path: `$RUN_DIR/stage1-plan.md`
2. request path: `$RUN_DIR/request.md`
3. output path: `$RUN_DIR/stage2-reviewed-plan.md`

`request.md` is the Bootstrap task file and is created before Stage 1. The parent
workflow owns the snapshot-pre/post proof check, `verify-proof`, lock release/reacquire, and
approval loop. Follow `references/stage-2-review-plan.md` for the Stage 2 command shapes and
failure handling.

## Stage 3: Implement

Resume the Stage 1 Codex planning thread/account and implement the reviewed plan with Codex. The
reviewed plan supersedes Codex's original draft. Stage 3 uses native Codex effort
(`cog codex-runner run-resume --effort medium`, no `--profile`) pinned with
`--account "$PLAN_ACCOUNT"` and `--thread-id "$PLAN_THREAD_ID"`; branch only on the runner-emitted
`status`/`resume_signal`. Follow `references/stage-3-implement.md` for exact command shapes, the
resume decision table, the Resume Fallback, and the prompt-file rule plus the durable-job poll
protocol.

## Stage 4: Review Implementation

Delegate implementation review to `review-lean` via the **Agent tool**, validate proof, triage
review and plan-conformance findings, and write `stage4-review.md`. Follow
`references/stage-4-review-implementation.md` for command shapes, proof validation, and triage
details.

## Stage 5: Optional Review Loop

Run the optional `review-loop` handoff only after all Stage 4 `NEEDS_DISCUSSION` items are resolved
and the mode or task complexity calls for it. The handoff input is assembled and validated by
`cog review-loop-input`, and the child run-dir is located via `cog rundir snapshot-children` +
`cog rundir locate-child`; follow `references/stage-5-review-loop.md` for the handoff build, child
run-dir proof, and summary handling.

## Final Output

If stage 5 was not run, remove the workflow lock before presenting the summary:

```bash
cog lock release "$LOCK_FILE"
```

(If stage 5 ran, the lock was already released before the `review-loop` handoff.)

End with a concise summary covering:

- Whether each stage completed (including whether stage 5 review loop ran).
- Files changed in the repo.
- How many findings were fixed, acknowledged, dismissed, or still need discussion.
- If stage 5 ran: include the review-loop's round count and outcome.
- Any remaining risks or follow-up items.

## Guardrails

- Do not skip stage 2 approval unless the mode is `auto-approve` or `auto-approve-review-loop`.
- Stage 3 must first attempt to resume the planning session with
  `--dangerously-bypass-approvals-and-sandbox` for write access; if the resume call fails for the
  documented reasons, run the fresh-`exec` Resume Fallback with fully inlined context.
- Do not invent unsupported Codex flags.
- Always use `codex-session exec`, never bare `codex exec`. The wrapper provides
  per-account isolation, config-recipe composition, and account-aware failover. Pass
  `--effort high` at the stage 1 `/plan-one-lean` planning call site and `--effort medium` at the
  stage 3 implementation call sites; escalate to `--effort high` only when the user explicitly asks
  to push a stage harder (stuck/looping runs, novel design, security-critical changes). Do not pass
  `-m`/`-c model_reasoning_effort`.
- Do not duplicate the full Codex CLI conventions here; keep those centralized in the reference
  file.
- Codex may run read-only git inspection commands needed to review the diff (`git diff`,
  `git diff --staged`, `git diff --name-only`, `git log`), but must never mutate git state
  (commit, add/stage, push, reset, checkout, stash, etc.). Only the Claude Code orchestrator
  performs git mutations.
- Keep deterministic mechanics in versioned `cog` subcommands (this skill is a thin
  orchestrator); keep only sequencing and judgment as prose. Do not reintroduce inline multi-line
  shell for setup, parsing, gating, or proof validation.

## Error Handling

After each Codex call, validate the output file is non-empty:

```bash
[ -s "$RUN_DIR/stage1-plan.md" ] || echo "ERROR: stage1-plan.md is empty"
```

If stage 3's `finalize` reports a failed status (non-zero exit, empty output file, bwrap error, or a
resume-mechanics signal), follow the documented **Resume Fallback** before reporting final failure.

If any other Codex call fails, or if the stage 3 fresh-`exec` fallback also fails:

1. Report the error to the user, including any stderr output.
2. Remove the workflow lock: `cog lock release "$LOCK_FILE"`
3. Do not retry automatically after the documented stage 3 fallback is exhausted.
4. Ask the user whether to retry the failed stage, skip it, or abort the workflow.
5. If the user approves a retry, reacquire the lock before re-running the stage:
   `cog lock acquire "$RUN_DIR" --owner-pid "$PPID"`

<!-- Migrated from stock-codex to codex-session wrapper on 2026-05-23 (R5). -->
<!-- Wave-2 thin-orchestrator rewrite on 2026-06-16 (R3): inline setup/parse/gate/proof shell -->
<!-- moved to cog rundir/lock/executor-prex-parse-args/codex-runner gate+verify-proof. -->
