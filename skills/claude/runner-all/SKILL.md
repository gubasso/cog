---
name: runner-all
description: >
  Drive a top-level implementation plans queue to completion. Select each
  runnable plans: item, dispatch its prompt verbatim to a fresh claude-delegate,
  reconcile the main item to done, commit, run the review-plan-implementation
  boundary, and continue until complete or failed closed.
model: opus
effort: low
argument-hint: "[-n|--dry-run] [--max <n>] <queue-plans.yaml>"
disable-model-invocation: true
allowed-tools: Bash Read Agent Skill
---

<!-- trigger-tests: "runner-all", "run all plans", "run the plan queue" -->

# Runner All

<!-- cog-plan-mode-gate -->

**Phase 0 — Plan-mode gate.** If Claude Code **plan mode** is active (a system-reminder says plan
mode is on / that you must not make edits), **STOP** before any other work — parsing args,
researching, interviewing, delegating, or writing. Tell the user in one line to exit plan mode
(`Shift+Tab`) and re-invoke `/runner-all`. Do not call `ExitPlanMode`, and do not silently continue.

Drive a `.implementation-plans/queue-plans.yaml` `plans:` queue. This skill runs inline in the
orchestrating session; it never delegates the main loop. Each selected main item carries the command
to run in its `prompt:` field, and this runner sends that text unchanged to a queue-blind
`claude-delegate` subagent.

## Contract

- `runner-all` consumes only the structural `plans:` queue contract.
- The selected item prompt is opaque data. Dispatch it exactly as read from `cog queue-select`.
- The delegated subagent owns the selected prompt. For current plan queues that prompt is normally
  `/runner-plan -ar @.implementation-plans/plans/<slug>/`.
- Main-plan `done` is plan-owned and runner-reconciled: after the delegate returns, ensure the main
  item is `done` with `cog queue-status-set --schema plans --from todo --to done --idempotent`.
- `/gc` is the only commit authority. Parse its captured result with `cog runner-commit-parse`.
  Human parse output is `COMMIT_SHA=<sha>` or `COMMIT_SHA=<sha> repo=<root>`; JSON output is
  `{ok, commits[]}`.
- After each committed main item, run the project-local `review-plan-implementation` boundary. That
  boundary performs `cog review-plan-implementation-scan` and `cog review-plan-implementation-verify`.

Depth budget: `runner-all` at depth 0 dispatches `runner-plan` at depth 1; `runner-plan` dispatches
an executor at depth 2; executor review subagents run at depth 3, below the fixed cap of 5.

## Usage

```bash
/runner-all .implementation-plans/queue-plans.yaml
/runner-all --max 1 .implementation-plans/queue-plans.yaml
/runner-all --dry-run .implementation-plans/queue-plans.yaml
```

`--max N` counts completed and committed main plans. `--dry-run` selects and prints the next main
item, its verbatim prompt, remaining `todo` plans, and the planned `/gc -a` step without dispatching,
flipping status, committing, or running revision.

The queue path must not contain whitespace. Arguments are tokenized by word splitting, matching the
`.implementation-plans/` layout convention.

## Algorithm

1. Parse only `-n|--dry-run`, `--max N` or `--max=N`, and one `queue-plans.yaml` path.
2. Run setup and source the durable context:

   ```bash
   RUN_DIR="$(cog runner-all-setup "${ARGUMENTS:-}" | sed -n 's/^RUN_DIR=//p')"
   [ -n "$RUN_DIR" ] || { echo "ERROR: runner-all-setup did not emit RUN_DIR" >&2; exit 1; }
   . "$RUN_DIR/ctx.env"
   ```

3. Select the next main item each loop:

   ```bash
   . "$RUN_DIR/ctx.env"
   : "${RUN_COUNT:=0}"
   REPO_FLAGS=()
   while IFS= read -r r; do [[ -n "$r" ]] && REPO_FLAGS+=(--repo "$r"); done <<<"$REPOS"
   cog queue-select --schema plans --queue "$MAIN_QUEUE_PATH" --repo-root "$REPO_ROOT" \
     "${REPO_FLAGS[@]}" "$RUN_DIR/main-select-$RUN_COUNT.json" \
     || { echo "ERROR: queue-select failed; see $RUN_DIR/main-select-$RUN_COUNT.json" >&2; exit 1; }
   ```

