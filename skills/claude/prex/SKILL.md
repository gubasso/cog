---
name: prex
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

# Plan Review Execute

Run a staged dual-agent workflow inside Claude Code:

1. Codex creates the implementation plan.
2. Claude reviews and corrects the plan.
3. Codex implements the reviewed plan.
4. Claude reviews the implementation and fixes minor issues.
5. An optional review loop validates the result via iterative Codex review and Claude fixes.

Stage 2 plan review and stage 5 review-loop handoff are delegated via the **Agent tool**
(`subagent_type: general-purpose`), not the Skill tool — see
`$DOCS_NOTES_REPO/tech/tools/claude-code/skills-and-orchestration.md` (Dispatch vs Delegation). The
parent workflow owns sequencing, proof checks, lock handling, and failure handling. These Agent-tool
delegations work even when `/prex` itself runs as a subagent: Claude Code supports nested subagents
(≥ v2.1.172), so a delegated `/prex` (e.g. under `claude-delegate`) spawns its stage 2/4/5 reviewers
as foreground nested subagents.

This skill is a **thin orchestrator**: every deterministic mechanic (run-dir + lock setup, flag
parsing, codex-session preflight gating, tsk resolution, delegation-proof validation) is a versioned
`cog` subcommand that emits parseable result lines; this body owns only the sequencing and
the judgment. See
[`$DOCS_NOTES_REPO/tech/tools/claude-code/skill-authoring/skill-script-extraction.md`](file:///$DOCS_NOTES_REPO/tech/tools/claude-code/skill-authoring/skill-script-extraction.md)
for the extraction rule and the output/status contract.

Read
[`$DOCS_NOTES_REPO/tech/tools/claude-code/codex-conventions.md`](file:///$DOCS_NOTES_REPO/tech/tools/claude-code/codex-conventions.md)
before running any Codex command. Treat that file as the source of truth for CLI invocation
patterns, thread ID extraction, and timeout requirements.

> **Execution discipline — never background a Codex call.** `/prex` runs as an **in-session
> delegated subagent** (dispatched via the `claude-delegate` subagent by an orchestrator such as
> `plan-queue-runner`) or standalone in an interactive session — not, as before, "always headless
> `claude -p`". Backgrounding is unsafe in either case. Every Codex Bash call (and every other tool
> call in this workflow) **MUST run in the foreground** with `run_in_background` false/omitted and a
> Bash-tool `timeout` of `600000ms`; the call blocks until Codex exits. Backgrounding breaks the
> synchronous sequencing the workflow relies on, and in any headless host the detached Codex is
> **reaped ~5s after the turn's final result**: implementation files may land, but Stages 4–5 never
> run, the round silently stays `doing`, and the process still exits `0` — the exact failure this
> discipline prevents. A round whose Codex stage cannot finish within the 600s window is a **planning
> error** — split the round per `plan-lifecycle.md` — **never** a reason to background. A genuine
> overrun surfaces deterministically as a `timeout-124`/`sigterm` status with partial logs; handle it
> via the Resume Fallback, not by detaching. This rule is now **enforced deterministically** by a
> `PreToolUse(Bash)` hook: a Codex Bash call that is backgrounded, or that omits a `timeout` of at
> least `600000ms`, is blocked before it runs — so the
> reap cannot happen even when this prose is overlooked deep in a long context. The prose remains as
> the rationale; the hook is the guarantee. Details are recorded in
> [`$DOCS_NOTES_REPO/tech/tools/claude-code/orchestration/in-session-vs-headless-delegation.md`](file:///$DOCS_NOTES_REPO/tech/tools/claude-code/orchestration/in-session-vs-headless-delegation.md).

Orchestration patterns shared with `review-loop` (proof-of- delegation, lock management, review-loop
handoff, verdict model) are documented in
[`$DOCS_NOTES_REPO/tech/tools/claude-code/orchestration/`](file:///$DOCS_NOTES_REPO/tech/tools/claude-code/orchestration/).
This skill is the reference implementation; the shared docs describe the contracts.

## Inputs

The workflow needs:

1. A task description. Sources, in order of precedence: the resolved body of the `-t`/`--tsk-impl`
   issue when that flag is set; otherwise `$ARGUMENTS`; otherwise the current conversation context.
2. A repository context summary sufficient for Codex to plan and implement.
3. `codex-session` installed and on `PATH`. The wrapper composes config-recipes, resolves accounts,
   and sets `CODEX_HOME` per-account per-group before passing through to `codex`. Model and
   reasoning effort come from the tier `--profile` (`medium` for stages 1 and 3; `deep` is the
   human-judged escalation tier, used only when the user asks for it). See the "Wrapper:
   `codex-session`" section in
   [`$DOCS_NOTES_REPO/tech/tools/claude-code/codex-conventions.md`](file:///$DOCS_NOTES_REPO/tech/tools/claude-code/codex-conventions.md)
   for the full API reference.

If the task description is missing or materially ambiguous after reviewing the current conversation,
ask one focused clarifying question before starting stage 1.

## Bootstrap: Run Directory and Lock

This is the **first** operational step. `cog` must be on `PATH` (ensure `cog` is installed and on `PATH`). Verify it is present and current, then create the run directory and acquire the
workflow lock in one call:

```bash
command -v cog >/dev/null || {
  echo "prex: missing CLI binary — ensure the cog CLI is installed and on PATH." >&2
  exit 1
}
cog require codex-runner rundir lock prex-parse-args prex-tsk-resolve || {
  echo "prex: stale installation of cog (missing required subcommands) — ensure the cog CLI is installed and on PATH." >&2
  exit 1
}
cog rundir prex --lock --owner-pid "$PPID"
```

This prints two result lines:

```text
RUN_DIR=<path>
LOCK_FILE=<path>
```

Shell state does not persist between Bash tool invocations. Read `RUN_DIR` and `LOCK_FILE` from this
output and **substitute the literal paths** in every subsequent command. All `cog` calls
below use the bare command (it is on `PATH`); no library sourcing or path resolution is needed.

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

- `stage1-plan.txt`
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
cog prex-parse-args "$RUN_DIR" "$ARGUMENTS"
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

- `/prex refactor the foo module` — manual mode
- `/prex -a refactor the foo module` — auto-approve
- `/prex -ar refactor the foo module` — auto-approve + review-loop
- `/prex -t` — resolve tsk id from active branch, use `tsk show` as the task
- `/prex -t 20240415-120030-my-issue` — use an explicit tsk id as the task
- `/prex -a -t 20240415-120030-my-issue` — auto-approve + tsk-sourced task
- `/prex -ar --tsk-impl` — auto-approve + review-loop + tsk-sourced task (id via `tsk id`)

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
   cog prex-tsk-resolve --run-dir "$RUN_DIR" || {
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

## Stage 1: Plan With Codex

Construct a planning prompt that includes:

- A behavioral orientation preamble: the prompt must begin with the read-only orientation block from
  [`$DOCS_NOTES_REPO/tech/tools/claude-code/codex-conventions.md`](file:///$DOCS_NOTES_REPO/tech/tools/claude-code/codex-conventions.md).
  Under the unified-sandbox approach, this block is the **primary behavioral control** for read-only
  enforcement; the CLI no longer enforces it via flags.
- The original task.
- Relevant repo constraints and conventions.
- The requirement to produce a numbered, reviewable plan.
- Assumptions, ambiguities, dependencies, and risks.

Run Codex with the resume-compatible unified sandbox pattern from the reference. Read-only behavior
is enforced by the prompt orientation block.

Write the full Codex planning prompt to a file inside `RUN_DIR` first (e.g.
`$RUN_DIR/stage1-prompt.md`), then pass it through `cog codex-runner run-exec --mode danger`.
Do not inline multi-line prompts directly in the Bash command; follow the prompt-file rule in the
shared orchestration doc.

```bash
cog codex-runner run-exec \
  --mode danger \
  --profile medium \
  --prompt "$RUN_DIR/stage1-prompt.md" \
  --output "$RUN_DIR/stage1-plan.txt" \
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

Read `stage1-plan.txt`, summarize the result briefly for the user, and move directly to stage 2.

## Stage 2: Review The Plan In Claude

Review the Codex plan by delegating the work to a real subagent via the **Agent tool**. The subagent
reads and follows `$HOME/.claude/skills/plan-reviewer/SKILL.md` in an isolated context and writes
the reviewed plan to a known path under `$RUN_DIR`.

Do NOT use the `Skill` tool for this delegation. `Skill` loads a skill's body inline into the
current conversation and does not produce a real fork, which causes the orchestrator to confuse
itself with the child's completion message and stop mid-workflow. The `Agent` tool with
`subagent_type: general-purpose` is the only reliable fork mechanism for nested delegation; see
`$DOCS_NOTES_REPO/tech/tools/claude-code/skills-and-orchestration.md` (Dispatch vs Delegation).

Pass file paths in the prompt, not inlined file contents: the subagent shares the filesystem and can
read the run-dir artifacts directly. The `plan-reviewer` skill body evaluates against correctness,
completeness, feasibility, currency, security, and idiomatic quality, then writes a reviewed plan
with `APPROVED` / `MODIFIED` / `REMOVED` / `ADDED` annotations to the output path specified in the
prompt.

The expected artifact for this stage is:

`$RUN_DIR/stage2-reviewed-plan.md`

Before delegation, snapshot the proof surface in the parent run directory:

```bash
cog codex-runner snapshot-pre "$RUN_DIR" "$RUN_DIR/stage2-pre.snap" \
  > "$RUN_DIR/stage2-pre-snapshot.json"
rm -f "$RUN_DIR/stage2-proof.diff" "$RUN_DIR/stage2-reviewed-plan.md"
```

**Invoke the Agent tool now with:**

- `subagent_type`: `general-purpose`
- `description`: `Review Codex plan`
- `prompt` (substitute the literal value of `$RUN_DIR` before sending):

  ```text
  Read the skill file at $HOME/.claude/skills/plan-reviewer/SKILL.md and follow
  its "Orchestrator Invocation Contract" mode. Your three path arguments are:

  1. plan-path:   <RUN_DIR>/stage1-plan.txt
  2. request-path: <RUN_DIR>/request.md
  3. output-path: <RUN_DIR>/stage2-reviewed-plan.md

  Read the two input files, perform the plan-reviewer workflow (Phases 1-4 of
  its body), and Write the final reviewed plan verbatim to the output path.
  Return a one-line confirmation containing the output path once the file is
  written. Do not modify any repository files outside the output path.
  ```

After the Agent tool call returns, capture the after snapshot and validate proof of delegation:

```bash
cog codex-runner snapshot-post "$RUN_DIR" \
  "$RUN_DIR/stage2-pre.snap" \
  "$RUN_DIR/stage2-post.snap" \
  "$RUN_DIR/stage2-proof.diff" \
  > "$RUN_DIR/stage2-post-snapshot.json"
cog codex-runner verify-proof \
  --proof "$RUN_DIR/stage2-proof.diff" \
  --artifact "$RUN_DIR/stage2-reviewed-plan.md" \
  || { cog lock release "$LOCK_FILE"; exit 1; }
```

`verify-proof` fails closed (exit 1, message on stderr) when the reviewed plan or the proof diff is
missing or empty. Do not continue to the approval loop if delegation proof is incomplete. Do not
retry automatically. Report the failure and ask the user whether to retry or abort.

Before pausing for user approval, temporarily release the workflow lock:

```bash
cog lock release "$LOCK_FILE"
```

### Approval Loop

After saving the reviewed plan and releasing the lock:

- If the mode is `auto-approve` or `auto-approve-review-loop`, display the **complete** reviewed
  plan to the user verbatim, show the file path to `stage2-reviewed-plan.md`, and treat the plan as
  approved without waiting for user input. After displaying the plan, reacquire the lock and proceed
  directly to stage 3.
- Otherwise, enter the approval loop below.

This approval loop repeats until the user explicitly approves or aborts:

1. Display the **complete** reviewed plan to the user verbatim — do not summarize, truncate, or
   collapse sections. The user must be able to read every step on screen before being asked to
   approve. Also show the file path to `stage2-reviewed-plan.md` so the user can reference it.
2. Wait for explicit user input: approval, modification requests, or abort.
3. If the user requests edits: apply the changes directly (do not invoke the Skill tool for
   `plan-reviewer` again), save the updated plan to `stage2-reviewed-plan.md`, and return to step 1.
4. If the user approves (`continue`, `approve`, `go`): exit the loop and proceed to stage 3.
5. If the user aborts (`stop`, `abort`): end the workflow immediately. The lock was already released
   before entering the loop.

If the user's intent is ambiguous (e.g., "looks good but change X"), treat it as an edit request —
apply the change and loop back for explicit approval.

After the user approves and before starting stage 3, reacquire the lock:

```bash
cog lock acquire "$RUN_DIR" --owner-pid "$PPID"
```

## Stage 3: Implement With Codex

Build an implementation prompt containing:

- The write orientation block from
  [`$DOCS_NOTES_REPO/tech/tools/claude-code/codex-conventions.md`](file:///$DOCS_NOTES_REPO/tech/tools/claude-code/codex-conventions.md).
- The statement: `The reviewed plan below supersedes your earlier draft. Implement it exactly.`
- The reviewed plan verbatim.
- An instruction to implement phases in order.
- A requirement to avoid silent deviations.
- A requirement to report files changed, deviations, and uncertainties.

When the resume call succeeds, do not re-send the original task description or repo
constraints/conventions — those remain in the resumed session context from stage 1. When falling
back to a fresh `exec`, inline all context; see **Resume Fallback** below.

Run Codex with the resume-compatible unified sandbox pattern from the reference.

Write the full implementation prompt to a file inside `RUN_DIR` first (e.g.
`$RUN_DIR/stage3-prompt.md`), then pass it to `cog codex-runner run-resume`. Do not inline
multi-line prompts directly in the Bash command; follow the prompt-file rule in the shared
orchestration doc.

```bash
cog codex-runner run-resume \
  --account "$PLAN_ACCOUNT" \
  --thread-id "$PLAN_THREAD_ID" \
  --profile medium \
  --prompt "$RUN_DIR/stage3-prompt.md" \
  --output "$RUN_DIR/stage3-impl-report.txt" \
  --events "$RUN_DIR/stage3-events.jsonl" \
  --stderr "$RUN_DIR/stage3-stderr.log" \
  > "$RUN_DIR/stage3-runner.json"
```

The `--account "$PLAN_ACCOUNT"` pin removes any dependence on auto-selection. The wrapper resolves
the resume to the thread's owner regardless (thread-index hit, or rollout-scan recovery with a
`warning:`); if the pin disagrees with the resolved owner the wrapper warns and proceeds pinned to
the owner — that warning is informational, not a failure.

Read the runner's deterministic classification before branching — do not re-derive the signal by
eyeballing stderr. `run-resume` emits `status` (the exit-code class) and `resume_signal` (the
warning-or-class: a successful resume that emitted a warning surfaces here even though `status` is
`ok`):

```bash
STATUS="$(jq -r '.status' "$RUN_DIR/stage3-runner.json")"
RESUME_SIGNAL="$(jq -r '.resume_signal' "$RUN_DIR/stage3-runner.json")"
EXIT_CODE="$(jq -r '.exit_code' "$RUN_DIR/stage3-runner.json")"
```

### Resume Fallback

Branch on the runner-emitted `resume_signal`/`status` values per the table below — do NOT treat every
resume error as a fresh-exec trigger. For the `resume-no-rollout` status the wrapper's stderr why-line
is the only disambiguator (sandbox-mismatch vs. absent/deleted), so consult
`$RUN_DIR/stage3-stderr.log` for that row only.

| Runner value (`resume_signal` / `status`)                                                         | Meaning                                                                                  | Reaction                                                                                                          |
| ------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------- |
| `resume_signal == recovered-owner` (rollout-scan recovery, `status` `ok`)                         | Thread-index miss; the wrapper found the owner itself and pinned the resume              | Resume **succeeded** — do **not** fall back. The warning is informational.                                        |
| `resume_signal == account-mismatch` (`status` `ok`)                                               | The `$PLAN_ACCOUNT` pin disagreed with the resolved owner; the wrapper used the owner    | Informational; no action.                                                                                         |
| `status == resume-blocked` (`exit_code` 75, `ResumeBlocked`)                                      | The **owning** account is quota-limited; the thread itself is fine                       | **Wait** until the owner's reset time shown in the message, then re-run the same resume. No automatic fresh exec. |
| `status == resume-owner-missing` (`ResumeOwnerMissing` — not in the index or any account)         | The thread is genuinely unknown (typo'd id, or rollout gone from every registered store) | The **only** true fresh-exec trigger — run Steps 1–3 below.                                                       |
| `status == resume-no-rollout` + sandbox-mismatch why-line in stderr                               | Rollout exists locally; the resume used different sandbox flags than the original run    | Re-run the resume with the **same** `--dangerously-bypass-approvals-and-sandbox` flags — **not** a fresh exec.    |
| `status == resume-no-rollout` + absent/deleted why-line in stderr                                 | The owner's rollout was deleted after resolution                                         | Fresh-exec fallback (Steps 1–3 below).                                                                            |
| `status` `nonzero`/`sigterm`/`timeout-124` with empty `stage3-events.jsonl` and none of the above | Unclassified failure (wrapper or environment)                                            | Inspect stderr; if unresolvable, fresh-exec fallback (Steps 1–3 below).                                           |

> **`ResumeBlocked` (exit 75) is NOT a resume-mechanics failure — do not auto-fallback.**
> `exec resume` is account-bound: the rollout exists only in the owner's `CODEX_HOME`, so no
> other account can continue this thread. Prefer to **wait** for the owner's reset and re-run
> the resume. Only fall back to a fresh `exec` if you accept starting a NEW thread with no
> continuity from the planning session — acceptable here because the fallback re-inlines the
> full reviewed plan. Keep auto selection for that fresh exec.

1. Build a self-contained implementation prompt that **inlines** all required context directly in
   the prompt body (do not reference run-dir file paths as instructions for Codex to read). Order
   the inlined sections as: (a) write orientation block, (b) reviewed plan, (c) original request,
   (d) repo constraints, (e) implementation instructions. The orientation block must appear FIRST so
   it gates everything that follows:
   - The write orientation block from `codex-conventions.md`.
   - The full content of `$RUN_DIR/stage2-reviewed-plan.md` (inlined, not referenced).
   - The full content of `$RUN_DIR/request.md` (inlined, not referenced).
   - Relevant repo constraints and conventions from `CLAUDE.md`.
   - The implementation instructions (implement phases in order, report files changed,
     `Do not run any git commands.`, and the literal `Files changed:` section header rule that stage
     4 parses).

2. Write that prompt to `$RUN_DIR/stage3-prompt-full.md`.

3. Run a fresh `exec` (not `resume`) with the inlined prompt:

```bash
cog codex-runner run-exec \
  --mode danger \
  --profile medium \
  --prompt "$RUN_DIR/stage3-prompt-full.md" \
  --output "$RUN_DIR/stage3-impl-report.txt" \
  --events "$RUN_DIR/stage3-events.jsonl" \
  --stderr "$RUN_DIR/stage3-stderr.log" \
  --thread first \
  > "$RUN_DIR/stage3-runner.json"
```

**Critical:** The fallback prompt must NEVER reference external temporary run-dir paths or
`$RUN_DIR` file paths as instructions for Codex to read; the container sandbox may not have access
to those paths. Inline all content directly in the prompt body.

When using Claude Code's Bash tool for either the resume call or the fallback fresh-exec, set the
timeout to `600000ms`. Run it in the **foreground** — `run_in_background` must be false/omitted. This
call blocks until Codex exits; never background it (see **Execution discipline** above).

Extract the implementation thread ID:

```bash
IMPL_THREAD_ID="$(cog codex-runner extract-thread "$RUN_DIR/stage3-events.jsonl" first | jq -r '.thread_id')"
[ -n "$IMPL_THREAD_ID" ] || IMPL_THREAD_ID="$PLAN_THREAD_ID"
```

On the resume success path the implementation reuses the planning session and the JSONL stream
typically does not emit a new `thread.started` — `IMPL_THREAD_ID` falls back to `PLAN_THREAD_ID`. On
the Resume Fallback fresh-`exec` path, the stream emits a new `thread.started` and `IMPL_THREAD_ID`
is that new thread.

Read `stage3-impl-report.txt`, summarize the outcome briefly for the user, and move to stage 4.

## Stage 4: Review The Implementation In Claude

Delegate findings-gathering to the Claude `review-code-deep` skill via the **Agent tool**
(`subagent_type: general-purpose`), then triage the structured JSON output in this orchestrator.
This mirrors the stage 2 delegation to `plan-reviewer` — same snapshot/proof pattern, same
fail-closed contract.

Do NOT use the `Skill` tool for this delegation. See the stage 2 note and
`$DOCS_NOTES_REPO/tech/tools/claude-code/skills-and-orchestration.md` (Dispatch vs Delegation).

### Step 1: Build the review context

Write `$RUN_DIR/stage4-context.md` containing, in this order:

- A one-line orchestrator note: `prex stage 4 — produce JSON findings for orchestrator triage.`
- The original task description (verbatim contents of `$RUN_DIR/request.md`).
- The approved reviewed plan (verbatim contents of `$RUN_DIR/stage2-reviewed-plan.md`).

### Step 2: Snapshot and clear prior artifacts

```bash
cog codex-runner snapshot-pre "$RUN_DIR" "$RUN_DIR/stage4-pre.snap" \
  > "$RUN_DIR/stage4-pre-snapshot.json"
rm -f "$RUN_DIR/stage4-findings.json" "$RUN_DIR/stage4-proof.diff"
```

### Step 3: Delegate to `review-code-deep`

**Invoke the Agent tool now with:**

- `subagent_type`: `general-purpose`
- `description`: `Review implementation`
- `prompt` (substitute the literal value of `$RUN_DIR` before sending):

  ```text
  Read the skill file at $HOME/.claude/skills/review-code-deep/SKILL.md and
  follow its "Orchestrator Invocation Contract" mode. Your two path arguments
  are:

    1. context-path: <RUN_DIR>/stage4-context.md
    2. output-path:  <RUN_DIR>/stage4-findings.json

  Run the review against the current uncommitted diff (capture both
  `git diff` and `git diff --staged`). Produce JSON findings following the
  schema in the shared `llm-review-discipline.md` reference, and Write them
  verbatim to the output path. Reply with the single line `WROTE <output-path>`
  once the file is written. Do not modify any repository files outside the
  output path.
  ```

### Step 4: Capture proof and validate

```bash
cog codex-runner snapshot-post "$RUN_DIR" \
  "$RUN_DIR/stage4-pre.snap" \
  "$RUN_DIR/stage4-post.snap" \
  "$RUN_DIR/stage4-proof.diff" \
  > "$RUN_DIR/stage4-post-snapshot.json"
cog codex-runner verify-proof \
  --proof "$RUN_DIR/stage4-proof.diff" \
  --artifact "$RUN_DIR/stage4-findings.json" \
  --require-json 'has("findings")' \
  || { cog lock release "$LOCK_FILE"; exit 1; }
```

`verify-proof` fails closed (exit 1, message on stderr) on a missing/empty findings file, a
missing/empty proof diff, or findings JSON that lacks a `findings` key. Do not retry automatically.
Report the failure and ask the user whether to retry or abort.

### Step 5: Triage findings (orchestrator only)

Parse `$RUN_DIR/stage4-findings.json` and translate each finding to the prex status vocabulary:

| `review-code-deep` finding                                | prex status                             |
| --------------------------------------------------------- | --------------------------------------- |
| `severity: blocking` or `important`, `confidence: high`   | `FIXED` if the fix is minor and obvious |
| `severity: blocking` or `important`, complex / unclear    | `NEEDS_DISCUSSION`                      |
| `severity: blocking` or `important`, `confidence: medium` | re-verify against code, then map above  |
| `severity: nit` or `suggestion`                           | `ACKNOWLEDGED`                          |
| `severity: question`                                      | `QUESTION`                              |
| `confidence: low` after independent re-check fails        | `DISMISSED`                             |

For each `FIXED`, apply the change directly with Edit/Write. For `NEEDS_DISCUSSION`, pause and
involve the user before continuing.

### Step 6: Plan-conformance check

`review-code-deep` reviews code quality; it does not know about the prex reviewed-plan structure.
Walk each phase in `$RUN_DIR/stage2-reviewed-plan.md` and confirm it appears in the implementation
diff. For any phase that is missing or partially implemented, append a synthetic `NEEDS_DISCUSSION`
row to the triage table with the phase reference.

### Step 7: Write `stage4-review.md`

Record the review summary and triage decisions in `$RUN_DIR/stage4-review.md` using the legacy prex
status vocabulary. Downstream consumers (`prex-stop-gate.sh`) depend on this artifact name and
format — do not rename it. Include:

- One-line summary.
- Triage table (finding → status → action).
- Plan-conformance section (from step 6).
- Open `NEEDS_DISCUSSION` and `QUESTION` items, if any.

After stage 4, decide whether to run stage 5:

- **Forced by mode**: If the mode is `auto-approve-review-loop`, run stage 5 after all stage 4
  `NEEDS_DISCUSSION` items have been resolved. Do not ask the user whether to run it.
- **Auto-trigger**: If the task is clearly complex (multi-phase plan, cross-cutting changes,
  security-sensitive code) **and** all stage 4 `NEEDS_DISCUSSION` items have been resolved,
  recommend stage 5 and proceed unless the user declines.
- **User decides**: If the implementation looks clean or stage 4 concerns were minor, tell the user
  that a review loop is available on request but not required.

## Stage 5: Optional Review Loop

This stage delegates to the `review-loop` skill instead of calling Codex review directly. The
`review-loop` skill creates its own run directory, handles Codex invocation, multi-round triage, and
fix application autonomously, and writes its final summary to `<child-run-dir>/summary.md`.

Run this stage only after all stage 4 `NEEDS_DISCUSSION` items have been resolved, when any of the
following is true:

- The mode is `auto-approve-review-loop`.
- The user requests it (e.g., "deep review", "review loop", "keep reviewing").
- The task is clearly complex.
- Stage 4 found issues substantial enough to justify an extra adversarial pass.

### Handoff to `review-loop`

Before invoking the skill, release the workflow lock so it does not interfere:

```bash
cog lock release "$LOCK_FILE"
```

Build a `review_loop_input.json` file in `$RUN_DIR` with the following structure:

```json
{
  "task": "<contents of request.md>",
  "reviewed_plan": "<contents of stage2-reviewed-plan.md>",
  "stage4_review": "<contents of stage4-review.md>",
  "plan_thread_id": "<PLAN_THREAD_ID or null>",
  "impl_thread_id": "<IMPL_THREAD_ID or null>"
}
```

Read the source files and write the JSON to `$RUN_DIR/review_loop_input.json`.

Before delegation, snapshot the skill-run base directory for `review-loop-*` directories so the
child run dir can be located after the call returns:

```bash
_SKILL_RUNS="${XDG_STATE_HOME:-$HOME/.local/state}/claude-session/skill-runs"
mkdir -p "$_SKILL_RUNS"
find "$_SKILL_RUNS" -maxdepth 1 -type d -name 'review-loop-*' -printf '%p\n' 2>/dev/null | sort > "$RUN_DIR/stage5-pre-rl.snap"
```

**Invoke the Agent tool now with:**

- `subagent_type`: `general-purpose`
- `description`: `Run review loop`
- `prompt` (substitute the literal value of `$RUN_DIR`):

  ```text
  Read the skill file at $HOME/.claude/skills/review-loop/SKILL.md and follow
  its "handoff mode". Your single argument is:

    <RUN_DIR>/review_loop_input.json

  Run the full review loop the skill describes, write the final summary.md to
  the review-loop run directory the skill creates, and return a one-line reply
  containing that run directory path.
  ```

Do NOT use the `Skill` tool for this call — see the stage 2 note and
`$DOCS_NOTES_REPO/tech/tools/claude-code/skills-and-orchestration.md` (Dispatch vs Delegation). The
`Agent` tool is the only mechanism that produces a real fork with a structured return.

After the Agent tool call returns, locate the child run directory and validate proof of delegation:

```bash
_SKILL_RUNS="${XDG_STATE_HOME:-$HOME/.local/state}/claude-session/skill-runs"
mkdir -p "$_SKILL_RUNS"
find "$_SKILL_RUNS" -maxdepth 1 -type d -name 'review-loop-*' -printf '%p\n' 2>/dev/null | sort > "$RUN_DIR/stage5-post-rl.snap"
diff -u "$RUN_DIR/stage5-pre-rl.snap" "$RUN_DIR/stage5-post-rl.snap" > "$RUN_DIR/stage5-proof.diff" || true
RL_RUN_DIR="$(comm -13 "$RUN_DIR/stage5-pre-rl.snap" "$RUN_DIR/stage5-post-rl.snap" | tail -1)"
[ -n "$RL_RUN_DIR" ] || {
  echo "ERROR: review-loop did not create a new run directory under $_SKILL_RUNS"
  exit 1
}
cog codex-runner verify-proof \
  --proof "$RUN_DIR/stage5-proof.diff" \
  --artifact "$RL_RUN_DIR/summary.md" || exit 1
printf '%s\n' "$RL_RUN_DIR" > "$RUN_DIR/stage5-rl-run-dir.txt"
```

The `comm` step locates the new `review-loop-*` directory (proof that delegation actually ran);
`verify-proof` then fails closed unless the snapshot diff is non-empty **and** the child wrote
`summary.md`. Do not retry automatically. Report the failure and ask the user whether to retry, skip
stage 5, or abort the workflow.

The review-loop skill will parse the JSON for task context, the reviewed plan, and prior findings,
then capture the live git diff independently.

When stage 3 resumes the stage 1 session, `impl_thread_id` equals `plan_thread_id`. Both fields are
kept in the handoff JSON for backward compatibility.

After the delegated review loop completes, read `$RL_RUN_DIR/summary.md` and incorporate the results
into the final output of this workflow.

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
  `--profile medium` at both stage 1 and stage 3 call sites; substitute `--profile deep` only when
  the user explicitly asks to escalate a stage (stuck/looping runs, novel design,
  security-critical changes). Do not pass `-m`/`-c model_reasoning_effort`.
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
[ -s "$RUN_DIR/stage1-plan.txt" ] || echo "ERROR: stage1-plan.txt is empty"
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
<!-- moved to cog rundir/lock/prex-parse-args/prex-tsk-resolve/codex-runner gate+verify-proof. -->
