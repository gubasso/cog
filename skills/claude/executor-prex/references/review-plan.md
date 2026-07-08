## Stage 2: Review Plan

Vet the drafted plan with `review-plan-oneshot` via the **Agent tool** (`subagent_type:
general-purpose`), not the Skill tool — see `$(cog skill-refs path skills-and-orchestration.md)`
(Dispatch vs Delegation). The reviewer runs as a fresh-context subagent, so its input is the validated
context brief `$RUN_DIR/context-brief.md` plus the three absolute paths its invocation contract expects:

1. `<plan-path-abs>` — the drafted plan `$RUN_DIR/draft-plan.md`.
2. `<request-path-abs>` — the request `$RUN_DIR/request.md`.
3. `<output-path-abs>` — the reviewed plan `$RUN_DIR/vetted-plan.md`.

Instruct the subagent to reply with exactly `WROTE $RUN_DIR/vetted-plan.md` on success. The reviewer
annotates and reconciles the drafted plan (APPROVED/MODIFIED/ADDED/REMOVED) and writes the vetted,
authoritative plan to `$RUN_DIR/vetted-plan.md`; the implementation stage applies that reconciliation.

Validate the delegation proof before trusting the result — the artifact must exist and be non-empty —
then release the workflow lock before pausing for approval:

```bash
[ -s "$RUN_DIR/vetted-plan.md" ] || { echo "ERROR: vetted-plan.md is empty" >&2; cog lock release "$LOCK_FILE"; exit 1; }
cog lock release "$LOCK_FILE"
```

### Approval Loop

After saving the vetted plan and releasing the lock:

- If the mode is `auto-approve` or `auto-approve-review-loop`, display the **complete** vetted plan to
  the user verbatim, show the file path to `vetted-plan.md`, and treat the plan as approved
  without waiting for user input. After displaying the plan, reacquire the lock and proceed directly
  to the implementation stage.
- Otherwise, enter the approval loop below.

This approval loop repeats until the user explicitly approves or aborts:

1. Display the **complete** vetted plan to the user verbatim — do not summarize, truncate, or collapse
   sections. The user must be able to read every step on screen before being asked to approve. Also
   show the file path to `vetted-plan.md` so the user can reference it.
2. Wait for explicit user input: approval, modification requests, or abort.
3. If the user requests edits: apply the changes directly, save the updated plan to
   `vetted-plan.md`, and return to step 1.
4. If the user approves (`continue`, `approve`, `go`): exit the loop and proceed to the implementation
   stage.
5. If the user aborts (`stop`, `abort`): end the workflow immediately. The lock was already released
   before entering the loop.

If the user's intent is ambiguous (e.g., "looks good but change X"), treat it as an edit request —
apply the change and loop back for explicit approval.

After the user approves and before starting the implementation stage, reacquire the lock:

```bash
cog lock acquire "$RUN_DIR" --owner-pid "$PPID"
```
