# Orchestration Patterns

Reusable patterns for multi-stage workflows that orchestrate Codex via `codex-session`. These patterns appear across `executor-prex` and `review-loop`.

Skills implement these patterns using their own variable names and stage numbers. This file defines the **contracts and shapes** — not the orchestration logic itself.

## Sandbox Detection Probe

Before the first Codex call in a workflow, determine whether the native bwrap sandbox works. The sandbox probe and fallback are owned by `cog codex-runner`: `cog codex-runner gate sandbox` resolves availability, health, and sandbox mode in one call. Skills consume that surface rather than reimplementing the probe.

- Run once per workflow, not per stage.
- Persist `SANDBOX_MODE` by substituting its literal value in subsequent commands (shell state does not persist between Bash tool invocations).
- Use the Bash tool timeout of `30000ms` for the probe.
- If fallback: inform the user in one line.

## Inline by Default, Fork on a Real Boundary

Every pattern below crosses into a fresh context. This one decides whether to cross at all.

Run a producer in the caller's own context by default. The session already holds the request, the research, and the decisions; a fresh context must re-derive them from a brief that can only ever be a lossy re-encoding of what the caller already has. Inline is cheaper, faster, and better informed.

Cross into a fresh context when the crossing buys something concrete:

- **A different engine.** Cross-engine review is independence by construction; a Claude session cannot get a Codex opinion in-session.
- **Real parallelism.** N independent units of the same work run concurrently only as N workers (§Homogeneous Parallel Fan-Out).
- **Deliberate bias isolation.** When the worker must not see the coordinator's verdict, the fork _is_ the mechanism — the coordinator withholds its conclusion, and only a context that never saw it can form an independent one.

Two shipped examples anchor the rule. `gc` commits inline for a single repo and fans out one worker per repo only when the session touched more than one. `plan-vetted` dispatches its multi-review through the Agent tool even though both sides are Claude, because the isolation is the point.

The judgment is the caller's and lives in skill prose. It is not a lookup: the same producer runs inline on one host and forked on another, and no `(executor, engine, route)` key can express a fork chosen for independence rather than for engine mismatch.

## Proof-of-Delegation

When delegating work to a subagent via the **Agent tool** (`subagent_type: general-purpose`), wrap the delegation in a snapshot/diff/validate pattern to confirm the subagent actually did the work.

### Contract

1. **Pre-snapshot** — capture the run directory state before delegation:

   ```bash
   find "$RUN_DIR" -type f -printf '%p %T@\n' 2>/dev/null | sort > "$RUN_DIR/<STAGE>-pre.snap"
   rm -f "$RUN_DIR/<PROOF_DIFF>" "$RUN_DIR/<OUTPUT_FILE>"
   ```

