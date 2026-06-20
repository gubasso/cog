---
name: executor-prex
description: >
  Automated staged workflow: Codex plans, Claude reviews the plan, Codex implements,
  Claude reviews the implementation, and an optional review loop can validate the result.
  Use this when the user wants a dual-agent plan-review-execute flow, asks to have
  Codex plan and implement while Claude validates, or refers to a staged adversarial
  workflow between Claude Code and Codex. Accepts CLI-style flags: `-a`/`--auto`
  for auto-approve, `-ar`/`--auto-review` for auto-approve + review-loop, and
  `-t`/`--tsk-impl [id]` to source the task from a tsk issue (`tsk show <id>`,
  resolving the id from the active branch via `tsk id` if omitted).
argument-hint: "[-a|-ar] [-t [id]] <task description>"
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
parsing, codex-session preflight gating, tsk resolution, delegation-proof validation) is a versioned
`cog` subcommand that emits parseable result lines; this body owns only the sequencing and
the judgment. See
`$(cog skill-refs path skill-authoring/skill-script-extraction.md)`
for the extraction rule and the output/status contract.

Codex invocation mechanics — CLI invocation patterns, thread ID extraction, and timeout
requirements — are owned by the `cog codex-runner` surface (`run-exec`, `run-resume`, `gate`,
`orientation`, `explain-status`) used throughout this skill; the maintenance reference is
`docs/reference/codex-conventions.md`. Obtain Codex behavioral preambles from
`cog codex-runner orientation <read-only|write>` and interpret runner statuses with
`cog codex-runner explain-status <status>`.

> **Execution discipline — env first, never background a Codex call.** `/executor-prex` runs as an
> **in-session delegated subagent** (dispatched via the `claude-delegate` subagent by an orchestrator
> such as `runner-queue`) or standalone in an interactive session — not, as before, "always
> headless `claude -p`". The no-backgrounding guarantee comes from the `claude-session` env layer:
> `CLAUDE_CODE_DISABLE_BACKGROUND_TASKS=1` disables Claude Code auto-backgrounding for the session.
> The `cog preflight claude-env` assertion below verifies that guarantee at bootstrap. Foreground
> discipline remains the in-session contract: every Codex Bash call (and every other tool call in
> this workflow) **MUST run in the foreground** with `run_in_background` false/omitted and a Bash-tool
> `timeout` of `600000ms`; the call blocks until Codex exits. A round whose Codex stage cannot finish
> within the 600s window is a **planning error** — split the round per `plan-lifecycle.md` — **never**
> a reason to background. A genuine overrun surfaces deterministically as a `timeout-124`/`sigterm`
> status with partial logs; handle it via the Resume Fallback, not by detaching. Details are recorded
> in
> `$(cog skill-refs path orchestration/in-session-vs-headless-delegation.md)`.

Orchestration patterns shared with `review-loop` (proof-of- delegation, lock management, review-loop
handoff, verdict model) are documented in
`$(cog skill-refs path orchestration/<file>.md)` (e.g. `orchestration-patterns.md`,
`verdict-model.md`).
This skill is the reference implementation; the shared docs describe the contracts.

## Inputs

The workflow needs:

1. A task description. Sources, in order of precedence: the resolved body of the `-t`/`--tsk-impl`
   issue when that flag is set; otherwise `$ARGUMENTS`; otherwise the current conversation context.
