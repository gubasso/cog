## Stage 2: Review The Plan In Claude

Review the Codex plan by delegating the work to a real subagent via the **Agent tool**. The subagent
reads and follows `$HOME/.claude/skills/plan-reviewer/SKILL.md` in an isolated context and writes
the reviewed plan to a known path under `$RUN_DIR`.

Do NOT use the `Skill` tool for this delegation. `Skill` loads a skill's body inline into the
current conversation and does not produce a real fork, which causes the orchestrator to confuse
itself with the child's completion message and stop mid-workflow. The `Agent` tool with
`subagent_type: general-purpose` is the only reliable fork mechanism for nested delegation; see
`$(cog skill-refs path skills-and-orchestration.md)` (Dispatch vs Delegation).

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

- The write orientation block emitted by `cog codex-runner orientation write`.
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
   - The write orientation block from `cog codex-runner orientation write`.
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
`$(cog skill-refs path skills-and-orchestration.md)` (Dispatch vs Delegation).

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
status vocabulary. Downstream consumers (the `cog hook-guard prex-stop` Stop-gate) depend on this
artifact name and format — do not rename it. Include:

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

Before delegation, snapshot the run base directory for `review-loop-*` directories so the
child run dir can be located after the call returns. The base is whatever `cog rundir` creates
into — ask `cog` rather than hardcoding a path, so this never drifts when the base moves:

```bash
_SKILL_RUNS="$(cog rundir --base)"
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
`$(cog skill-refs path skills-and-orchestration.md)` (Dispatch vs Delegation). The
`Agent` tool is the only mechanism that produces a real fork with a structured return.

After the Agent tool call returns, locate the child run directory and validate proof of delegation.
Use the same `cog rundir --base` value as the pre-snapshot so both sides scan the identical base:

```bash
_SKILL_RUNS="$(cog rundir --base)"
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
