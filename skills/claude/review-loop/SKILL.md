---
name: review-loop
description: >
  Automated review loop: Codex reviews uncommitted changes, Claude triages
  findings and applies fixes, Codex re-reviews until clean or max rounds.
  Use when the user wants iterative code review, says "review loop", "keep
  reviewing until clean", or wants automated multi-pass review with Codex.
argument-hint: "[task context or path to review_loop_input.json]"
context: fork
agent: general-purpose
allowed-tools: Bash Read Write Edit
---

<!-- trigger-tests: "review loop", "keep reviewing until clean", "iterative code review", "multi-pass review with Codex" -->

# Review Loop

Orchestrate an automated review loop: each round invokes the Codex `review-code-deep` twin in
orchestrator mode against the live diff (one-shot, read-only sandbox, structured JSON output);
Claude triages findings and applies fixes; the cycle repeats until the JSON output declares the
review complete (`findings == []` or `decision == "approve"`), max rounds are reached, or the user
intervenes.

Each round is independent — there is no `codex-session exec resume`. The per-round
context file carries intent and prior-round triage forward so the reviewer does not re-raise
resolved issues.

Prepend the read-only orientation preamble from `cog codex-runner orientation read-only` to every
Codex review prompt; it is the primary behavioral control for read-only enforcement. CLI invocation
patterns and timeout requirements are owned by the `cog codex-runner run-exec` surface used below.
The Codex twin of `review-code-deep` lives at
`codex-session/.agents/skills/review-code-deep/SKILL.md` — its "Orchestrator Invocation Contract"
section defines the per-round input/output protocol used here.

## Inputs

Two modes depending on `$ARGUMENTS`:

**Handoff mode** — `$ARGUMENTS` is the absolute path to a `review_loop_input.json` file produced by
`executor-prex` stage 5. Before reading it, validate the orchestrator-supplied handoff file through the
deterministic `cog review-loop-input` surface; that command owns the handoff schema and validation
contract.

```bash
cog review-loop-input validate --input "$ARGUMENTS"
```

Pass `--json` only when machine-readable validation output is needed. After validation, use the
handoff fields for judgment context:

- `task` — the original task description.
- `reviewed_plan` — the approved implementation plan from stage 2.
- `stage4_review` — stage 4 review findings and their triage statuses.
- `plan_thread_id` and `impl_thread_id` — Codex thread IDs from the upstream workflow. These are
  informational only and are not consumed by the loop. Each round invokes `review-code-deep` as a
  fresh one-shot, so no upstream session continuity is needed.

For loop judgment, `task`, `reviewed_plan`, and `stage4_review` are the content fields that feed
round context; `plan_thread_id` and `impl_thread_id` are informational and may be null. The handoff
schema and its authoritative required-field contract are owned and enforced by
`cog review-loop-input validate`; the loop reads the fields above for judgment context only and does
not restate that validation rule. The review-loop still captures the live git diff independently —
the JSON provides intent and prior-review context, not the code state.

**Standalone mode** — `$ARGUMENTS` is a task description or empty. Gather context from:

- The current conversation history.
- `git diff` and `git diff --staged` for uncommitted changes.
- `git diff --name-only` and `git diff --staged --name-only` for the changed file list.
- `git log --oneline -10` for recent commits — if the diff is empty but recent commits exist, review
  the latest commit(s) using `git diff HEAD~1` (or the appropriate range) so that post-commit
  invocations have code to review.

If there is insufficient context to understand what the changes are meant to accomplish, ask one
focused clarifying question before starting round 1.

## Codex CLI Reference

Codex invocation mechanics are owned by the `cog codex-runner` surface (`run-exec`, `gate`,
`orientation`, `explain-status`); the maintenance reference is `docs/reference/codex-conventions.md`.
The following guardrails are inlined here as critical safety constraints:

- Every round invokes the Codex `review-code-deep` twin one-shot via
  `codex-session exec` in orchestrator mode. There is no
  `codex-session exec resume`; each round is independent and re-establishes context
  from `$RUN_DIR/round-N-context.md`.
- Native sandbox: `--sandbox read-only --json --output-last-message`. Fallback sandbox:
  `-c 'sandbox_permissions=["disk-full-read-access"]' --json --output-last-message`. See the
  Environment Compatibility section in the shared conventions file.
- Round 1 passes `--effort medium` — the first full-diff review gets the flagship model at the
  quality-default effort. Rounds 2+ use `--effort low` (same model, low effort) since they are
  continuations reviewing incremental, already-triaged fixes. Substitute `--effort deep` for a
  round only when the user explicitly asks to escalate (e.g. a stuck/looping review). Never pass
  `-m`/`-c` flags at the call site.
