---
name: executor-prex
description: >
  Automated staged workflow: plan-vetted produces a vetted plan, Codex implements it,
  Claude reviews the implementation, and an optional review loop can validate the result.
  Use this when the user wants a dual-agent plan-review-execute flow, asks to have a vetted
  plan implemented by Codex while Claude validates, or refers to a staged adversarial
  workflow between Claude Code and Codex. Accepts CLI-style flags: `-a`/`--auto`
  for auto-approve and `-ar`/`--auto-review` for auto-approve + review-loop.
argument-hint: "[-a|-ar] <task description>"
disable-model-invocation: true
allowed-tools: Bash Read Write Edit Agent Skill
---

<!-- trigger-tests: "executor-prex", "plan-review-execute", "have Codex plan and implement while Claude validates", "staged adversarial workflow" -->
<!-- cog-skill: plan-emitter -->
<!-- cog-skill: input-fidelity -->

# Plan Review Execute

<!-- cog-plan-mode-gate -->

**Phase 0 — Plan-mode gate.** If Claude Code **plan mode** is active (a system-reminder says plan
mode is on / that you must not make edits), **STOP** before any other work — parsing args,
researching, interviewing, delegating, or writing. Tell the user in one line to exit plan mode
(`Shift+Tab`) and re-invoke `/executor-prex`. Do not call `ExitPlanMode`, and do not silently continue.

<!-- cog-context-brief-gate -->

**Context-brief gate.** Before `/executor-prex` dispatches to any fresh-context worker — an Agent subagent
or a `cog codex-runner` Codex job — build its input as a validated context brief from your whole
accumulated raw context: attach the raw request as-is, author an oriented objective, carry the full
substance and load-bearing artifacts, and omit your own verdict. Build the brief with `cog
context-brief build` and confirm it with `cog context-brief validate` before dispatch.

Run a staged dual-agent workflow inside Claude Code:

1. `plan-vetted` produces a vetted implementation plan (evaluate the input, then generate or
   multi-review it through dual-engine planning).
2. Codex implements the vetted plan.
3. Claude reviews the implementation and fixes minor issues.
4. An optional review loop validates the result via iterative Codex review and Claude fixes.

Stage 3 implementation review and stage 4 review-loop handoff are delegated via the **Agent tool**
(`subagent_type: general-purpose`), not the Skill tool — see
`$(cog skill-refs path skills-and-orchestration.md)` (Dispatch vs Delegation). The
parent workflow owns sequencing, proof checks, lock handling, and failure handling. These Agent-tool
delegations work even when `/executor-prex` itself runs as a subagent: Claude Code supports nested
subagents (≥ v2.1.172), so a delegated `/executor-prex` (e.g. under `claude-delegate`) spawns its
stage 3/4 reviewers as foreground nested subagents.

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
> **in-session delegated subagent** (dispatched via the `claude-delegate` subagent by a runner) or
> standalone in an interactive session. The Claude-harness no-backgrounding
> guarantee comes from the `claude-session` env layer: `CLAUDE_CODE_DISABLE_BACKGROUND_TASKS=1`,
> asserted by the `cog preflight claude-env` check below. Every Codex stage is a **cog-owned durable
> job**: `cog codex-runner run-exec` launches it with `--state` and returns immediately,
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
3. `codex-session` installed and on `PATH`. `cog codex-runner` owns durable launch,
   finalize/cancel/status, orientation, status explanation, account-aware wrapper setup, and effort
   selection (`medium` for stage 2 implementation; escalate to `high` only when the user asks for
   it). Stage 1 planning runs inside `plan-vetted`, which owns its own dual-engine effort.

If the task description is missing or materially ambiguous after reviewing the current conversation,
ask one focused clarifying question before starting the vetted plan.

## Bootstrap: Run Directory and Lock

This is the **first** operational step. `cog` must be on `PATH` (ensure `cog` is installed and on `PATH`). Verify it is present and current, then create the run directory and acquire the
workflow lock in one call:

