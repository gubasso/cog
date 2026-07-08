## Stage 4: Review Implementation

Delegate findings-gathering to the Claude `review-oneshot` skill via the **Agent tool**
(`subagent_type: general-purpose`), then triage the structured JSON output in this orchestrator.
This follows the Agent-delegation proof pattern: snapshot, delegate, validate proof, then
fail closed if the artifact is missing or invalid.

Do NOT use the `Skill` tool for this delegation. See
`$(cog skill-refs path skills-and-orchestration.md)` (Dispatch vs Delegation).

### Step 1: Build the review context

Write `$RUN_DIR/review-context.md` containing, in this order:

- A one-line orchestrator note: `executor-prex implementation review — produce JSON findings for orchestrator triage.`
- The original task description (verbatim contents of `$RUN_DIR/request.md`).
- The approved reviewed plan (verbatim contents of `$RUN_DIR/vetted-plan.md`).

The reviewed plan source is load-bearing: use `$RUN_DIR/vetted-plan.md`, not the raw input
plan, so `review-oneshot` can perform plan-conformance review from the approved plan.

### Step 2: Snapshot and clear prior artifacts

```bash
cog codex-runner snapshot-pre "$RUN_DIR" "$RUN_DIR/review-pre.snap" \
  > "$RUN_DIR/review-pre-snapshot.json"
rm -f "$RUN_DIR/review-findings.json" "$RUN_DIR/review-proof.diff"
```

### Step 3: Delegate to `review-oneshot`

**Invoke the Agent tool now with:**

- `subagent_type`: `general-purpose`
- `description`: `Review implementation`
- `prompt` (substitute the literal value of `$RUN_DIR` before sending):

  ```text
  Read the skill file at $HOME/.claude/skills/review-oneshot/SKILL.md and
  follow its "Orchestrator Invocation Contract" mode. Your two path arguments
  are:

    1. context-path: <RUN_DIR>/review-context.md
    2. output-path:  <RUN_DIR>/review-findings.json

  Follow that contract exactly: run in orchestrator mode, produce validated
  JSON findings, write them verbatim to the output path, and reply with the
  single line `WROTE <output-path>` once the file is written. Do not modify any
  repository files outside the output path.
  ```

### Step 4: Capture proof and validate

```bash
cog codex-runner snapshot-post "$RUN_DIR" \
  "$RUN_DIR/review-pre.snap" \
  "$RUN_DIR/review-post.snap" \
  "$RUN_DIR/review-proof.diff" \
  > "$RUN_DIR/review-post-snapshot.json"
cog codex-runner verify-proof \
  --proof "$RUN_DIR/review-proof.diff" \
  --artifact "$RUN_DIR/review-findings.json" \
  --require-json 'has("findings")' \
  || { cog lock release "$LOCK_FILE"; exit 1; }
```

`verify-proof` fails closed (exit 1, message on stderr) on a missing/empty findings file, a
missing/empty proof diff, or findings JSON that lacks a `findings` key. Do not retry automatically.
Report the failure and ask the user whether to retry or abort.

The child reply is useful progress signal only. The durable postcondition is the proof-validated
`$RUN_DIR/review-findings.json`; absence or invalidity of that artifact fails closed regardless of
the child response text.

### Step 5: Triage findings (orchestrator only)

Parse `$RUN_DIR/review-findings.json` and translate each finding to the executor-prex status vocabulary:

| `review-oneshot` finding                                     | executor-prex status                    |
| --------------------------------------------------------- | --------------------------------------- |
| `severity: blocking` or `important`, `confidence: high`   | `FIXED` if the fix is minor and obvious |
| `severity: blocking` or `important`, complex / unclear    | `NEEDS_DISCUSSION`                      |
| `severity: blocking` or `important`, `confidence: medium` | re-verify against code, then map above  |
| `severity: nit` or `suggestion`                           | `ACKNOWLEDGED`                          |
| `severity: question`                                      | `QUESTION`                              |
| `confidence: low` after independent re-check fails        | `DISMISSED`                             |

For each `FIXED`, apply the change directly with Edit/Write. For `NEEDS_DISCUSSION`, pause and
involve the user before continuing.

Plan-conformance gaps arrive as ordinary `review-oneshot` findings because Step 1 includes the
approved reviewed plan in `$RUN_DIR/review-context.md`. Apply the same status mapping to
plan-conformance findings as to code-quality findings: blocking or important gaps are `FIXED` only
when the fix is minor and obvious; otherwise they are `NEEDS_DISCUSSION`.

### Step 6: Write `review.md`

Record the review summary and triage decisions in `$RUN_DIR/review.md` using the executor-prex
status vocabulary. Downstream consumers (the `cog hook-guard executor-prex-stop` Stop-gate) depend
on this
artifact name and format — do not rename it. Include:

- One-line summary.
- Triage table (finding → status → action).
- Plan-conformance findings summary, if any, sourced from `review-oneshot` findings.
- Open `NEEDS_DISCUSSION` and `QUESTION` items, if any.

After the implementation review, decide whether to run the review loop:

- **Forced by mode**: If the mode is `auto-approve-review-loop`, run the review loop after all
  `NEEDS_DISCUSSION` items have been resolved. Do not ask the user whether to run it.
- **Auto-trigger**: If the task is clearly complex (multi-phase plan, cross-cutting changes,
  security-sensitive code) **and** all `NEEDS_DISCUSSION` items have been resolved,
  recommend the review loop and proceed unless the user declines.
- **User decides**: If the implementation looks clean or the review concerns were minor, tell the user
  that a review loop is available on request but not required.