- Never use `--approval-policy` or `-a` (not supported for `codex-session exec`).
- Never use `codex-session review --uncommitted` (does not support `--json` or
  `--output-last-message`; output capture is unreliable).
- **Run every Codex call in the foreground** with `run_in_background` false/omitted and a Bash-tool
  `timeout` of `600000ms`; the call blocks until Codex exits. **Never background it.** `review-loop`
  often runs in a headless / forked context (it carries `context: fork` and is handed off from executor-prex
  stage 5) and may run as a nested subagent (Claude Code ≥ v2.1.172). In any headless host a
  backgrounded Codex run is reaped ~5s after the turn's final result, silently losing the round's
  review while the process still exits `0`. A review that cannot finish within 600s is a scope
  problem, not a reason to detach; a genuine overrun surfaces as a `timeout-124`/`sigterm` status.
- `SANDBOX_MODE` is resolved by the Pre-flight: Check Codex and Sandbox section before round 1. If the
  calling workflow already set `SANDBOX_MODE`, the preflight will confirm or override it.
- The runner always passes `< /dev/null` and captures stderr directly to `round-N-stderr.log` so the
  benign stdin-notice does not pollute the captured JSON.

## Run Directory

Create a temporary directory for all loop artifacts:

```bash
cog rundir review-loop
```

Shell state does not persist between Bash tool invocations. Substitute the literal path in
subsequent commands, or re-assign `RUN_DIR` at the start of each Bash call.

## Pre-flight: Check Codex and Sandbox

After `RUN_DIR` creation and before the first Codex call, gate environment readiness with
`cog codex-runner gate sandbox` — a single deterministic Bash call, no subagent. This runs
once per skill invocation, not before every round. The `sandbox` gate is a superset of codex
availability/health, so one call resolves availability, health, and sandbox mode. It **fails closed** —
exits non-zero with a legible message (and so does a missing helper). On success it leaves a valid
`preflight.json` from which the sandbox mode is read with a trivial `jq`.

```bash
cog codex-runner gate sandbox "$RUN_DIR/preflight.json" || exit 1
SANDBOX_MODE="$(jq -r '.codex_session.sandbox_mode' "$RUN_DIR/preflight.json")"
echo "SANDBOX_MODE=$SANDBOX_MODE"
```

Persist `SANDBOX_MODE` by substituting its literal value in subsequent commands (shell state does
not persist between Bash tool invocations).

If `SANDBOX_MODE=fallback`, briefly inform the user:

> Native Codex sandbox unavailable (container environment). Using config-based sandbox for read-only
> calls and bypass mode for implementation.

Artifacts written during the loop:

- `round-N-context.md` — assembled per-round context (task, plan, prior triage) passed to the Codex
  `review-code-deep` twin in orchestrator mode.
- `round-N-prompt.txt` — the literal `codex-session exec` prompt for round N (two
  paths plus a short orientation note).
- `round-N-findings.json` — Codex's last-message JSON payload (the `review-code-deep` output) for
  round N.
- `round-N-events.jsonl` — JSONL event stream for round N.
- `round-N-stderr.log` — Codex stderr capture for round N.
- `round-N-triage.md` — triage report for round N.
- `summary.md` — final summary after the loop ends.

## Context Gathering

Before each round N, assemble context and write it to `$RUN_DIR/round-N-context.md`. The Codex
`review-code-deep` twin re-captures the live `git diff` and changed file list itself in orchestrator
mode — this context file carries intent and prior-round state only.

Round 1 contents:

1. **Task description** — from handoff JSON `task` field, or `$ARGUMENTS`, or conversation context.
2. **Reviewed plan** — from handoff JSON `reviewed_plan` field if in handoff mode. Gives the
   reviewer the intended design so it can verify correctness, not just style.
3. **Pre-existing findings** — from handoff JSON `stage4_review` field if in handoff mode (include
   their triage statuses so Codex does not re-raise findings already addressed).

Round 2+ contents:

1. **Task description** — same as round 1 (each round is independent; the Codex session does not
   carry over).
2. **Reviewed plan** — same as round 1, if in handoff mode.
3. **Previous round triage** — verbatim contents of `$RUN_DIR/round-(N-1)-triage.md`.
4. **Fixes since previous round** — short summary of what Claude changed (file paths + one-line
   each).
5. **User guidance**, if any, received since the last round.

If both `git diff` and `git diff --staged` are empty, fall back to `git diff HEAD~1` to capture the
most recent commit. Note this fallback in the context file so the reviewer knows which range to
inspect.

## Review Round

For each round N (starting at 1, up to MAX_ROUNDS):

### Step 1: Construct Prompt