2. **Delegate** — invoke the Agent tool (never the Skill tool for nested delegation; see [Skills and Orchestration §Dispatch vs Delegation](../skills-and-orchestration.md#dispatch-vs-delegation).

3. **Post-snapshot and diff** — capture the state after delegation returns:

   ```bash
   find "$RUN_DIR" -type f -printf '%p %T@\n' 2>/dev/null | sort > "$RUN_DIR/<STAGE>-post.snap"
   diff -u "$RUN_DIR/<STAGE>-pre.snap" "$RUN_DIR/<STAGE>-post.snap" \
     > "$RUN_DIR/<PROOF_DIFF>" || true
   ```

4. **Validate** — fail closed on missing evidence:

   ```bash
   [ -s "$RUN_DIR/<OUTPUT_FILE>" ] || {
     echo "ERROR: delegated work did not produce $RUN_DIR/<OUTPUT_FILE>"
     exit 1
   }
   [ -s "$RUN_DIR/<PROOF_DIFF>" ] || {
     echo "ERROR: no proof of delegated activity in $RUN_DIR"
     exit 1
   }
   ```

### Rules

- Do not retry automatically on proof failure. Report the error and ask the user.
- Do not fall back to inline work if delegation fails — the point is separation of concerns.
- The proof diff serves as an audit trail: it shows which files the subagent created or modified.

### Variant: External directory proof

For delegations that create artifacts outside `$RUN_DIR` (e.g., `review-loop` creates `/tmp/review-loop-*`), use the same pattern but snapshot the external directory:

```bash
find /tmp -maxdepth 1 -type d -name '<PATTERN>-*' -printf '%p\n' 2>/dev/null \
  | sort > "$RUN_DIR/<STAGE>-pre.snap"
# ... delegate ...
find /tmp -maxdepth 1 -type d -name '<PATTERN>-*' -printf '%p\n' 2>/dev/null \
  | sort > "$RUN_DIR/<STAGE>-post.snap"
diff -u ... > "$RUN_DIR/<PROOF_DIFF>" || true
NEW_DIR="$(comm -13 "$RUN_DIR/<STAGE>-pre.snap" "$RUN_DIR/<STAGE>-post.snap" | tail -1)"
```

## Homogeneous Parallel Fan-Out

When a coordinator has N independent units of the **same** work — one per repo, one per file, one per shard — dispatch one identical Agent subagent per unit **concurrently** rather than looping over them sequentially. The concurrency mechanism is issuing all N Agent tool calls in a single assistant message; each worker owns a disjoint durable artifact so there is no cross-worker contention. This generalizes the two-way heterogeneous fan-out (one Claude Agent + one Codex job) to N homogeneous Agent subagents.

### Contract

1. **Partition** — the coordinator computes the unit set once (e.g. `cog gc-plan` partitions session files by owning repo) and gives each unit its own scratch subdirectory under the run directory and its own single result-line file:

   ```text
   $RUN_DIR/<unit-slug>/            # slug must be collision-free (e.g. basename + short hash)
   $RUN_DIR/<unit-slug>/result-line.txt
   ```

2. **Pre-snapshot** — capture run-directory state and clear stale per-unit result/proof files:

   ```bash
   find "$RUN_DIR" -type f -printf '%p %T@\n' 2>/dev/null | sort > "$RUN_DIR/<STAGE>-pre.snap"
   ```

3. **Dispatch (parallel)** — in ONE assistant message, issue one Agent call per unit (`subagent_type: general-purpose`, never the Skill tool). Each prompt points the worker at its skill file and passes that unit's literal arguments (its scratch dir, its result-line file, and any per-unit flag). All calls go in the single message so they run concurrently.

4. **Post-snapshot, diff, and validate** — after all workers return, snapshot again, diff, and fail closed on missing evidence, per unit:

   ```bash
   find "$RUN_DIR" -type f -printf '%p %T@\n' 2>/dev/null | sort > "$RUN_DIR/<STAGE>-post.snap"
   diff -u "$RUN_DIR/<STAGE>-pre.snap" "$RUN_DIR/<STAGE>-post.snap" > "$RUN_DIR/<PROOF_DIFF>" || true
   ```

   For every unit, fail closed if its `result-line.txt` is missing or empty, or if `<PROOF_DIFF>` is empty. Do not auto-retry; do not fall back to inline work.

5. **Aggregate** — concatenate the per-unit result-line files into one file and parse with a fail-closed aggregator that rejects any failure line:

   ```bash
   cat "$RUN_DIR"/*/result-line.txt > "$RUN_DIR/<RESULTS>"
   # commit fan-out: cog gc-commit-parse "$RUN_DIR/<RESULTS>" --json  (fails closed on any *_FAILED)
   ```

### Rules

- Each worker owns a disjoint artifact; slugs must be collision-free (a shared basename across units is not enough — append a short hash of a unique key).
- Sibling workers share one depth level; each may independently spawn its own nested worker within the fixed 5-level cap.
- Require env-first no-backgrounding (`CLAUDE_CODE_DISABLE_BACKGROUND_TASKS=1`) before dispatch; never shell-background the Agent calls.
- A worker in fresh context cannot ask the user — it fails closed on any unresolved condition, and the coordinator surfaces the failed units after aggregation.

## Lock File Management

Multi-stage workflows use lock files to prevent concurrent sessions from interfering.

### Contract

- **Location**: `${XDG_RUNTIME_DIR:-/tmp}/`
- **Naming**: `<workflow>-active-<suffix>` where suffix is derived from the run directory (basename suffix or SHA1 hash of the realpath).
- **Contents**: two lines — the `$RUN_DIR` path and the owning PID (`$PPID`).
- **Creation**: atomic via write-to-tmp + `mv`.

  ```bash
  printf '%s\n%s\n' "$RUN_DIR" "$PPID" > "${LOCK_FILE}.tmp" \
    && mv "${LOCK_FILE}.tmp" "$LOCK_FILE"
  ```

- **Release**: `rm -f "$LOCK_FILE"` before any user-facing pause (approval loops, user questions).
- **Reacquisition**: recreate the lock before resuming execution after user approval.
- **Orphan detection**: a Stop hook or coordinator checks whether the owning PID is still alive. If the PID is dead or the `$RUN_DIR` no longer exists, the lock is stale and can be cleaned up.

## Review-Loop Handoff

When a workflow hands off to the `review-loop` skill for iterative Codex review + Claude fix cycles, it constructs a JSON file and delegates via the Agent tool.

### Handoff JSON schema

```json
{
  "task": "<contents of request.md>",
  "reviewed_plan": "<contents of vetted-plan.md>",
  "implementation_review": "<contents of review.md>",
  "plan_thread_id": "<PLAN_THREAD_ID or null>",
  "impl_thread_id": "<IMPL_THREAD_ID or null>"
}
```

Write the JSON to `$RUN_DIR/review_loop_input.json`. The review-loop skill parses this for task context, the reviewed plan, and prior findings, then captures the live git diff independently.

`reviewed_plan` is always the folded, structurally validated contents of `vetted-plan.md`; an annotated plan review is never valid in this field.

### Delegation prompt template

```text
Read the skill file at $HOME/.claude/skills/review-loop/SKILL.md and follow
its "handoff mode". Your single argument is:

  <RUN_DIR>/review_loop_input.json

Run the full review loop the skill describes, write the final summary.md to
the review-loop run directory the skill creates, and return a one-line reply
containing that run directory path.
```

Use `subagent_type: general-purpose` (not the Skill tool). Wrap the delegation in the proof-of-delegation pattern (§Proof-of-Delegation, external directory variant) using `/tmp/review-loop-*` as the pattern.

### Validation

After delegation, locate the child run directory and validate:

- `$RL_RUN_DIR/summary.md` exists and is non-empty.
- The proof diff shows a new `/tmp/review-loop-*` directory was created.

Fail closed on missing proof. Do not retry automatically.