4. If `.state` is `complete`, stop successfully. If selection fails or reports blocked work, stop
   failed closed and report `$RUN_DIR`.
5. For dry-run, print `.selected.item`, `.selected.prompt`, and `.todo_remaining`, then stop.
6. Dispatch the selected prompt through a foreground Agent call:

   - `subagent_type`: `claude-delegate`
   - `description`: `Run plan <ITEM>`
   - `prompt`:

     ```text
     Working repo (your cwd): <REPO_ROOT>

     Run this queued main-plan prompt to completion, exactly as written:

         <PROMPT>

     Run the queued prompt exactly as written; its slash command selects the nested runner. Run every
     Codex call in the foreground. Return your structured result.
     ```

   A malformed or non-runnable prompt fails inside the delegate. In that case the main item will not
   reconcile to `done`; stop and surface the delegate result plus `$RUN_DIR`.

7. Reconcile the selected main item:

   ```bash
   . "$RUN_DIR/ctx.env"
   : "${RUN_COUNT:=0}"
   PLAN_ITEM="$(jq -r '.selected.item' "$RUN_DIR/main-select-$RUN_COUNT.json")"
   cog queue-status-set --queue "$MAIN_QUEUE_PATH" --schema plans --item "$PLAN_ITEM" \
     --from todo --to done --idempotent "$RUN_DIR/main-status-$RUN_COUNT.json"
   jq -e '.ok and .status_after == "done"' "$RUN_DIR/main-status-$RUN_COUNT.json" >/dev/null \
     || { echo "ERROR: main plan '$PLAN_ITEM' not reconciled to done" >&2; exit 1; }
   ```

8. Commit through a foreground `claude-delegate` running `/gc -a`, capture only `COMMIT_*` lines to
   `$RUN_DIR/commit-$RUN_COUNT.out`, and parse:

   ```bash
   . "$RUN_DIR/ctx.env"
   cog runner-commit-parse "$RUN_DIR/commit-$RUN_COUNT.out" || exit 1
   cog runner-commit-parse "$RUN_DIR/commit-$RUN_COUNT.out" --json
   ```

9. Run the revision boundary as a foreground `claude-delegate`:

   ```text
   Working repo (your cwd): <REPO_ROOT>

   Run the project-local `review-plan-implementation` skill after the committed queue item:

       --repo-root <REPO_ROOT>
       --main-queue <MAIN_QUEUE_PATH>

   Use RUN_DIR=<RUN_DIR> for scan, verify, and commit-output files. The boundary must run
   `cog review-plan-implementation-scan` before changes and `cog review-plan-implementation-verify`
   after changes, then commit verified drift through /gc in the foreground. Return STATUS: OK with
   both phases reported, using NO_DRIFT for a phase that changed nothing. Return STATUS: FAILED on
   scan, verify, graph-check, or commit failure.
   ```

   Require `STATUS: OK`, proof that `cog review-plan-implementation-verify` passed, and a clean
   verified postcondition before selecting more work.

10. Increment `RUN_COUNT`, honor `--max N`, and loop.

## Multi-Repo

If the main queue carries a top-level `repos:` list, `runner-all-setup` persists it as newline-joined
`REPOS`. Rebuild `--repo <path>` flags from that value whenever shelling out. Commit steps normally
commit `REPO_ROOT`; nested `runner-plan` commits plan satellite repos from each inner queue.

## Failure Handling

Stop immediately on setup failure, invalid queue data, duplicate items, existing `doing`, dirty
worktree, blocked dependencies, delegate failure, reconcile failure, missing or failed `COMMIT_*`,
or revision failure. An intentional `--max` stop is normal and reports remaining work. Dry-run never
dispatches, flips status, commits, or runs revision.
