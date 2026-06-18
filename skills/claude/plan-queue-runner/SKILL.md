---
name: plan-queue-runner
description: >
  Drive a plan-writer multi-round implementation plan directory to completion
  from its QUEUE.yaml. Use when the user asks to "run the queue", "run the
  plan queue", "execute the plan rounds", "drive the plan directory", or
  invokes "plan-queue-runner". Dispatches each queued /prex round to a fresh
  claude-delegate subagent, verifies QUEUE.yaml reached done, commits with
  /gc -y -a across every repo the round touched, and loops until complete or
  failed closed.
argument-hint: "[-n|--dry-run] [--max <n>] <plan-dir-or-queue-path>"
disable-model-invocation: true
allowed-tools: Bash Read Agent Skill
---

<!-- trigger-tests: "plan-queue-runner", "run the queue", "run the plan queue", "execute the plan rounds", "drive the plan directory" -->

# Plan Queue Runner

Drive a plan-writer directory plan to completion from its `QUEUE.yaml`. For each runnable `todo`
round, dispatch that round's exact `prompt` to a fresh `claude-delegate` subagent, verify the round
flipped itself to `done`, commit with `/gc -y -a`, and continue until the queue drains or a failure
stops the run.

This skill runs **inline** in the orchestrating session. Dispatch each round to the `claude-delegate`
subagent via the **Agent tool** (foreground, blocking). Nested subagents (Claude Code ≥ v2.1.172)
let `/prex` spawn its own review-stage subagents from within the delegate, so `/prex` no longer needs
its own top-level process. The old requirement to run each round in a separate headless `claude -p`
process is **obsolete and removed** — see
[`$DOCS_NOTES_REPO/tech/tools/claude-code/orchestration/in-session-vs-headless-delegation.md`](file:///$DOCS_NOTES_REPO/tech/tools/claude-code/orchestration/in-session-vs-headless-delegation.md).

A foreground Agent call blocks the orchestrator until the delegate's entire agentic loop completes
and returns, so the _outer_ per-round process reap is gone. The delegate's **own** Codex Bash calls,
one level down, could still be backgrounded or run under too short a timeout — that is now prevented
deterministically by the `cog hook-guard codex-foreground` `PreToolUse(Bash)` hook, which fires
inside subagents too and blocks any backgrounded or sub-`600000ms` Codex call before it runs.
Multi-level round completion is independently guaranteed by the QUEUE-status check below: after the
delegate returns, this runner re-reads `QUEUE.yaml` and fails closed unless the round is `done`.

## Multi-Repo Plans

A plan may write into more than one git repo: the repo holding `QUEUE.yaml` (`REPO_ROOT`, where the
status flips live) plus one or more **satellite** repos the rounds implement into. Declare satellites
in an optional top-level `repos:` list in the inner `QUEUE.yaml`, before `rounds:`:

```yaml
repos:
  - /abs/path/to/satellite-repo
rounds:
  - item: round-one
    status: todo
    depends_on: []
    prompt: "/prex -ar .implementation-plans/plans/<plan>/round-one.md"
    notes: ""
```

When present, the clean-tree guard covers every declared repo and the commit step runs
`/gc -y -a --repo <sat>...` so `/gc` commits both the `QUEUE.yaml` flip in `REPO_ROOT` and the
round's artifacts in satellites. `plan-queue-runner-setup` persists satellites to `ctx.env` as
newline-joined `REPOS`; rebuild `--repo` flags from it whenever shelling out:

```bash
. "$RUN_DIR/ctx.env"
REPO_FLAGS=()
while IFS= read -r r; do [[ -n "$r" ]] && REPO_FLAGS+=(--repo "$r"); done <<<"$REPOS"
```

## Security Posture

Subagents inherit the orchestrating session's **permission mode**. Under the deployed
`base.json` (`defaultMode: bypassPermissions`), the `claude-delegate` subagent — and the `/prex` /
`/gc` work it runs — execute with that mode without any per-process flags. This is high privilege:
run only inside a trusted repository. The startup guard refuses a dirty worktree across every
declared repo and refuses any round already marked `doing`.

Do not weaken the trust boundary. The delegate uses the stowed skills from `$HOME/.claude/skills/`
and the stowed `$HOME/.claude/agents/claude-delegate.md`, not unstowed repo source. If nested
unattended `/prex` ever surfaces an approval prompt, the session was started in a weaker permission
mode than `bypassPermissions` — restart it under the intended mode after confirming the boundary.

## Usage

```bash
/plan-queue-runner .implementation-plans/plans/build-orion-nixos-config
/plan-queue-runner --dry-run .implementation-plans/plans/build-orion-nixos-config
/plan-queue-runner --max 1 .implementation-plans/plans/build-orion-nixos-config/QUEUE.yaml
```

`--max N` stops after `N` successfully committed rounds in this invocation. `--dry-run` prints the
next runnable round, all remaining `todo` rounds, and the planned `/gc -y -a` commit without
dispatching any delegate.

The plan directory or `QUEUE.yaml` path must not contain whitespace (arguments are tokenized by
word-splitting, matching the convention used by `/prex` and the `.implementation-plans/` layout).

## Algorithm

1. Parse only `-n|--dry-run`, `--max N` or `--max=N`, and one plan directory or `QUEUE.yaml` path.
2. Resolve `REPO_ROOT`, normalize `QUEUE_PATH`, read optional `repos:` satellites, create `RUN_DIR`,
   and write `RUN_DIR/ctx.env` including `REPOS`.
3. Ask `cog queue-select` to validate `QUEUE.yaml`, reject duplicate `item` values, reject
   any `doing` round, require a clean worktree across `REPO_ROOT` and every declared satellite, and
   select the first runnable `todo` round.
4. Use the helper's JSON result as the selection source. `queue-select` is read-only and never flips
   statuses; the runner still verifies status changes after the delegate returns.
5. Dispatch the round to a `claude-delegate` subagent via the **Agent tool** (foreground). The call
   blocks until the delegate's whole workflow finishes and returns its structured result.
6. Re-read `QUEUE.yaml` and require that round's status to be `done`; never write the queue.
7. Dispatch `/gc -y -a` plus `--repo` flags for satellites to a `claude-delegate` subagent the same
   way, parse the captured `COMMIT_*` line(s), then loop.

## Runner

Run this first Bash call to parse arguments, validate, and persist context. Shell variables and cwd
do not persist between tool calls; later snippets source `"$RUN_DIR/ctx.env"`.

```bash
cog plan-queue-runner-setup "${ARGUMENTS:-}"
```

The command parses the flags (`-n|--dry-run`, `--max N`) and the single TARGET (a plan dir or a
`QUEUE.yaml` path), resolves the repo root, normalizes the queue path, creates the run dir, writes
the load-bearing `ctx.env` (`REPO_ROOT`/`QUEUE_PATH`/`RUN_DIR`/`DRY_RUN`/`MAX_ROUNDS`/`REPOS`,
`%q`-quoted), and runs the first `queue-select`. It emits `RUN_DIR=<path>`; it exits 2 on a
bad/unknown flag or a missing/duplicate target, and exits 1 when outside a git repo, the queue is
missing, or `queue-select` fails (surface that error to the user).

For each loop iteration, re-run `queue-select` with satellite `--repo` flags and read the selected
round from its JSON output. `state: complete` means the queue is done; a helper failure means
validation failed, a `doing` round already exists, a worktree is dirty, or dependencies are blocked.

```bash
. "$RUN_DIR/ctx.env"
REPO_FLAGS=()
while IFS= read -r r; do [[ -n "$r" ]] && REPO_FLAGS+=(--repo "$r"); done <<<"$REPOS"
cog queue-select --queue "$QUEUE_PATH" --repo-root "$REPO_ROOT" "${REPO_FLAGS[@]}" \
  "$RUN_DIR/queue-select.json" \
  || { echo "ERROR: queue-select failed; see $RUN_DIR/queue-select.json" >&2; exit 1; }
STATE="$(jq -r '.state' "$RUN_DIR/queue-select.json")"
ITEM="$(jq -r '.selected.item // empty' "$RUN_DIR/queue-select.json")"
PROMPT="$(jq -r '.selected.prompt // empty' "$RUN_DIR/queue-select.json")"
```

For `--dry-run`, do not dispatch any delegate. Print the selected round, planned `/gc -y -a`, and all
remaining `todo` rounds:

```bash
. "$RUN_DIR/ctx.env"
yq e -r '.rounds[] | select(.status == "todo") | "- " + .item + ": " + .prompt' "$QUEUE_PATH"
```

For a real run, keep `RUN_COUNT`, `COMMITS`, and `STOP_REASON` in the model's state. Take the
selected `ITEM` and `PROMPT` from `queue-select.json` and set `SAFE_ITEM` with
`tr -c 'A-Za-z0-9_.-' '_'`:

```bash
. "$RUN_DIR/ctx.env"
ITEM="$(jq -r '.selected.item' "$RUN_DIR/queue-select.json")"
PROMPT="$(jq -r '.selected.prompt' "$RUN_DIR/queue-select.json")"
SAFE_ITEM="$(printf '%s' "$ITEM" | tr -c 'A-Za-z0-9_.-' '_')"
echo "REPO_ROOT=$REPO_ROOT ITEM=$ITEM"
```

### Dispatch the round

**Invoke the Agent tool now** (foreground — never `run_in_background`):

- `subagent_type`: `claude-delegate`
- `description`: `Run round <ITEM>` (substitute the literal item)
- `prompt` (substitute the literal `REPO_ROOT` and the verbatim `PROMPT` from `queue-select.json`,
  which preserves spaces/quotes exactly):

  ```text
  Working repo (your cwd): <REPO_ROOT>

  Run this queued implementation round to completion, exactly as written:

      <PROMPT>

  This is a `/prex` round: run all of its stages (plan → review → implement → review → loop).
  Run every Codex call in the foreground; never background it. The round is complete only when the
  plan is fully implemented and reviewed AND this round's status is flipped to `done` in QUEUE.yaml
  per the plan's final step. Return your structured result.
  ```

The Agent call blocks until the delegate returns. There are no `.out/.err/.status` files — the
delegate's structured result is returned in-context. A non-`done` outcome is surfaced directly by
the next step.

### Verify the round

Verify the round, by item, after the delegate returns:

```bash
. "$RUN_DIR/ctx.env"
ITEM="$ITEM" yq e -r '.rounds[] | select(.item == strenv(ITEM)) | .status' "$QUEUE_PATH"
```

The status must be exactly `done`; otherwise **fail closed** and stop. Do not edit `QUEUE.yaml`. A
round that returns but is **not** `done` means the delegate did not complete the workflow (e.g. it
reported a blocker, or `/prex` stopped before flipping the queue). This is a **hard fail** — report
the delegate's returned summary verbatim alongside the run dir, and stop:

```bash
. "$RUN_DIR/ctx.env"
ROUND_STATUS="$(ITEM="$ITEM" yq e -r '.rounds[] | select(.item == strenv(ITEM)) | .status' "$QUEUE_PATH")"
if [ "$ROUND_STATUS" != "done" ]; then
  echo "ERROR: round '$ITEM' is '$ROUND_STATUS', not 'done' — delegate did not complete it." >&2
  echo "See the claude-delegate result returned above and inspect: $RUN_DIR" >&2
  exit 1
fi
```

### Commit the round

Dispatch the commit to a `claude-delegate` subagent the same way. **Invoke the Agent tool**
(foreground). When `REPOS` is non-empty, run `/gc -y -a` with one `--repo <path>` flag per
satellite so `/gc` commits every repo the round touched.

- `subagent_type`: `claude-delegate`
- `description`: `Commit round <ITEM>`
- `prompt` (substitute the literal `REPO_ROOT`, `RUN_DIR`, `<n>` = current `RUN_COUNT`, and
  `<REPO_FLAGS>` = the space-joined `--repo <path>` flags, empty when there are no satellites):

  ```text
  Working repo (your cwd): <REPO_ROOT>

  Run `/gc -y -a <REPO_FLAGS>` to commit the current round's changes across every repo it touched.
  Then write ONLY the verbatim final `COMMIT_*` line(s) that /gc printed — one line per repo, in
  order (e.g. `COMMIT_OK <sha> repo=<root>`), and nothing else — to this exact path:
  <RUN_DIR>/commit-<n>.out

  Return your structured result with that COMMIT_* block as RESULT.
  ```

Parse the captured line(s) with the helper:

```bash
. "$RUN_DIR/ctx.env"
cog plan-queue-runner-parse-commit "$RUN_DIR/commit-$RUN_COUNT.out" || exit 1
cog plan-queue-runner-parse-commit "$RUN_DIR/commit-$RUN_COUNT.out" --json
```

The helper scans every `COMMIT_*` line. A single legacy line with no `repo=` suffix yields one
`COMMIT_SHA=<sha>`; multi-repo output yields one `COMMIT_SHA=<sha> repo=<root>` per repo and, with
`--json`, `{"ok":true,"commits":[{"repo","sha","line"}]}`. It exits non-zero if any repo's line is
`COMMIT_*_FAILED` or if no `COMMIT_*` line is present.

After each successful commit, record `ITEM:repo:SHA` for every committed repo, increment the counter,
honor `--max N`, and loop. At the end, report `run_dir`, `queue`, `rounds_run`, per-repo commits,
remaining `todo` rounds, and `stop_reason`.

## Rules

- Never write `QUEUE.yaml`; no `yq -i`, no `sed -i`, and no redirect to the queue path.
- Verify, do not set: after the round delegate returns, the round must already be `done`.
- Run each round in a fresh `claude-delegate` subagent (isolated context), foreground/blocking — one
  per round. Never use `run_in_background` for a dispatch.
- `/gc` is the only commit authority; parse only `COMMIT_OK`, `COMMIT_PUSH_OK`, `COMMIT_FAILED`, or
  `COMMIT_PUSH_FAILED` (each optionally `repo=`-suffixed) from the captured block.
- Always commit with `/gc -y -a` plus `--repo` per declared satellite; the startup clean-tree guard
  across every declared repo is what makes stage-all safe.
- Fail closed on existing `doing`, dirty startup tree in any declared repo, invalid queue shape, a
  round status other than `done` after the delegate returns, missing or failed commit status for any
  repo, blocked dependencies, or failed verification.
- Use each round entry's `prompt` verbatim. Do not reconstruct `/prex` commands.

## Failure Handling

Stop immediately on any failed guard, invalid YAML, duplicate `item`, no runnable round with `todo`
remaining, a round status other than `done` after its delegate returns, or a `/gc` failure line for
any repo. Report the run directory and the failing `claude-delegate` subagent's returned structured
result (`STATUS`/`RESULT`/`BLOCKERS`) so the user can see exactly where the round stopped.
