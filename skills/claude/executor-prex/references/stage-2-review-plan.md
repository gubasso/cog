## Stage 2: Review Plan

Review the Codex plan by delegating the work to a real subagent via the **Agent tool**. The subagent
runs `/review-plan-lean` in orchestrator mode with three absolute paths and writes the reviewed
plan to a known path under `$RUN_DIR`.

Do NOT use the `Skill` tool for this delegation. `Skill` loads a skill's body inline into the
current conversation and does not produce a real fork, which causes the orchestrator to confuse
itself with the child's completion message and stop mid-workflow. The `Agent` tool with
`subagent_type: general-purpose` is the only reliable fork mechanism for nested delegation; see
`$(cog skill-refs path skills-and-orchestration.md)` (Dispatch vs Delegation).

Pass file paths in the prompt, not inlined file contents: the subagent shares the filesystem and can
read the run-dir artifacts directly. `review-plan-lean` owns the `cog plan-review orchestrator`
scaffold/write/validate mechanics and writes a reviewed plan with `APPROVED` / `MODIFIED` /
`REMOVED` / `ADDED` annotations to the output path specified in the prompt. The parent must not
pre-create or pre-format `stage2-reviewed-plan.md`; it only clears a stale artifact before
delegation and validates proof afterward.

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
  Read the skill file at $HOME/.claude/skills/review-plan-lean/SKILL.md
  and run /review-plan-lean in orchestrator mode. Its three absolute path
  arguments are:

  1. plan-path:   <RUN_DIR>/stage1-plan.md
  2. request-path: <RUN_DIR>/request.md
  3. output-path: <RUN_DIR>/stage2-reviewed-plan.md

  The request path is the Bootstrap task file created before
  Stage 1. Follow review-plan-lean's Orchestrator Invocation Contract:
  review the plan, let review-plan-lean call cog plan-review orchestrator
  for scaffold/write/validate mechanics, and write the final reviewed plan
  verbatim to the output path. Return a one-line confirmation containing the
  output path once the file is written. Do not modify any repository files
  outside the output path.
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
3. If the user requests edits: apply the changes directly, save the updated plan to
   `stage2-reviewed-plan.md`, and return to step 1.
4. If the user approves (`continue`, `approve`, `go`): exit the loop and proceed to stage 3.
5. If the user aborts (`stop`, `abort`): end the workflow immediately. The lock was already released
   before entering the loop.

If the user's intent is ambiguous (e.g., "looks good but change X"), treat it as an edit request —
apply the change and loop back for explicit approval.

After the user approves and before starting stage 3, reacquire the lock:

```bash
cog lock acquire "$RUN_DIR" --owner-pid "$PPID"
```
