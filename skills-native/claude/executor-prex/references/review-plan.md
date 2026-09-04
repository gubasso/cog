<!-- markdownlint-disable-file MD041 -->

## Stage 2: Review Plan

Vet the drafted plan with `review-plan-oneshot` via the **Agent tool** (`subagent_type:
general-purpose`), not the Skill tool — see `$(cog skill-refs path skills-and-orchestration.md)` (Dispatch vs Delegation). The reviewer runs as a fresh-context subagent, so its input is the validated context brief `$RUN_DIR/context-brief.md` plus the three absolute paths its invocation contract expects:

1. `<plan-path-abs>` — the drafted plan `$RUN_DIR/draft-plan.md`.
2. `<request-path-abs>` — the request `$RUN_DIR/request.md`.
3. `<output-path-abs>` — the annotated review `$RUN_DIR/plan-review.md`.

Instruct the subagent to reply with exactly `WROTE $RUN_DIR/plan-review.md` on success. Reviews remain reviews; the parent owns the fold.

Validate the review, then follow `$(cog skill-refs path plan-quality/plan-review-fold.md)` in the parent context with `draft-plan.md` as the base and `vetted-plan.md` as the target. Retain `vetted-plan-review-items.json`, `vetted-plan-fold-manifest.json`, and `vetted-plan-fold-check.json`. Only after review validation, plan-doc validation, and successful fold-check may the workflow release the lock for approval:

```bash
cog plan-review validate "$RUN_DIR/plan-review.md" || { cog lock release "$LOCK_FILE"; exit 1; }
# Follow the shared fold protocol here; author the folded plan and manifest.
cog plan-doc validate "$RUN_DIR/vetted-plan.md" || { cog lock release "$LOCK_FILE"; exit 1; }
cog plan-review fold-check --review "$RUN_DIR/plan-review.md" --plan "$RUN_DIR/vetted-plan.md" --manifest "$RUN_DIR/vetted-plan-fold-manifest.json" --json >"$RUN_DIR/vetted-plan-fold-check.json" || { cog lock release "$LOCK_FILE"; exit 1; }
cog lock release "$LOCK_FILE"
```

### Approval Loop

After saving the vetted plan and releasing the lock:

- If the mode is `auto-approve` or `auto-approve-review-loop`, display the **complete** vetted plan to the user verbatim, show the file path to `vetted-plan.md`, and treat the plan as approved without waiting for user input. After displaying the plan, reacquire the lock and proceed directly to the implementation stage.
- Otherwise, enter the approval loop below.

This approval loop repeats until the user explicitly approves or aborts:

1. Display the **complete** vetted plan to the user verbatim — do not summarize, truncate, or collapse sections. The user must be able to read every step on screen before being asked to approve. Also show the file path to `vetted-plan.md` so the user can reference it.
2. Wait for explicit user input: approval, modification requests, or abort.
3. If the user requests edits: apply the changes directly and save `vetted-plan.md`. Update the manifest first if the edit changes a disposition, then rerun `cog plan-doc validate` and `cog plan-review fold-check ... --json >"$RUN_DIR/vetted-plan-fold-check.json"` so the receipt hashes the current plan. On failure, keep the lock released and stop. Return to step 1 only after both gates pass.
4. If the user approves (`continue`, `approve`, `go`): exit the loop and proceed to the implementation stage.
5. If the user aborts (`stop`, `abort`): end the workflow immediately. The lock was already released before entering the loop.

If the user's intent is ambiguous (e.g., "looks good but change X"), treat it as an edit request — apply the change and loop back for explicit approval.

After the user approves and before starting the implementation stage, reacquire the lock:

```bash
cog lock acquire "$RUN_DIR" --owner-pid "$PPID"
```
