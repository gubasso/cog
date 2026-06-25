## Stage 1-2: Vetted Plan

Produce the vetted plan by inline-chaining `plan-vetted` in the current context: read the skill at
`$HOME/.claude/skills/plan-vetted/SKILL.md` and follow it. `plan-vetted` owns the input-quality gate
and the dual-engine producer selection (generate when thin, multi-review when already detailed); the
parent only supplies the input and the output path, then runs the approval loop.

Pass the task as an enrichment-only superset of the original request — verbatim and in full, plus
relevant repo constraints — and the output path `$RUN_DIR/stage2-reviewed-plan.md`. Do not pre-create
or pre-format the artifact; `plan-vetted` writes the vetted plan there and returns the output path and
the route.

`plan-vetted`'s producers (`plan-multi`, `review-plan-multi`) run as fresh-context Agent-tool
subagents inside it, so the heavy planning work stays isolated while the parent keeps sequencing the
workflow. A `good-input` route yields an annotated review of the supplied plan
(APPROVED/MODIFIED/ADDED/REMOVED); the implementation stage applies that reconciliation.

After the vetted plan is written, verify the artifact and release the workflow lock before pausing for
approval:

```bash
[ -s "$RUN_DIR/stage2-reviewed-plan.md" ] || { echo "ERROR: stage2-reviewed-plan.md is empty" >&2; cog lock release "$LOCK_FILE"; exit 1; }
cog lock release "$LOCK_FILE"
```

### Approval Loop

After saving the vetted plan and releasing the lock:

- If the mode is `auto-approve` or `auto-approve-review-loop`, display the **complete** vetted plan to
  the user verbatim, show the file path to `stage2-reviewed-plan.md`, and treat the plan as approved
  without waiting for user input. After displaying the plan, reacquire the lock and proceed directly
  to stage 3.
- Otherwise, enter the approval loop below.

This approval loop repeats until the user explicitly approves or aborts:

1. Display the **complete** vetted plan to the user verbatim — do not summarize, truncate, or collapse
   sections. The user must be able to read every step on screen before being asked to approve. Also
   show the file path to `stage2-reviewed-plan.md` so the user can reference it.
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