```bash
command -v cog >/dev/null || {
  echo "executor-prex: missing CLI binary — ensure the cog CLI is installed and on PATH." >&2
  exit 1
}
cog require hook-guard codex-runner rundir lock preflight executor-prex-parse-args executor assess-input || {
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

- `vetted-plan.md` (the vetted plan, written by `plan-vetted` via `--output`)
- `impl-report.txt`
- `impl-events.jsonl`
- `impl.longrun.json` (durable job state)
- `review-context.md`
- `review-findings.json`
- `review-proof.diff`
- `review.md`
- `review_loop_input.json` (produced only if stage 4 runs)
- `preflight.json` (codex gate output)
- `context-brief.md` (the validated context brief; built once, reused across stages)

## Workflow Mode

Mode is selected via CLI-style flags on `$ARGUMENTS`. Supported modes:

| Mode                       | Flag                   | Vetted-plan approval (stage 1)                                | Stage 4 trigger                                                        |
| -------------------------- | ---------------------- | ------------------------------------------------------------ | --------------------------------------------------------------------- |
| `manual` (default)         | (none)                 | Wait for explicit user approval                              | User decides / auto-trigger heuristic                                 |
| `auto-approve`             | `-a`, `--auto`         | Display the complete vetted plan, then proceed without waiting | User decides / auto-trigger heuristic                                |
| `auto-approve-review-loop` | `-ar`, `--auto-review` | Display the complete vetted plan, then proceed without waiting | Always run after stage 3 once all `NEEDS_DISCUSSION` items are resolved |

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

## Context Brief

Build the run's context brief once, then reuse it across stages (it is also passed through to the
Stage 4 review-loop handoff). Build it per
`$(cog skill-refs path orchestration/context-brief-contract.md)` from `$RUN_DIR/request.md`: scaffold
the authored body, fill it from the whole session (a well-oriented **Objective**; **Output Format**;
**Boundaries**; **Context & Decisions** carrying the full substance; **Artifacts** inline or
pointed-to; **Effort Guidance**; **Not Evaluated** — keep your own verdict out), then build it:

```bash
cog context-brief template --out "$RUN_DIR/brief-body.md"
# fill $RUN_DIR/brief-body.md per the contract, then:
cog context-brief build --request "$RUN_DIR/request.md" --body "$RUN_DIR/brief-body.md" --out "$RUN_DIR/context-brief.md"
```

`build` attaches the request verbatim and fails closed unless every section is filled.

## Stage 1: Vetted Plan

Produce the vetted implementation plan with `plan-vetted`, which fills the old plan and plan-review
stages in one step: it evaluates the input, then generates a plan (`needs-plan`) or multi-reviews it
(`good-input`) through dual-engine planning. Inline-chain it in the current context (read
`$HOME/.claude/skills/plan-vetted/SKILL.md` and follow it), passing the task plus `--output
"$RUN_DIR/vetted-plan.md"`. The delegation input is the validated context brief
`$RUN_DIR/context-brief.md` built above.

`plan-vetted` writes the vetted plan to `$RUN_DIR/vetted-plan.md` and returns the output path
and the route. Verify the artifact before continuing:

```bash
[ -s "$RUN_DIR/vetted-plan.md" ] || { echo "ERROR: vetted-plan.md is empty" >&2; cog lock release "$LOCK_FILE"; exit 1; }
```

The parent workflow owns lock release/reacquire and the approval loop. Follow
`references/vetted-plan.md` for the inline-chain delegation shape and the approval loop.

## Stage 2: Implement

Implement the vetted plan with Codex as a fresh durable `exec`, inlining the full plan and request so
the run is self-contained (the vetted plan carries all planning context; there is no Codex planning
thread to resume). Stage 2 uses native Codex effort (`cog codex-runner run-exec --effort medium`, no
`--profile`). Follow `references/implement.md` for the exact command shapes, the inlined-prompt
contract, and the prompt-file rule plus the durable-job poll protocol.

## Stage 3: Review Implementation

Delegate implementation review to `review-oneshot` via the **Agent tool**, validate proof, triage
review and plan-conformance findings, and write `review.md`. Follow
`references/review-implementation.md` for command shapes, proof validation, and triage
details.

## Stage 4: Optional Review Loop

Run the optional `review-loop` handoff only after all Stage 3 `NEEDS_DISCUSSION` items are resolved
and the mode or task complexity calls for it. The handoff input is assembled and validated by
`cog review-loop-input`, and the child run-dir is located via `cog rundir snapshot-children` +
`cog rundir locate-child`; follow `references/review-loop.md` for the handoff build, child
run-dir proof, and summary handling.

## Final Output

If stage 4 was not run, remove the workflow lock before presenting the summary:

```bash
cog lock release "$LOCK_FILE"
```

(If stage 4 ran, the lock was already released before the `review-loop` handoff.)

End with a concise summary covering:

- Whether each stage completed (including whether stage 4 review loop ran).
- Files changed in the repo.
- How many findings were fixed, acknowledged, dismissed, or still need discussion.
- If stage 4 ran: include the review-loop's round count and outcome.
- Any remaining risks or follow-up items.

## Match-outcome telemetry

When the input was a queued plan-vault round (the `-ar <path>` resolves under a plan vault), record a
match-outcome so routing can be calibrated ([ADR-0058](../../docs/decisions/0058-match-outcome-telemetry-and-calibration-loop.md)).
Resolve the join key from the round path — it stays producer-blind. The `executor-prex`
marginal-value checkpoint is the **relevant review-loop findings count**: the real findings the review
loop surfaced across its rounds (from the `REVIEW_LOOP_OK … rounds=<n>` line and `round-*-findings.json`).
Zero relevant findings means the loop earned nothing — over-powered by one rung:

```bash
cog match-telemetry round-key --round-path <input-round-path> --json   # -> project_key, plan_slug, round_id
cog match-telemetry record --kind outcome \
  --project-key <project_key> --plan-slug <plan_slug> --round-id <round_id> \
  --actual-executor executor-prex --result <pass|fail> [--reverted] [--retries <n>] \
  [--loc-changed <n>] [--files <n>] --review-loop-findings <n> [--note <text>] --json
