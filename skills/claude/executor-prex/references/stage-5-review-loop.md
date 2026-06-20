## Stage 5: Optional Review Loop

This stage delegates to the leaned `review-loop` skill instead of calling Codex review directly. The
`review-loop` skill validates the handoff input through `cog review-loop-input validate`, creates its
own run directory, handles Codex invocation, multi-round triage, and fix application autonomously,
and writes its final summary to `<child-run-dir>/summary.md`.

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

Assemble and validate the handoff input. `cog review-loop-input` owns the handoff schema; `build`
reads `request.md`, `stage2-reviewed-plan.md`, `stage4-review.md`, and the optional thread-id files
from `$RUN_DIR`, assembles `{task, reviewed_plan, stage4_review, plan_thread_id, impl_thread_id}`,
and validates the result before it is written:

```bash
cog review-loop-input build \
  --run-dir "$RUN_DIR" \
  --out "$RUN_DIR/review_loop_input.json"
```

When stage 3 resumes the stage 1 session, `impl_thread_id` equals `plan_thread_id`; both fields are
kept in the handoff JSON for backward compatibility and may be null. The schema and its
required-field contract are owned and enforced by `cog review-loop-input`; do not restate or
hand-format the JSON here.

Before delegation, snapshot the run base directory for existing `review-loop-*` children so the new
child run dir can be located after the call returns. `cog rundir snapshot-children` resolves the base
from `cog rundir` itself (never a hardcoded path, so this never drifts when the base moves) and
writes the sorted snapshot:

```bash
cog rundir snapshot-children \
  --prefix review-loop \
  --out "$RUN_DIR/stage5-pre-rl.snap"
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
`cog rundir locate-child` takes the matching pre/post snapshots, writes the proof diff, and emits the
new `review-loop-*` directory. Both snapshots scan the identical `cog rundir` base:

```bash
cog rundir snapshot-children \
  --prefix review-loop \
  --out "$RUN_DIR/stage5-post-rl.snap"
cog rundir locate-child \
  --pre "$RUN_DIR/stage5-pre-rl.snap" \
  --post "$RUN_DIR/stage5-post-rl.snap" \
  --proof "$RUN_DIR/stage5-proof.diff"
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
  --proof "$RUN_DIR/stage5-proof.diff" \
  --artifact "$RL_RUN_DIR/summary.md" || exit 1
printf '%s\n' "$RL_RUN_DIR" > "$RUN_DIR/stage5-rl-run-dir.txt"
```

`cog rundir locate-child` writes the snapshot diff and identifies the new `review-loop-*` directory
(proof that delegation actually ran); `verify-proof` then fails closed unless the snapshot diff is
non-empty **and** the child wrote `summary.md`. Do not retry automatically. Report the failure and
ask the user whether to retry, skip stage 5, or abort the workflow.

The review-loop skill parses the validated JSON for task context, the reviewed plan, and prior
findings, then captures the live git diff independently.

After the delegated review loop completes, read `$RL_RUN_DIR/summary.md` and incorporate the results
into the final output of this workflow.
