## Stage 4: Optional Review Loop

This stage delegates to the leaned `review-loop` skill instead of calling Codex review directly. The
`review-loop` skill validates the handoff input through `cog review-loop-input validate`, creates its
own run directory, handles Codex invocation, multi-round triage, and fix application autonomously,
and writes its final summary to `<child-run-dir>/summary.md`.

Run this stage only after all stage 3 `NEEDS_DISCUSSION` items have been resolved, when any of the
following is true:

- The mode is `auto-approve-review-loop`.
- The user requests it (e.g., "deep review", "review loop", "keep reviewing").
- The task is clearly complex.
- Stage 3 found issues substantial enough to justify an extra adversarial pass.

### Handoff to `review-loop`

Before invoking the skill, release the workflow lock so it does not interfere:

```bash
cog lock release "$LOCK_FILE"
```

Assemble and validate the handoff input. `cog review-loop-input` owns the handoff schema; `build`
reads `request.md`, `vetted-plan.md`, `review.md`, and the optional thread-id files
from `$RUN_DIR`, assembles `{task, reviewed_plan, implementation_review, plan_thread_id, impl_thread_id}`,
and validates the result before it is written:

```bash
cog review-loop-input build \
  --run-dir "$RUN_DIR" \
  --out "$RUN_DIR/review_loop_input.json"
```

When a rich-context brief conforming to
`$(cog skill-refs path orchestration/context-brief-contract.md)` has been assembled for this run,
pass it through with `--context "$RUN_DIR/context-brief.md"`; the consumer then seeds its round-1
context from that brief instead of reassembling one. Omit the flag when no brief was built — the
canonical 5-key envelope is unchanged and the consumer assembles its own context from `task`,
`reviewed_plan`, and `implementation_review`.

Stage 2 runs as a fresh Codex exec, so `plan_thread_id` is normally null while `impl_thread_id`
records the implementation exec when available. Both fields are kept in the handoff JSON and may be
null. The schema and its
required-field contract are owned and enforced by `cog review-loop-input`; do not restate or
hand-format the JSON here.

Before delegation, snapshot the run base directory for existing `review-loop-*` children so the new
child run dir can be located after the call returns. `cog rundir snapshot-children` resolves the base
from `cog rundir` itself (never a hardcoded path, so this never drifts when the base moves) and
writes the sorted snapshot:

```bash
cog rundir snapshot-children \
  --prefix review-loop \
  --out "$RUN_DIR/review-loop-pre.snap"
```

**Invoke the Agent tool now with:**

- `subagent_type`: `general-purpose`
- `description`: `Run review loop`
- `prompt` (substitute the literal value of `$RUN_DIR`):

  ```text
  Read the skill file at $HOME/.claude/skills/review-loop/SKILL.md and follow
  its "handoff mode". Your single argument is:

    <RUN_DIR>/review_loop_input.json

  Run the full review loop the skill describes. It is not complete until you
  have written summary.md via `cog review-loop-summary build`, confirmed it with
  `cog review-loop-summary validate`, and your reply's final line is exactly the
  `REVIEW_LOOP_OK <run-dir> rounds=<n> reason=<reason>` line that build printed,
  with no text after it. Do not reply with an inline triage summary — that
  belongs in summary.md.
  ```

Capture the `agentId` the Agent tool returns; the recovery branch below reuses it.

Do NOT use the `Skill` tool for this call — see
`$(cog skill-refs path skills-and-orchestration.md)` (Dispatch vs Delegation). The
`Agent` tool is the only mechanism that produces a real fork with a structured return.

After the Agent tool call returns, locate the child run directory and validate proof of delegation.
`cog rundir locate-child` takes the matching pre/post snapshots, writes the proof diff, and emits the
new `review-loop-*` directory. Both snapshots scan the identical `cog rundir` base:

```bash
cog rundir snapshot-children \
  --prefix review-loop \
  --out "$RUN_DIR/review-loop-post.snap"
cog rundir locate-child \
  --pre "$RUN_DIR/review-loop-pre.snap" \
  --post "$RUN_DIR/review-loop-post.snap" \
  --proof "$RUN_DIR/review-loop-proof.diff"
```

`cog rundir locate-child` prints one result line:

```text
CHILD_RUN_DIR=<path>
```

Read that path as `RL_RUN_DIR`. If `CHILD_RUN_DIR` is empty, the review-loop did not create a new run
directory; report the failure and stop (do not retry automatically). Otherwise validate proof and
record the child run dir:

```bash
cog codex-runner verify-proof \
  --proof "$RUN_DIR/review-loop-proof.diff" \
  --artifact "$RL_RUN_DIR/summary.md"
```

`cog rundir locate-child` writes the snapshot diff and identifies the new `review-loop-*` directory
(proof that delegation actually ran); `verify-proof` then fails closed unless the snapshot diff is
non-empty **and** the child wrote `summary.md`. On success, record the child run dir and continue:

```bash
printf '%s\n' "$RL_RUN_DIR" > "$RUN_DIR/review-loop-run-dir.txt"
```

**Bounded recovery (at most once).** When `verify-proof` fails but the located `$RL_RUN_DIR` shows the
loop actually ran — `$RL_RUN_DIR/round-1-findings.json` exists — the child completed its review but
skipped Final Output (the drift this contract guards against). Do not hard-fail yet: re-dispatch the
**same** child once to finish only the terminal step. Prefer `SendMessage` to the captured `agentId`
(it retains round context to author an accurate body); if that agent is no longer addressable, use a
fresh `Agent` (`subagent_type: general-purpose`) pointed at the existing `$RL_RUN_DIR`. Instruct it:

```text
Complete Final Output only for the review-loop run at <RL_RUN_DIR>. Write
summary-body.md per the skill's required sections, run `cog review-loop-summary
build --run-dir <RL_RUN_DIR> --termination-reason <reason> --body <RL_RUN_DIR>/summary-body.md`,
then `cog review-loop-summary validate --run-dir <RL_RUN_DIR>`, and reply with
exactly the REVIEW_LOOP_OK line that build printed.
```

Then re-run the `verify-proof` command above. If it now passes, record the run dir and continue. If it
still fails — or `$RL_RUN_DIR/round-1-findings.json` was absent (the loop never ran) — stop without a
further retry: report the failure and ask the user whether to retry stage 4, skip it, or abort the
workflow.

The review-loop skill parses the validated JSON for task context, the reviewed plan, and prior
findings, then captures the live git diff independently.

After the delegated review loop completes, read `$RL_RUN_DIR/summary.md` and incorporate the results
into the final output of this workflow.
