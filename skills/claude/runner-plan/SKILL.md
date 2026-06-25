---
name: runner-plan
description: >
  Drive one implementation plan directory's rounds queue to completion. Select
  each runnable rounds: item, dispatch its prompt verbatim to a fresh
  claude-delegate, verify the round is done, commit, run the
  review-plan-implementation boundary, and continue until complete or failed
  closed.
argument-hint: "[-n|--dry-run] [--max <n>] -ar @<plan-dir>"
disable-model-invocation: true
allowed-tools: Bash Read Agent Skill
---

<!-- trigger-tests: "runner-plan", "run this plan", "execute the plan rounds" -->

# Runner Plan

<!-- cog-plan-mode-gate -->

**Phase 0 — Plan-mode gate.** If Claude Code **plan mode** is active (a system-reminder says plan
mode is on / that you must not make edits), **STOP** before any other work — parsing args,
researching, interviewing, delegating, or writing. Tell the user in one line to exit plan mode
(`Shift+Tab`) and re-invoke `/runner-plan`. Do not call `ExitPlanMode`, and do not silently continue.

Drive one flat plan directory under `.implementation-plans/plans/`. This skill runs inline in its
own invocation; it never delegates its rounds loop. Each selected round carries the command to run in
its `prompt:` field, and this runner sends that text unchanged to a queue-blind `claude-delegate`
subagent.

## Contract

- `runner-plan` consumes only a plan directory containing `queue-rounds.yaml` with `rounds:` schema.
- `cog runner-plan-setup` validates the `-ar @<plan-dir>` target with
  `cog::fn::review_plan_implementation_assert_flat` and `cog::fn::queue_validate_file`.
- The selected round prompt is opaque data. Dispatch it exactly as read from `cog queue-select`.
- The executor prompt owns the round's status flip. After the delegate returns, verify the round is
  exactly `done`; do not edit the round status in this skill.
- `/gc` is the only commit authority. Parse its captured result with `cog runner-commit-parse`.
  Human parse output is `COMMIT_SHA=<sha>` or `COMMIT_SHA=<sha> repo=<root>`; JSON output is
  `{ok, commits[]}`.
- After each committed round, run the project-local `review-plan-implementation` boundary. That
  boundary performs `cog review-plan-implementation-scan` and `cog review-plan-implementation-verify`.

Depth budget: `runner-plan` at depth 1 when launched by `runner-all` dispatches an executor at depth
2; executor review subagents run at depth 3, below the fixed cap of 5.

## Usage

```bash
/runner-plan -ar @.implementation-plans/plans/<slug>/
/runner-plan --max 1 -ar @.implementation-plans/plans/<slug>/
/runner-plan --dry-run -ar @.implementation-plans/plans/<slug>/
```

`--max N` counts completed and committed rounds. `--dry-run` selects and prints the next round, its
verbatim prompt, remaining `todo` rounds, and the planned `/gc -a` flags without dispatching,
flipping status, committing, or running revision.

The plan path must not contain whitespace. Arguments are tokenized by word splitting, matching the
`.implementation-plans/` layout convention.

## Algorithm

1. Parse only `-n|--dry-run`, `--max N` or `--max=N`, and `-ar @<plan-dir>`.
2. Run setup and source the durable context:

   ```bash
   RUN_DIR="$(cog runner-plan-setup "${ARGUMENTS:-}" | sed -n 's/^RUN_DIR=//p')"
   [ -n "$RUN_DIR" ] || { echo "ERROR: runner-plan-setup did not emit RUN_DIR" >&2; exit 1; }
   . "$RUN_DIR/ctx.env"
   ```

3. Select the next round each loop:

   ```bash
   . "$RUN_DIR/ctx.env"
   : "${RUN_COUNT:=0}"
   REPO_FLAGS=()
   while IFS= read -r r; do [[ -n "$r" ]] && REPO_FLAGS+=(--repo "$r"); done <<<"$REPOS"
   cog queue-select --schema rounds --queue "$INNER_QUEUE_PATH" --repo-root "$REPO_ROOT" \
     "${REPO_FLAGS[@]}" "$RUN_DIR/round-select-$RUN_COUNT.json" \
     || { echo "ERROR: queue-select failed; see $RUN_DIR/round-select-$RUN_COUNT.json" >&2; exit 1; }
   ```

