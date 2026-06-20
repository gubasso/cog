## Stage 4: Review Implementation

Delegate findings-gathering to the Claude `review-code-deep` skill via the **Agent tool**
(`subagent_type: general-purpose`), then triage the structured JSON output in this orchestrator.
This mirrors the stage 2 Agent-delegation proof pattern: snapshot, delegate, validate proof, then
fail closed if the artifact is missing or invalid.

Do NOT use the `Skill` tool for this delegation. See the stage 2 note and
`$(cog skill-refs path skills-and-orchestration.md)` (Dispatch vs Delegation).

### Step 1: Build the review context

Write `$RUN_DIR/stage4-context.md` containing, in this order:

- A one-line orchestrator note: `prex stage 4 — produce JSON findings for orchestrator triage.`
- The original task description (verbatim contents of `$RUN_DIR/request.md`).
- The approved reviewed plan (verbatim contents of `$RUN_DIR/stage2-reviewed-plan.md`).

The reviewed plan source is load-bearing: use `$RUN_DIR/stage2-reviewed-plan.md`, not the original
Stage 1 plan, so `review-code-deep` can perform plan-conformance review from the approved plan.

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

  Follow that contract exactly: run in orchestrator mode, produce validated
  JSON findings, write them verbatim to the output path, and reply with the
  single line `WROTE <output-path>` once the file is written. Do not modify any
  repository files outside the output path.
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

The child reply is useful progress signal only. The durable postcondition is the proof-validated
`$RUN_DIR/stage4-findings.json`; absence or invalidity of that artifact fails closed regardless of
the child response text.

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

Plan-conformance gaps arrive as ordinary `review-code-deep` findings because Step 1 includes the
approved reviewed plan in `$RUN_DIR/stage4-context.md`. Apply the same status mapping to
plan-conformance findings as to code-quality findings: blocking or important gaps are `FIXED` only
when the fix is minor and obvious; otherwise they are `NEEDS_DISCUSSION`.

### Step 6: Write `stage4-review.md`

Record the review summary and triage decisions in `$RUN_DIR/stage4-review.md` using the legacy prex
status vocabulary. Downstream consumers (the `cog hook-guard executor-prex-stop` Stop-gate) depend
on this
artifact name and format — do not rename it. Include:

- One-line summary.
- Triage table (finding → status → action).
- Plan-conformance findings summary, if any, sourced from `review-code-deep` findings.
- Open `NEEDS_DISCUSSION` and `QUESTION` items, if any.

After stage 4, decide whether to run stage 5:

- **Forced by mode**: If the mode is `auto-approve-review-loop`, run stage 5 after all stage 4
  `NEEDS_DISCUSSION` items have been resolved. Do not ask the user whether to run it.
- **Auto-trigger**: If the task is clearly complex (multi-phase plan, cross-cutting changes,
  security-sensitive code) **and** all stage 4 `NEEDS_DISCUSSION` items have been resolved,
  recommend stage 5 and proceed unless the user declines.
- **User decides**: If the implementation looks clean or stage 4 concerns were minor, tell the user
  that a review loop is available on request but not required.