2. A repository context summary sufficient for Codex to plan and implement.
3. `codex-session` installed and on `PATH`. The wrapper composes config-recipes, resolves accounts,
   and sets `CODEX_HOME` per-account per-group before passing through to `codex`. Model selection and
   reasoning effort come from `cog codex-runner --effort` (`high` for stage 1 planning via
   `/plan-codex`, `medium` for stage 3 implementation; `deep` is the human-judged escalation tier,
   used only when the user asks for it). See the "Wrapper:
   `codex-session`" section in the maintenance reference `docs/reference/codex-conventions.md`
   for the full API reference.

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
cog require hook-guard codex-runner rundir lock preflight executor-prex-parse-args executor-prex-tsk-resolve || {
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
cog preflight claude-env "$RUN_DIR/preflight-claude-env.json" --allow-legacy-session \
  || { cog lock release "$LOCK_FILE"; exit 1; }
```

The `--allow-legacy-session` flag exists only for this env rollout. In the already-running session
that predates the `base.json` env change, an absent guarantee is advisory: `cog` writes
`preflight-claude-env.json`, warns, and returns 0 so the current plan can finish. In a restarted
session the strict check should pass because `CLAUDE_CODE_DISABLE_BACKGROUND_TASKS=1` is in force.
Without that migration flag, `cog preflight claude-env` fails closed when the env guarantee is absent.

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

- `stage1-plan.md`
- `stage1-events.jsonl`
- `stage2-reviewed-plan.md`
- `stage3-impl-report.txt`
- `stage3-events.jsonl`
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

`-t`/`--tsk-impl [id]` is an orthogonal input-source flag and may be combined with any mode above.
See **Tsk-Impl Source** below.

Parse the flags with one deterministic call, **after `RUN_DIR` is created** (Bootstrap above) and
**before any other workflow step**. Substitute the literal `$RUN_DIR` path and pass the raw
arguments as a single quoted argument:

```bash
cog executor-prex-parse-args "$RUN_DIR" "$ARGUMENTS"
```

This writes the resolved mode to `$RUN_DIR/mode`, the tsk-impl state to `$RUN_DIR/tsk-impl` (`0:`
when disabled, `1:<id-or-empty>` when enabled), and the stripped task description to
`$RUN_DIR/task.txt`. It prints `MODE=`, `TSK_IMPL=`, and `TSK_ID=` for immediate use, and **exits 2
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
- `/executor-prex -t` — resolve tsk id from active branch, use `tsk show` as the task
- `/executor-prex -t 20240415-120030-my-issue` — use an explicit tsk id as the task
- `/executor-prex -a -t 20240415-120030-my-issue` — auto-approve + tsk-sourced task
- `/executor-prex -ar --tsk-impl` — auto-approve + review-loop + tsk-sourced task (id via `tsk id`)

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

## Tsk-Impl Source

When the parser reported `TSK_IMPL=1` (i.e., the user passed `-t`/`--tsk-impl`), resolve the task
description from a tsk issue **before** Stage 1 planning begins. This overrides `$RUN_DIR/task.txt`
and `$RUN_DIR/request.md` with the tsk-issue body. When `TSK_IMPL=0`, skip this entire section.

Before running any `tsk` command, read
[`$DOCS_NOTES_REPO/tech/tools/riptask/commands.md`](file:///$DOCS_NOTES_REPO/tech/tools/riptask/commands.md)
for CLI conventions. If `$DOCS_NOTES_REPO` is unset or the file is unavailable, fall back to
`tsk <command> --help`.

Steps:

1. Resolve the id and fetch the issue body with one call:

   ```bash
   cog executor-prex-tsk-resolve --run-dir "$RUN_DIR" || {
     cog lock release "$LOCK_FILE"
     exit 1
   }
   ```

   This resolves the id (from the `$RUN_DIR/tsk-impl` state, else `tsk id` on the active branch),
   fetches the body into `$RUN_DIR/tsk-issue.md`, rewrites `$RUN_DIR/tsk-impl` to `1:<id>`, and
   prints `TSK_ID=` and `TSK_BODY=`. On any failure (no id resolvable, `tsk show` error) it prints
   guidance to stderr and exits non-zero: release the lock and STOP. Do NOT fall back to
   `$ARGUMENTS` or conversation context.

2. Classify the body in `$RUN_DIR/tsk-issue.md` (this is a judgment call, not a mechanic):

   - **Well-specified** — concrete requirements, referenced files, and explicit steps or acceptance
     criteria. Copy it verbatim into the task slot:

     ```bash
     cp "$RUN_DIR/tsk-issue.md" "$RUN_DIR/task.txt"
     cp "$RUN_DIR/tsk-issue.md" "$RUN_DIR/request.md"
     ```

   - **Thin / vague / incomplete** — short, unreferenced, or lacking actionable steps. Pause the
     workflow before Stage 1 and ask the user:

     > The tsk issue body is thin. Do you want to complement the spec and build a more complete plan
     > before I kick off Codex? Reply `yes` (add context), `proceed anyway`, or `abort`.

     - `yes`: ask focused clarifying questions, merge the added context into a consolidated plan,
       and write the result to `$RUN_DIR/task.txt` and `$RUN_DIR/request.md`. Show the merged plan
       to the user verbatim and wait for an explicit second approval before continuing.
     - `proceed anyway`: copy the body as-is (same as the well-specified branch). Note the thin-spec
       risk in one line.
     - `abort`: release the lock (`cog lock release "$LOCK_FILE"`) and stop.

3. After this section, Stages 1-5 operate on `$RUN_DIR/task.txt` and `$RUN_DIR/request.md` exactly
   as they do in non-tsk-impl runs. No other stage needs tsk-specific logic.

## Stage 1: Plan

Delegate planning to Codex's own `/plan-codex` skill. The parent orchestrator does **not** invoke
`/plan-codex` as a Claude skill or Agent delegation; it writes a thin Codex prompt to
`$RUN_DIR/stage1-prompt.md` and passes that prompt through `cog codex-runner run-exec`.

The Stage 1 prompt must tell Codex to run `/plan-codex`, save the lean plan to
`$RUN_DIR/stage1-plan.md`, and produce a numbered, reviewable implementation plan with assumptions,
ambiguities, dependencies, and risks. Include the original task and relevant repo constraints. The
only permitted write during this planning stage is the plan artifact under `RUN_DIR`.

Keep the prompt-file rule: write the complete Stage 1 prompt to `RUN_DIR` first, then pass it via
`--prompt`; never inline multi-line prompts directly in the Bash command.

```bash
cog codex-runner run-exec \
  --mode danger \
  --effort high \
  --prompt "$RUN_DIR/stage1-prompt.md" \
  --output "$RUN_DIR/stage1-plan.md" \
  --events "$RUN_DIR/stage1-events.jsonl" \
  --stderr "$RUN_DIR/stage1-stderr.log" \
  --thread last \
  > "$RUN_DIR/stage1-runner.json"
```

When using Claude Code's Bash tool for this command, set the timeout to `600000ms`. Run it in the
**foreground** — `run_in_background` must be false/omitted. This call blocks until Codex exits; never
background it (see **Execution discipline** above).

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

Delegate plan review via the **Agent tool** to `/review-plan-claude`, using its three-absolute-path
orchestrator contract:

1. plan path: `$RUN_DIR/stage1-plan.md`
2. request path: `$RUN_DIR/request.md`
3. output path: `$RUN_DIR/stage2-reviewed-plan.md`

`request.md` is the Bootstrap/Tsk-resolved task file and is created before Stage 1. The parent
workflow owns the snapshot-pre/post proof check, `verify-proof`, lock release/reacquire, and
approval loop. Follow `references/stage-2-review-plan.md` for the Stage 2 command shapes and
failure handling.

## Stage 3: Implement

Resume the Stage 1 Codex planning thread/account and implement the reviewed plan with Codex. The
reviewed plan supersedes Codex's original draft. Stage 3 uses native Codex effort
(`cog codex-runner run-resume --effort medium`, no `--profile`) pinned with
`--account "$PLAN_ACCOUNT"` and `--thread-id "$PLAN_THREAD_ID"`; branch only on the runner-emitted
`status`/`resume_signal`. Follow `references/stage-3-implement.md` for exact command shapes, the
resume decision table, the Resume Fallback, and the prompt-file / `600000ms` / foreground discipline.

## Stage 4: Review Implementation

Delegate implementation review to `review-code-deep` via the **Agent tool**, validate proof, triage
findings, check plan conformance, and write `stage4-review.md`. Stage 4 behavior is unchanged in
this round; follow `references/stage-4-review-implementation.md` for command shapes and triage
details.

## Stage 5: Optional Review Loop

Run the optional `review-loop` handoff only after all Stage 4 `NEEDS_DISCUSSION` items are resolved
and the mode or task complexity calls for it. Stage 5 behavior is unchanged in this round; follow
`references/stage-5-review-loop.md` for handoff JSON, child run-dir proof, and summary handling.

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
  `--effort high` at the stage 1 `/plan-codex` planning call site and `--effort medium` at the
  stage 3 implementation call sites; substitute `--effort deep` only when the user explicitly asks
  to escalate a stage (stuck/looping runs, novel design, security-critical changes). Do not pass
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
- When `-t`/`--tsk-impl` is set, the tsk-issue body (plus any user-supplied complement) is the ONLY
  source of the task description. Do not silently merge `$ARGUMENTS` trailing text or conversation
  context into it.
- If `tsk id` cannot resolve an id, STOP the workflow and release the lock. Do not fall back to
  other sources.

## Error Handling

After each Codex call, validate the output file is non-empty:

```bash
[ -s "$RUN_DIR/stage1-plan.md" ] || echo "ERROR: stage1-plan.md is empty"
```

If the stage 3 resume call fails (non-zero exit, empty output file, bwrap error, or Bash tool
timeout), follow the documented **Resume Fallback** before reporting final failure.

If any other Codex call fails, or if the stage 3 fresh-`exec` fallback also fails:

1. Report the error to the user, including any stderr output.
2. Remove the workflow lock: `cog lock release "$LOCK_FILE"`
3. Do not retry automatically after the documented stage 3 fallback is exhausted.
4. Ask the user whether to retry the failed stage, skip it, or abort the workflow.
5. If the user approves a retry, reacquire the lock before re-running the stage:
   `cog lock acquire "$RUN_DIR" --owner-pid "$PPID"`

<!-- Migrated from stock-codex to codex-session wrapper on 2026-05-23 (R5). -->
<!-- Wave-2 thin-orchestrator rewrite on 2026-06-16 (R3): inline setup/parse/gate/proof shell -->
<!-- moved to cog rundir/lock/executor-prex-parse-args/executor-prex-tsk-resolve/codex-runner gate+verify-proof. -->