4. If `.state` is `complete`, stop successfully. If selection fails or reports blocked work, stop
   failed closed and report `$RUN_DIR`.
5. For dry-run, print `.selected.item`, `.selected.prompt`, `.todo_remaining`, and planned repo
   flags, then stop.
6. Dispatch the selected prompt through a foreground Agent call:

   - `subagent_type`: `claude-delegate`
   - `description`: `Run round <ITEM>`
   - `prompt`:

     ```text
     Working repo (your cwd): <REPO_ROOT>

     Run this queued implementation round to completion, exactly as written:

         <PROMPT>

     Run the queued prompt exactly as written; its slash command selects the executor. Run every
     Codex call in the foreground. The round is complete only when the plan is fully implemented and
     reviewed AND this round's status is flipped to `done` in queue-rounds.yaml per the plan's final
     step. Return your structured result.
     ```

7. Verify the round status after the delegate returns:

   ```bash
   . "$RUN_DIR/ctx.env"
   : "${RUN_COUNT:=0}"
   ITEM="$(jq -r '.selected.item' "$RUN_DIR/round-select-$RUN_COUNT.json")"
   [ -n "$ITEM" ] && [ "$ITEM" != null ] || { echo "ERROR: no selected item" >&2; exit 1; }
   ROUND_STATUS="$(ITEM="$ITEM" yq e -r '.rounds[] | select(.item == strenv(ITEM)) | .status' "$INNER_QUEUE_PATH")"
   if [ "$ROUND_STATUS" != "done" ]; then
     echo "ERROR: round '$ITEM' is '$ROUND_STATUS', not 'done'; delegate did not complete it." >&2
     echo "See the claude-delegate result returned above and inspect: $RUN_DIR" >&2
     exit 1
   fi
   ```

8. Commit through a foreground `claude-delegate` running `/gc -a` plus one `--repo <path>` per
   satellite in `REPOS`. Capture only `COMMIT_*` lines to `$RUN_DIR/commit-$RUN_COUNT.out`, then
   parse:

   ```bash
   . "$RUN_DIR/ctx.env"
   cog runner-commit-parse "$RUN_DIR/commit-$RUN_COUNT.out" || exit 1
   cog runner-commit-parse "$RUN_DIR/commit-$RUN_COUNT.out" --json
   ```

9. Run the revision boundary as a foreground `claude-delegate`. Resolve the canonical main queue at
   revision time; do not persist a parent main-queue path in setup:

   ```bash
   . "$RUN_DIR/ctx.env"
   REVISION_MAIN_QUEUE="$REPO_ROOT/.implementation-plans/queue-plans.yaml"
   [ -f "$REVISION_MAIN_QUEUE" ] || { echo "ERROR: revision main queue not found: $REVISION_MAIN_QUEUE" >&2; exit 1; }
   ```

   Prompt:

   ```text
   Working repo (your cwd): <REPO_ROOT>

   Run the project-local `review-plan-implementation` skill after the committed queue item:

       --repo-root <REPO_ROOT>
       --main-queue <REVISION_MAIN_QUEUE>

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

An inner `queue-rounds.yaml` may declare satellite repos:

```yaml
repos:
  - /abs/path/to/satellite-repo
rounds:
  - item: round-one
    prompt: /executor-prex -ar .implementation-plans/plans/<plan>/round-one.md
```

`runner-plan-setup` persists this list as newline-joined `REPOS`. Rebuild `--repo <path>` flags from
that value for clean-tree checks and `/gc -a` commits.

## Failure Handling

Stop immediately on setup failure, invalid queue data, duplicate items, existing `doing`, dirty
worktree, blocked dependencies, delegate failure, a round not verified as `done`, missing or failed
`COMMIT_*`, or revision failure. An intentional `--max` stop is normal and reports remaining work.
Dry-run never dispatches, flips status, commits, or runs revision.