```

Skip telemetry for non-round inputs. Attach `--note` only when the objective signals look conflicting
or questionable — never as a routine per-run rating.

## Guardrails

- Do not skip the stage 1 vetted-plan approval unless the mode is `auto-approve` or
  `auto-approve-review-loop`.
- Stage 2 implements via a fresh durable `exec` with the vetted plan and request inlined; there is no
  planning thread to resume.
- Do not invent unsupported Codex flags.
- Always use `codex-session exec`, never bare `codex exec`. The wrapper provides
  per-account isolation, config-recipe composition, and account-aware failover. Pass
  `--effort medium` at the stage 2 implementation call site; escalate to `--effort high` only when the
  user explicitly asks to push it harder (stuck/looping runs, novel design, security-critical
  changes). Do not pass `-m`/`-c model_reasoning_effort`.
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

After the vetted-plan stage, validate the plan artifact is non-empty:

```bash
[ -s "$RUN_DIR/vetted-plan.md" ] || echo "ERROR: vetted-plan.md is empty"
```

After the stage 2 Codex call, validate the implementation report is non-empty:

```bash
[ -s "$RUN_DIR/impl-report.txt" ] || echo "ERROR: impl-report.txt is empty"
```

If any stage fails:

1. Report the error to the user, including any stderr output.
2. Remove the workflow lock: `cog lock release "$LOCK_FILE"`
3. Do not retry automatically.
4. Ask the user whether to retry the failed stage, skip it, or abort the workflow.
5. If the user approves a retry, reacquire the lock before re-running the stage:
   `cog lock acquire "$RUN_DIR" --owner-pid "$PPID"`

<!-- Migrated from stock-codex to codex-session wrapper on 2026-05-23 (R5). -->
<!-- Wave-2 thin-orchestrator rewrite on 2026-06-16 (R3): inline setup/parse/gate/proof shell -->
<!-- moved to cog rundir/lock/executor-prex-parse-args/codex-runner gate+verify-proof. -->
