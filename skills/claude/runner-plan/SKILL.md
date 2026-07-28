---
name: runner-plan
description: >
  Drive one implementation plan directory's rounds queue to completion. Select
  each runnable rounds: item, dispatch its prompt verbatim to a fresh
  claude-delegate, verify the round is done, commit, run the
  review-queue-rounds boundary, and continue until complete or failed
  closed.
model: opus
effort: low
argument-hint: "[-n|--dry-run] [--max <n>] -ar @<plan-dir>"
disable-model-invocation: true
allowed-tools: Bash Read Agent Skill
---

<!-- trigger-tests: "runner-plan", "run this plan", "execute the plan rounds" -->

# Runner Plan

**Phase 0 — Plan-mode gate.** If Claude Code plan mode is active, STOP before any other work and follow `$(cog skill-refs path orchestration/plan-mode-gate.md)`.

Drive one flat plan directory in the resolved cog plan vault (local or global store), resolved by `cog runner-plan-setup` via `cog plan runner-resolve`. This skill runs inline in its own invocation; it never delegates its rounds loop. Each selected round carries the command to run in its `prompt:` field, and this runner sends that text unchanged to a queue-blind `claude-delegate` subagent.

## Contract

- `runner-plan` consumes only a plan directory containing `queue-rounds.yaml` with `rounds:` schema.
- `cog runner-plan-setup` validates the `-ar @<plan-dir>` target through `cog plan runner-resolve`, which resolves the vault store, asserts flatness, and validates the `rounds` schema; setup emits the resolved `PLAN_ROOT`, `MAIN_QUEUE_PATH`, `PLAN_STORE`, and `PROJECT_KEY` into `ctx.env`.
- The selected round prompt is opaque data. Dispatch it exactly as read from `cog queue-select`.
- The executor prompt owns the round's status flip. After the delegate returns, verify the round is exactly `done`; do not edit the round status in this skill.
- `/gc` is the only commit authority. Parse its captured result with `cog runner-commit-parse`. Human parse output is `COMMIT_SHA=<sha>` or `COMMIT_SHA=<sha> repo=<root>`; JSON output is `{ok, commits[]}`.
- After each committed round, run the `review-queue-rounds` boundary. That boundary performs `cog review-queue-rounds-scan` and `cog review-queue-rounds-verify`.
- `ctx.env` carries `REPO_ROOT`, `PLAN_ROOT`, `MAIN_QUEUE_PATH`, `PLAN_DIR`, `INNER_QUEUE_PATH`, `QUEUE_PATH`, `QUEUE_SCHEMA`, `PLAN_STORE`, `PROJECT_KEY`, `RUN_DIR`, `DRY_RUN`, `MAX_ROUNDS`, and `REPOS`.

Depth budget: `runner-plan` at depth 1 when launched by `runner-all` dispatches an executor at depth 2; executor review subagents run at depth 3, below the fixed cap of 5.

## Usage

```bash
# Local store (in-project vault), or global store (absolute out-of-project vault):
/runner-plan -ar @.cog/plans/plans/<slug>/
/runner-plan -ar @/abs/cog/plans/projects/<project-key>/plans/<slug>/
/runner-plan --max 1 -ar @.cog/plans/plans/<slug>/
/runner-plan --dry-run -ar @.cog/plans/plans/<slug>/
```

`--max N` counts completed and committed rounds. `--dry-run` selects and prints the next round, its verbatim prompt, remaining `todo` rounds, and the planned `/gc -a` flags without dispatching, flipping status, committing, or running revision.

The plan path must not contain whitespace. Arguments are tokenized by word splitting, matching the vault layout convention.

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

4. If `.state` is `complete`, stop successfully. If selection fails or reports blocked work, stop failed closed and report `$RUN_DIR`.
5. For dry-run, print `.selected.item`, `.selected.prompt`, `.todo_remaining`, and planned repo flags, then stop.
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

   When a round is an operator-approval gate, it stays not-`done` until the human approves on a channel the executor can verify, per `$(cog skill-refs path orchestration/approval-gate-contract.md)`. Surface the exact `cog gate approve --round-id <id> --round-path <round-file>` command for the human to run — never relay approval or hand-edit the queue to force the round through.