Build the round prompt and write it to `$RUN_DIR/round-N-prompt.txt`. The prompt opens with the
explicit `$review-code-deep` skill mention plus two absolute paths so the Codex twin enters
orchestrator mode (see its "Orchestrator Invocation Contract" section).

```text
$review-code-deep <RUN_DIR>/round-N-context.md <RUN_DIR>/round-N-output-marker

You are running as the round-N reviewer for an automated review loop.
Read the context file, capture the live git diff (and `git diff --staged`),
run the review, and emit the JSON document as your final message. Do not
write any files. Use read-only git commands only (`git diff`,
`git diff --staged`, `git diff --name-only`, `git log`); never run mutating
git commands (commit, add, push, reset, checkout, stash, etc.).
```

Substitute the literal `RUN_DIR` path and the literal round number before writing the file. The
`<RUN_DIR>/round-N-output-marker` second arg is symbolic — the Codex twin emits JSON as its last
message, captured via `--output-last-message`.

### Step 2: Invoke Codex

Select the effort tier based on round number: round 1 passes `medium`; rounds 2+ pass `low`. Invoke
Codex through `cog codex-runner run-exec`; the runner owns the exact native/fallback
`codex-session exec` form, `< /dev/null`, direct stderr capture, output-last-message capture, and
error classification.

```bash
if [ "$N" -eq 1 ]; then EFFORT="medium"; else EFFORT="low"; fi
RUNNER_MODE="$SANDBOX_MODE"
[ "$RUNNER_MODE" = "native" ] || RUNNER_MODE="fallback"
cog codex-runner run-exec \
  --mode "$RUNNER_MODE" \
  --effort "$EFFORT" \
  --prompt "$RUN_DIR/round-N-prompt.txt" \
  --output "$RUN_DIR/round-N-findings.json" \
  --events "$RUN_DIR/round-N-events.jsonl" \
  --stderr "$RUN_DIR/round-N-stderr.log" \
  > "$RUN_DIR/round-N-runner.json"
```

Set the Bash tool timeout to `600000ms` and keep the call in the **foreground**
(`run_in_background` false/omitted) — it blocks until Codex exits; never background it. Each round is
independent — there is no `codex-session exec resume` and no review-thread-ID extraction.

Validate the runner outcome and captured output before triaging:

```bash
jq -e '.status == "ok"' "$RUN_DIR/round-N-runner.json" >/dev/null || {
  echo "ERROR: codex review for round N failed"
  jq '.' "$RUN_DIR/round-N-runner.json" >&2
  exit 1
}
[ -s "$RUN_DIR/round-N-findings.json" ] || {
  echo "ERROR: codex review for round N produced no output"
  exit 1
}
jq -e 'has("findings")' "$RUN_DIR/round-N-findings.json" > /dev/null || {
  echo "ERROR: round-N-findings.json is not a valid review-code-deep JSON document"
  exit 1
}
```

### Step 3: Check Termination

Parse `$RUN_DIR/round-N-findings.json` and end the loop if **any** of the following hold:

- `findings` array is empty.
- Top-level `decision` is `"approve"`.

In either case, proceed directly to **Final Output**. The literal phrase `REVIEW COMPLETE` is no
longer used.

### Step 4: Triage Findings

