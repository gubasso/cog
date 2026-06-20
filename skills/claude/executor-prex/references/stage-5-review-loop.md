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