8. Enforce the round's declared scope before committing. When the selected round declares `scope`, run the scope-guard against the working-tree changeset; a breach means the round rewrote far more than it declared. STOP on breach and report the delta (proceed / split / revert) per Failure Handling:

   ```bash
   . "$RUN_DIR/ctx.env"
   MAX_FILES="$(ITEM="$ITEM" yq e -r '.rounds[] | select(.item == strenv(ITEM)) | .scope.max_files // ""' "$INNER_QUEUE_PATH")"
   MAX_LINES="$(ITEM="$ITEM" yq e -r '.rounds[] | select(.item == strenv(ITEM)) | .scope.max_lines // ""' "$INNER_QUEUE_PATH")"
   if [ -n "$MAX_FILES" ] || [ -n "$MAX_LINES" ]; then
     cog review-scope check ${MAX_FILES:+--max-files "$MAX_FILES"} ${MAX_LINES:+--max-lines "$MAX_LINES"} --json \
       || { echo "SCOPE BREACH for round '$ITEM': staged change exceeds declared scope; stop and report." >&2; exit 1; }
   fi
   ```

   Then commit through a foreground `claude-delegate` running `/gc -a` plus one `--repo <path>` per satellite in `REPOS`. Capture only `COMMIT_*` lines to `$RUN_DIR/commit-$RUN_COUNT.out`, then parse:

   ```bash
   . "$RUN_DIR/ctx.env"
   cog runner-commit-parse "$RUN_DIR/commit-$RUN_COUNT.out" || exit 1
   cog runner-commit-parse "$RUN_DIR/commit-$RUN_COUNT.out" --json
   ```

   A round that changed only queue metadata produces a `COMMIT_OK empty` line; treat it as success, skip the per-repo commit, and proceed to the boundary.

9. Run the revision boundary as a foreground `claude-delegate`. Source `MAIN_QUEUE_PATH` from `ctx.env` (emitted by setup) and re-resolve the vault to prove it is still consistent:

   ```bash
   . "$RUN_DIR/ctx.env"
   RESOLVE_JSON="$(cog plan runner-resolve --target "$PLAN_DIR" --json)" || exit 1
   REVISION_MAIN_QUEUE="$(jq -r '.main_queue' <<<"$RESOLVE_JSON")"
   [ "$REVISION_MAIN_QUEUE" = "$MAIN_QUEUE_PATH" ] || { echo "ERROR: resolver main queue drifted" >&2; exit 1; }
   ```

   Prompt:

   ```text
   Working repo (your cwd): <REPO_ROOT>

   Run the `review-queue-rounds` skill after the committed queue item:

       --repo-root <REPO_ROOT>
       --main-queue <REVISION_MAIN_QUEUE>

   Use RUN_DIR=<RUN_DIR> for scan, verify, and commit-output files. The boundary must run
   `cog review-queue-rounds-scan` before changes and `cog review-queue-rounds-verify`
   after changes, then commit verified drift through /gc in the foreground. Return STATUS: OK with
   both phases reported, using NO_DRIFT for a phase that changed nothing. Return STATUS: FAILED on
   scan, verify, graph-check, or commit failure.
   ```

   Require `STATUS: OK`, proof that `cog review-queue-rounds-verify` passed, and a clean verified postcondition before selecting more work.

   After the boundary, scan for cross-round no-ops. When the round declared `artifacts` or `idempotency_check`, check whether an earlier round already deployed the same artifact so a re-deploy no-op is reported, not silent:

   ```bash
   . "$RUN_DIR/ctx.env"
   cog review-queue-rounds-check-idempotency --queue "$INNER_QUEUE_PATH" --round "$ITEM" --json \
     >"$RUN_DIR/idempotency-$RUN_COUNT.json"
   ```

   For each `already_deployed` entry, record a `NO_OP_ARTIFACT` note on the round and surface it.

10. Increment `RUN_COUNT`, honor `--max N`, and loop.

## Multi-Repo

An inner `queue-rounds.yaml` may declare satellite repos:

```yaml
repos:
  - /abs/path/to/satellite-repo
rounds:
  - item: round-one
    prompt: /executor-prex -ar /abs/plan-root/plans/<plan>/rounds/round-one.md
```

`runner-plan-setup` persists this list as newline-joined `REPOS`. Rebuild `--repo <path>` flags from that value for clean-tree checks and `/gc -a` commits.

## Failure Handling

Stop immediately on setup failure, invalid queue data, duplicate items, existing `doing`, dirty worktree, blocked dependencies, delegate failure, a round not verified as `done`, missing or failed `COMMIT_*`, or revision failure. An intentional `--max` stop is normal and reports remaining work. Dry-run never dispatches, flips status, commits, or runs revision.