Parse `$RUN_DIR/round-N-findings.json` and walk each entry in the `findings` array. The schema is
defined in
[`$DOCS_NOTES_REPO/tech/programming/code-review/llm-review-discipline.md`](file:///$DOCS_NOTES_REPO/tech/programming/code-review/llm-review-discipline.md)
— fields include `severity`, `file`, `line_start`, `line_end`, `category`, `headline`, `evidence`,
`reasoning`, `suggestion`, and `confidence`.

For each finding:

1. **Relevance check**: Is the finding technically correct? Is it aligned with the task scope and
   not about unrelated code?
2. **Doc verification**: For `blocking`/`important`/`suggestion` findings, verify the claim against
   the current code, local documentation, and official sources. Use web search if the finding
   references API behavior, library semantics, or external specifications.
3. **Translate severity → status**:
   - `blocking` / `important` with `confidence in {high, medium}` → `FIXED` if the fix is minor and
     obvious, otherwise `NEEDS_DISCUSSION`.
   - `nit` / `suggestion` → `ACKNOWLEDGED`.
   - `question` → `QUESTION` (answer it in the next round's context file).
   - `praise` → drop (positive notes are not actionable).
   - Anything with `confidence: low` that fails an independent re-check → `DISMISSED`.

### Step 5: Apply Fixes

For all findings marked `FIXED`, edit the code directly. Make the minimal change needed to address
each finding.

### Step 6: Write Triage Report

Save the triage report to `$RUN_DIR/round-N-triage.md` using this format:

```markdown
# Round N Triage

### Finding 1: <short title>

- **Type**: Issue | Suggestion | Question
- **Status**: FIXED | ACKNOWLEDGED | DISMISSED | NEEDS_DISCUSSION | QUESTION
- **Reasoning**: <1-2 sentences>
- **Action taken**: <what changed, or why skipped>

### Finding 2: <short title>

...
```

### Step 7: NEEDS_DISCUSSION Check

If any findings have status `NEEDS_DISCUSSION`, pause the loop:

- Present each `NEEDS_DISCUSSION` finding to the user with full context.
- Wait for user input before continuing.
- Append the user's response to the triage report before resuming.

### Status Line

After completing triage for a round, output a brief status:

```text
Round N: X fixed, Y acknowledged, Z dismissed. Continuing...
```

## Loop Orchestration

- **MAX_ROUNDS** = 5 (overridable if the user specifies a different limit in `$ARGUMENTS` or
  conversation).
- Do NOT ask "shall I continue?" between rounds — loop autonomously.
- Only pause for `NEEDS_DISCUSSION` findings or errors.
- If MAX_ROUNDS is reached without the JSON-termination condition being met (empty `findings` or
  `decision == "approve"`), inform the user and present all remaining `ACKNOWLEDGED`,
  `NEEDS_DISCUSSION`, and `QUESTION` items.

## Error Handling

If `codex-runner` reports a non-`ok` status (non-zero exit, empty output file, SIGTERM, timeout, or
quota):

1. Report the error to the user, including any stderr output.
2. Do not retry automatically.
3. Ask the user whether to retry the failed round, skip it, or abort the loop.

**Quota tempfail (exit 75) is a wait, not a hot retry.** If a round's wrapper exits 75
with an `account: AutoExhausted` or `account: no eligible account` message, every usable
account is out of quota / rate-limited / in cooldown. These messages carry per-account
reset ETAs and an `earliest available: <dur> (<HH:MM UTC>)` summary. Do NOT immediately
re-fire the round — that just burns into the same 429. Surface the ETA to the user and
wait until the earliest-available time before retrying (or let the user decide). Note
also that exit 75 may arrive with a still-valid review JSON in the
`--output-last-message` file when the _previous_ account completed the review before the
next rotation 429'd; check that file before discarding the round. (Quota thresholds are
soft penalty knees as of 2026-06-02; run `cog codex-runner explain-status <status>` for the
quota/error interpretation.)

## User Intervention

The user can type at any time during the loop:

- **"stop"** or **"abort"**: End the loop gracefully and produce the final summary with whatever
  rounds completed.
- **Guidance or corrections**: Incorporate into the next round's prompt as additional context.
- **Response to NEEDS_DISCUSSION**: Append to the triage report, then resume the loop.

## Final Output

When the loop ends (empty `findings`, `decision == "approve"`, max rounds, or user abort), write a
summary to `$RUN_DIR/summary.md` and present it to the user:

- Total rounds executed.
- Per-round breakdown: how many findings were fixed, acknowledged, dismissed, or flagged for
  discussion.
- Files changed across all rounds (from `git diff --name-only` vs the state at loop start).
- Any remaining `NEEDS_DISCUSSION` or `ACKNOWLEDGED` items.
- The termination reason: `findings-empty`, `decision-approve`, `max-rounds`, or `user-abort`.

## Guardrails

- Codex never edits code; all fixes are applied by Claude Code.
- Every round runs in read-only mode (`--sandbox read-only` native, or
  `-c 'sandbox_permissions=["disk-full-read-access"]'` fallback). Round 1 uses `--effort
  medium`; rounds 2+ use `--effort low`. No `codex-session exec resume`;
  each round is a fresh one-shot invocation of the Codex `review-code-deep` twin in orchestrator
  mode.
- Never use `--approval-policy` or `-a` (not supported for `codex-session exec`).
- Never use `codex-session review --uncommitted` (no `--json` / `--output-last-message`).
- Never skip triage — every finding must be classified and assigned a status.
- Never ask "shall I continue?" between rounds — the loop runs autonomously.
- Codex may run read-only git inspection commands needed to review the diff (`git diff`,
  `git diff --staged`, `git diff --name-only`, `git log`), but must never mutate git state
  (commit, add/stage, push, reset, checkout, stash, etc.). Only the Claude Code orchestrator
  performs git mutations.
- Delegate deterministic mechanics (run-dir, gate, Codex exec) to versioned `cog`
  subcommands; keep only judgment (triage, termination, finding validation) as prose.
- Do not duplicate the full Codex CLI conventions or `review-code-deep` body here; reference the
  shared files.
