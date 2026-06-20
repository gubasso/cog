---
name: runner-queue
description: >
  Drive either an inner rounds: implementation queue from a plan directory or
  queue-rounds.yaml, or a top-level plans: main queue, to completion. Use when
  the user asks to "run the queue", "run the plan queue", "execute the plan
  rounds", "drive the plan directory", or invokes "runner-queue".
  Dispatches queued executor prompts to fresh claude-delegate subagents, verifies
  queue status, commits with /gc -a across every repo the item touched, runs the
  review-implementation-plans boundary, and loops until complete or failed closed.
argument-hint: "[-n|--dry-run] [--max <n>] <queue-path|plan-dir>"
disable-model-invocation: true
allowed-tools: Bash Read Agent Skill
---

<!-- trigger-tests: "runner-queue", "run the queue", "run the plan queue", "execute the plan rounds", "drive the plan directory" -->

# Runner Queue

Drive a plan-writer implementation queue to completion. This skill runs **inline** in the
orchestrating session at depth 0. In `rounds:` mode it preserves the existing per-round behavior:
select a runnable round, dispatch its exact `prompt` to a fresh `claude-delegate` subagent, verify
the round flipped itself to `done`, commit with `/gc -a`, run revision, and continue. In `plans:`
mode it selects main plans in order, resolves each one to an `inner_queue`, drives that inner queue,
flips the main plan to `done`, commits, runs revision, and continues.

Dispatch each round and each commit through the **Agent tool** (foreground, blocking). Nested
subagents (Claude Code >= v2.1.172) let `/executor-prex` spawn its own review-stage subagents from within the
delegate, so `/executor-prex` no longer needs its own top-level process. The old requirement to run each
round in a separate headless `claude -p` process is **obsolete and removed**; see the orchestration
contract docs for the current foreground Agent shape.

A foreground Agent call blocks the orchestrator until the delegate's agentic loop completes and
returns. The delegate's own Codex Bash calls, one level down, rely on the same session env guarantee
as the parent: `CLAUDE_CODE_DISABLE_BACKGROUND_TASKS=1` must be in force so Claude Code does not
auto-background long-running Bash calls. `/executor-prex` asserts that env at bootstrap; the foreground
discipline still applies to every Codex invocation. Multi-level round completion is independently
guaranteed by the queue-status check below.

## Queue Modes

- `rounds:` is inner queue mode. It is today's behavior: select runnable `todo` rounds from an inner
  `queue-rounds.yaml`, run each round through `claude-delegate`, verify the round is `done`, commit,
  revise, and loop.
- `plans:` is main queue mode. Select runnable `todo` plan entries from the top-level main queue,
  resolve each selected plan to its executable form, drive the resolved inner queue to completion,
  flip the main plan `done`, commit, revise, and loop.

`cog runner-queue-setup` auto-detects schema and writes `QUEUE_SCHEMA` to `RUN_DIR/ctx.env`. For
`plans:` it also writes `MAIN_QUEUE_PATH`. A queue file with neither or both top-level schema keys
fails closed in setup. Live data is directory-only in this round: every main plan resolves to
`kind: "inner_queue"` backed by `<plan-dir>/queue-rounds.yaml`; any other form fails closed in
`cog runner-queue-resolve-plan`.

A `plans:` entry selects the executor through its queued `prompt:`. The resolver accepts the
`-ar <plan-dir>` form for **any** `/executor-*` prompt — matched by the prefix taxonomy, not a
hardcoded list (`/prex` stays an alias for `/executor-prex`) — maps it to the plan directory's inner
`queue-rounds.yaml`, and preserves the prompt verbatim. Examples (not a closed set):

```yaml
plans:
  - item: plan-with-prex
    prompt: /executor-prex -ar @.implementation-plans/plans/plan-with-prex/
  - item: plan-with-claude
    prompt: /executor-claude -ar @.implementation-plans/plans/plan-with-claude/
  - item: plan-with-codex
    prompt: /executor-codex-session -ar @.implementation-plans/plans/plan-with-codex/
```

Plan directories are **flat siblings** directly under `.implementation-plans/plans/`
(`plans/<slug>/`); ordering between plans lives only in the top-level `queue-plans.yaml` `depends_on`
field, never in the filesystem. `cog runner-queue-resolve-plan` resolves each main-plan entry to one
`plans/<slug>/` directory and fails closed if the resolved target is not a direct child of `plans/`.

DO NOT delegate the main loop to a subagent. Main loop = depth 0; each round delegate = +1; each
review-implementation-plans subagent = +1 sibling, not nested under the round delegate; hard cap = 5.

## Multi-Repo Plans

A plan may write into more than one git repo: the repo holding the queue (`REPO_ROOT`, where queue
status flips live) plus one or more **satellite** repos the rounds implement into. Declare satellites
in an optional top-level `repos:` list in the inner `queue-rounds.yaml`, before `rounds:`:

```yaml
repos:
  - /abs/path/to/satellite-repo
rounds:
  - item: round-one
    prompt: "/executor-prex -ar .implementation-plans/plans/<plan>/round-one.md"
```

When present, the clean-tree guard covers every declared repo and the commit step runs
`/gc -a --repo <sat>...` so `/gc` commits both the queue flip in `REPO_ROOT` and artifacts in
satellites. `runner-queue-setup` and `runner-queue-resolve-plan` persist satellites as
newline-joined `REPOS`; rebuild `--repo` flags from it whenever shelling out:

```bash
. "$RUN_DIR/ctx.env"
REPO_FLAGS=()
while IFS= read -r r; do [[ -n "$r" ]] && REPO_FLAGS+=(--repo "$r"); done <<<"$REPOS"
```

## Security Posture

Subagents inherit the orchestrating session's **permission mode**. Under the deployed `base.json`
(`defaultMode: bypassPermissions`), the `claude-delegate` subagent - and the `/executor-prex` / `/gc` work it
runs - execute with that mode without per-process flags. Run only inside a trusted repository. The
startup guard refuses a dirty worktree across every declared repo and refuses any item already marked
`doing`.

Do not weaken the trust boundary. The delegate uses the stowed skills from `$HOME/.claude/skills/`
and the stowed `$HOME/.claude/agents/claude-delegate.md`, not unstowed repo source. If a nested
unattended executor ever surfaces an approval prompt, the session was started in a weaker permission
mode than `bypassPermissions`; restart it under the intended mode after confirming the boundary.

## Usage

```bash
/runner-queue .implementation-plans/queue-plans.yaml
/runner-queue --max 1 .implementation-plans/queue-plans.yaml
```

In `rounds:` mode, `--max N` stops after `N` successfully committed rounds in this invocation, and
`--dry-run` prints the next runnable round, remaining `todo` rounds, and the planned `/gc -a` commit
without dispatching any delegate. In `plans:` mode, `--max N` counts completed main plans, not inner
rounds; `--dry-run` prints the selected plan, resolved `kind`, resolved prompt, inner queue path, and
remaining `todo` plans, dispatching nothing and never flipping status, committing, or revising.

The plan directory or queue path must not contain whitespace. Arguments are tokenized by
word-splitting, matching the convention used by `/executor-prex` and the `.implementation-plans/`
layout.

## Algorithm

1. Parse only `-n|--dry-run`, `--max N` or `--max=N`, and one plan directory or queue path.
2. Run `cog runner-queue-setup "${ARGUMENTS:-}"` and capture `RUN_DIR` from its `RUN_DIR=<path>`
   stdout line, then source `"$RUN_DIR/ctx.env"`. Shell variables do not persist between tool calls,
   so do this in one Bash block and re-capture `RUN_DIR` the same way in any later block that needs
   it before `ctx.env` is sourced:

   ```bash
   RUN_DIR="$(cog runner-queue-setup "${ARGUMENTS:-}" | sed -n 's/^RUN_DIR=//p')"
   [ -n "$RUN_DIR" ] || { echo "ERROR: runner-queue-setup did not emit RUN_DIR" >&2; exit 1; }
   . "$RUN_DIR/ctx.env"
   echo "QUEUE_SCHEMA=$QUEUE_SCHEMA"
   ```

3. Branch on `QUEUE_SCHEMA`.
4. If `QUEUE_SCHEMA=rounds`, write `$RUN_DIR/inner.env` from setup values (the direct `rounds:`
   `inner.env` snippet in **Drive an inner queue**: `INNER_QUEUE_PATH="$QUEUE_PATH"`,
   `INNER_REPOS="$REPOS"`), then call **Drive an inner queue**.
5. If `QUEUE_SCHEMA=plans`, run **Main Queue Loop** inline.
6. Any other `QUEUE_SCHEMA` value is an impossible setup-contract violation; stop the run.

The setup command resolves the repo root, normalizes queue paths, creates `RUN_DIR`, writes
`ctx.env` (`REPO_ROOT`/`QUEUE_PATH`/`RUN_DIR`/`DRY_RUN`/`MAX_ROUNDS`/`REPOS`/`QUEUE_SCHEMA`, and
`MAIN_QUEUE_PATH` for `plans:`), and runs the initial validation/selection. It exits 2 for bad
arguments and exits 1 for invalid queue state; surface the helper error to the user.

## Drive an inner queue

This sub-procedure reads two **inner** values - `INNER_QUEUE_PATH` (always a `rounds:` queue) and
`INNER_REPOS` (newline-joined resolver repos or setup repos). Shell state does not persist between
tool calls, so these are never carried as live shell variables across snippets; each caller first
writes them to a durable `$RUN_DIR/inner.env` (a key=value file, the same pattern `cog ... -setup`
uses for `ctx.env`), and every snippet below sources `inner.env` right after `ctx.env`. Use the
dedicated `INNER_*` names - never the `ctx.env` `QUEUE_PATH`/`QUEUE_SCHEMA`/`REPOS`, which in `plans:`
mode point at the **main** queue and must stay intact for the next main `queue-select`.

A direct `rounds:` caller writes `inner.env` from setup values:

```bash
. "$RUN_DIR/ctx.env"
{ printf 'INNER_QUEUE_PATH=%q\n' "$QUEUE_PATH"; printf 'INNER_REPOS=%q\n' "$REPOS"; } > "$RUN_DIR/inner.env"
```

Main mode writes `inner.env` from the resolver output (see **Main Queue Loop**) before invoking this
sub-procedure. Either way, `inner.env` is the single durable source the snippets below depend on.

For each loop iteration, re-run selection (the inner queue is always schema `rounds`) with satellite
`--repo` flags and read the selected round from the helper JSON. `state: complete` means the inner
queue is done. A helper failure means validation failed, an item is already `doing`, a worktree is
dirty, or dependencies are blocked.

```bash
. "$RUN_DIR/ctx.env"; . "$RUN_DIR/inner.env"
REPO_FLAGS=()
while IFS= read -r r; do [[ -n "$r" ]] && REPO_FLAGS+=(--repo "$r"); done <<<"$INNER_REPOS"
cog queue-select --schema rounds --queue "$INNER_QUEUE_PATH" --repo-root "$REPO_ROOT" \
  "${REPO_FLAGS[@]}" "$RUN_DIR/queue-select.json" \
  || { echo "ERROR: queue-select failed; see $RUN_DIR/queue-select.json" >&2; exit 1; }
STATE="$(jq -r '.state' "$RUN_DIR/queue-select.json")"
ITEM="$(jq -r '.selected.item // empty' "$RUN_DIR/queue-select.json")"
PROMPT="$(jq -r '.selected.prompt // empty' "$RUN_DIR/queue-select.json")"
```

For `--dry-run`, do not dispatch any delegate. Print the selected round, planned `/gc -a`, and all
remaining `todo` rounds. In a direct inner-queue invocation, round-level `--max N` counts committed
rounds.

For a real run, keep `RUN_COUNT`, `COMMITS`, and `STOP_REASON` in the model's state. Take `ITEM` and
`PROMPT` from `queue-select.json` and set `SAFE_ITEM` with `tr -c 'A-Za-z0-9_.-' '_'`:

```bash
. "$RUN_DIR/ctx.env"; . "$RUN_DIR/inner.env"
ITEM="$(jq -r '.selected.item' "$RUN_DIR/queue-select.json")"
PROMPT="$(jq -r '.selected.prompt' "$RUN_DIR/queue-select.json")"
SAFE_ITEM="$(printf '%s' "$ITEM" | tr -c 'A-Za-z0-9_.-' '_')"
echo "REPO_ROOT=$REPO_ROOT ITEM=$ITEM INNER_QUEUE_PATH=$INNER_QUEUE_PATH"
```

### Dispatch the round

**Invoke the Agent tool now** (foreground - never `run_in_background`):

- `subagent_type`: `claude-delegate`
- `description`: `Run round <ITEM>` (substitute the literal item)
- `prompt` (substitute literal `REPO_ROOT` and the verbatim `PROMPT` from `queue-select.json`):

  ```text
  Working repo (your cwd): <REPO_ROOT>

  Run this queued implementation round to completion, exactly as written:

      <PROMPT>

  Run the queued prompt exactly as written; its slash command selects the executor. Run every Codex call in the foreground; never background it. The round is complete only when the plan is fully implemented and reviewed AND this round's status is flipped to `done` in queue-rounds.yaml per the plan's final step. Return your structured result.
  ```

The Agent call blocks until the delegate returns. There are no `.out/.err/.status` files; the
delegate's structured result is returned in context. A non-`done` outcome is surfaced by the next
step.

### Verify the round

Verify the round, by item, after the delegate returns:

```bash
. "$RUN_DIR/ctx.env"; . "$RUN_DIR/inner.env"
ITEM="$(jq -r '.selected.item' "$RUN_DIR/queue-select.json")"
[ -n "$ITEM" ] && [ "$ITEM" != null ] || { echo "ERROR: no selected item in queue-select.json" >&2; exit 1; }
ROUND_STATUS="$(ITEM="$ITEM" yq e -r '.rounds[] | select(.item == strenv(ITEM)) | .status' "$INNER_QUEUE_PATH")"
if [ "$ROUND_STATUS" != "done" ]; then
  echo "ERROR: round '$ITEM' is '$ROUND_STATUS', not 'done'; delegate did not complete it." >&2
  echo "See the claude-delegate result returned above and inspect: $RUN_DIR" >&2
  exit 1
fi
```

The status must be exactly `done`; otherwise fail closed and stop. Do not edit the inner queue.

### Commit the round

Dispatch the commit to a `claude-delegate` subagent the same way. **Invoke the Agent tool**
(foreground). Build the commit `--repo` flags from `INNER_REPOS` (the satellites the resolved inner
queue actually touches), not the `ctx.env` `REPOS` - in `plans:` mode `REPOS` is the main-queue's
satellite list and may omit repos the selected plan's inner queue declares, which would silently leave
satellite changes uncommitted. When `INNER_REPOS` is non-empty, run `/gc -a` with one `--repo <path>`
flag per satellite so `/gc` commits every repo the round touched:

```bash
. "$RUN_DIR/ctx.env"; . "$RUN_DIR/inner.env"
REPO_FLAGS=()
while IFS= read -r r; do [[ -n "$r" ]] && REPO_FLAGS+=(--repo "$r"); done <<<"$INNER_REPOS"
```

- `subagent_type`: `claude-delegate`
- `description`: `Commit round <ITEM>`
- `prompt` (substitute literal `REPO_ROOT`, `RUN_DIR`, `<n>` = current `RUN_COUNT`, and
  `<REPO_FLAGS>` = the space-joined `--repo <path>` flags, empty when there are no satellites):

  ```text
  Working repo (your cwd): <REPO_ROOT>

  Run `/gc -a <REPO_FLAGS>` to commit the current round's changes across every repo it touched.
  Then write ONLY the verbatim final `COMMIT_*` line(s) that /gc printed - one line per repo, in
  order (e.g. `COMMIT_OK <sha> repo=<root>`), and nothing else - to this exact path:
  <RUN_DIR>/commit-<n>.out

  Return your structured result with that COMMIT_* block as RESULT.
  ```

Parse the captured line(s) with the helper:

```bash
. "$RUN_DIR/ctx.env"
cog runner-queue-parse-commit "$RUN_DIR/commit-$RUN_COUNT.out" || exit 1
cog runner-queue-parse-commit "$RUN_DIR/commit-$RUN_COUNT.out" --json
```

The helper scans every `COMMIT_*` line. A single legacy line with no `repo=` suffix yields one
`COMMIT_SHA=<sha>`; multi-repo output yields one `COMMIT_SHA=<sha> repo=<root>` per repo and, with
`--json`, `{"ok":true,"commits":[{"repo","sha","line"}]}`. It exits non-zero if any repo's line is
`COMMIT_*_FAILED` or if no `COMMIT_*` line is present.

After each successful round commit, record `ITEM:repo:SHA`, run **Review-Implementation-Plans Boundary**, increment
the direct-round counter when this invocation is `rounds:` mode, honor direct-round `--max N`, and
loop.

## Main Queue Loop

The `plans:` main loop runs inline at depth 0. It is never delegated to an Agent subagent.

Shell state does not persist between tool calls, so source `ctx.env`, initialize the plan-level
`RUN_COUNT`, and rebuild `REPO_FLAGS` from `REPOS` before the first selection. Per plan iteration,
select the next plan:

```bash
. "$RUN_DIR/ctx.env"
: "${RUN_COUNT:=0}"
REPO_FLAGS=()
while IFS= read -r r; do [[ -n "$r" ]] && REPO_FLAGS+=(--repo "$r"); done <<<"$REPOS"
cog queue-select --schema plans --queue "$MAIN_QUEUE_PATH" --repo-root "$REPO_ROOT" \
  "${REPO_FLAGS[@]}" "$RUN_DIR/main-select-$RUN_COUNT.json"
```

`state: complete` finishes the main run. `blocked` or no runnable `todo` with remaining work is
fail-closed. Dirty-tree and invalid-queue failures are surfaced from `queue-select`.

Extract `PLAN_ITEM` from `.selected.item` and set `SAFE_ITEM` with `tr -c 'A-Za-z0-9_.-' '_'`, then
resolve the plan. Shell state does not persist between tool calls, so read `PLAN_ITEM` from the
selection JSON in the same block (do not rely on a prior assignment):

```bash
. "$RUN_DIR/ctx.env"
: "${RUN_COUNT:=0}"
PLAN_ITEM="$(jq -r '.selected.item' "$RUN_DIR/main-select-$RUN_COUNT.json")"
SAFE_ITEM="$(printf '%s' "$PLAN_ITEM" | tr -c 'A-Za-z0-9_.-' '_')"
cog runner-queue-resolve-plan --repo-root "$REPO_ROOT" --queue "$MAIN_QUEUE_PATH" \
  --item "$PLAN_ITEM" "$RUN_DIR/resolve-$SAFE_ITEM.json"
```

The only supported resolved form is `kind: "inner_queue"`, enforced by the command. It fails closed
if the target is not a directory carrying `queue-rounds.yaml`.

Read `.inner_queue_path` and `.repos` from the resolver output and write them to the durable
`$RUN_DIR/inner.env` that **Drive an inner queue** consumes (the resolver returns `.repos` as a JSON
array, so join it with newlines):

```bash
. "$RUN_DIR/ctx.env"
: "${RUN_COUNT:=0}"
PLAN_ITEM="$(jq -r '.selected.item' "$RUN_DIR/main-select-$RUN_COUNT.json")"
SAFE_ITEM="$(printf '%s' "$PLAN_ITEM" | tr -c 'A-Za-z0-9_.-' '_')"
INNER_QUEUE_PATH="$(jq -r '.inner_queue_path' "$RUN_DIR/resolve-$SAFE_ITEM.json")"
INNER_REPOS="$(jq -r '.repos[]? // empty' "$RUN_DIR/resolve-$SAFE_ITEM.json")"
{ printf 'INNER_QUEUE_PATH=%q\n' "$INNER_QUEUE_PATH"; printf 'INNER_REPOS=%q\n' "$INNER_REPOS"; } > "$RUN_DIR/inner.env"
```

Then invoke **Drive an inner queue** until the inner selection state is `complete`. The inner
procedure reads only `inner.env`; the `ctx.env` `QUEUE_PATH`/`QUEUE_SCHEMA`/`REPOS` still point at the
**main** queue and stay intact for the next main `queue-select`. Verify the inner queue is complete
before the main status flip.

Flip the main plan to `done` only through:

```bash
. "$RUN_DIR/ctx.env"
: "${RUN_COUNT:=0}"
PLAN_ITEM="$(jq -r '.selected.item' "$RUN_DIR/main-select-$RUN_COUNT.json")"
cog queue-status-set --queue "$MAIN_QUEUE_PATH" --schema plans --item "$PLAN_ITEM" \
  --from todo --to done "$RUN_DIR/main-status-$RUN_COUNT.json"
```

Main-plan `done` is always runner-owned via this exact command. Inner-round `done` remains
verify-only and is owned by the queued executor prompt.

Commit the plan's accumulated work plus the main-queue status flip with the existing foreground
`claude-delegate` `/gc -a` pattern. Build the `--repo` flags from `INNER_REPOS` (still in
`inner.env`) so the commit covers the selected plan's satellites; `/gc -a` always commits `REPO_ROOT`
itself, which carries the main-queue `done` flip. Parse with `cog runner-queue-parse-commit`,
run **Review-Implementation-Plans Boundary**, increment the plan-level counter, honor `--max N`, and loop. In main
mode an inner queue may run many rounds, but the plan-level `--max` counter increments only after the
main plan is flipped, committed, and revision completes.

## Dry Run And Max

`rounds:` mode preserves current behavior: dry-run prints the selected round, remaining `todo` rounds,
and the planned `/gc -a`; `--max N` counts successfully committed rounds. `plans:` mode dry-run runs
only main selection and plan resolution. Keep the block self-contained — shell state does not persist,
so source `ctx.env`, rebuild `REPO_FLAGS` from `REPOS`, and read `PLAN_ITEM`/`SAFE_ITEM` from the
dry-run selection output before resolving:

```bash
. "$RUN_DIR/ctx.env"
REPO_FLAGS=()
while IFS= read -r r; do [[ -n "$r" ]] && REPO_FLAGS+=(--repo "$r"); done <<<"$REPOS"
cog queue-select --schema plans --queue "$MAIN_QUEUE_PATH" --repo-root "$REPO_ROOT" \
  "${REPO_FLAGS[@]}" "$RUN_DIR/main-select-dry-run.json"
PLAN_ITEM="$(jq -r '.selected.item // empty' "$RUN_DIR/main-select-dry-run.json")"
SAFE_ITEM="$(printf '%s' "$PLAN_ITEM" | tr -c 'A-Za-z0-9_.-' '_')"
cog runner-queue-resolve-plan --repo-root "$REPO_ROOT" --queue "$MAIN_QUEUE_PATH" \
  --item "$PLAN_ITEM" "$RUN_DIR/resolve-$SAFE_ITEM.json"
```

Print the selected plan item, resolved `kind`, resolved prompt, resolved `inner_queue_path`, and
remaining `todo` plans. Do not dispatch a round delegate, call `queue-status-set`, commit, or run
`review-implementation-plans`. In main mode, `--max N` counts completed and committed main plans, not inner rounds.

## Review-Implementation-Plans Boundary

Run this boundary after every successful `/gc` for a committed item - after each committed inner
round and after each committed main plan - and before the next `queue-select`. Skip it entirely under
`--dry-run`.

Invoke the project-local `review-implementation-plans` skill as a foreground Agent subagent. It is a
sibling of the round delegate (+1 depth), not nested under it. Unlike the stowed
`$HOME/.claude/skills/` skills the delegate normally uses (see Security Posture),
`review-implementation-plans` is a **project** skill resolved from the repo working tree; the prompt
sets cwd to `REPO_ROOT` so the delegate loads
`.claude/skills/review-implementation-plans/SKILL.md` from there. The revision subagent owns its own
foreground `/gc -a` calls for revision drift; the runner does not issue a separate revision commit.
The boundary may produce up to two commits: one for plan reconciliation and one for queue
order/dependency review.

`review-implementation-plans` always requires `--main-queue`. In `plans:` mode pass `MAIN_QUEUE_PATH` from
`ctx.env`. In `rounds:` mode `ctx.env` has no `MAIN_QUEUE_PATH` (setup writes it only for `plans:`),
so resolve the project main queue - the root `.implementation-plans/queue-plans.yaml`, the canonical
location `review-implementation-plans` documents - before dispatching:

```bash
. "$RUN_DIR/ctx.env"
REVISION_MAIN_QUEUE="${MAIN_QUEUE_PATH:-$REPO_ROOT/.implementation-plans/queue-plans.yaml}"
[ -f "$REVISION_MAIN_QUEUE" ] || { echo "ERROR: revision main queue not found: $REVISION_MAIN_QUEUE" >&2; exit 1; }
```

Pass `REVISION_MAIN_QUEUE` as the `--main-queue` value in the prompt below. In `rounds:` mode the
revision pass reconciles the inner rounds queue against that project main queue; if a repo has no root
main queue the boundary fails closed rather than running `review-implementation-plans` with a missing argument.

- `subagent_type`: `claude-delegate`
- `description`: `Revise implementation plans`
- `prompt`:

  ```text
  Working repo (your cwd): <REPO_ROOT>

  Run the project-local `review-implementation-plans` skill after the committed queue item:

      --repo-root <REPO_ROOT>
      --main-queue <REVISION_MAIN_QUEUE>

  Use RUN_DIR=<RUN_DIR> for scan, verify, and commit-output files. First reconcile the main plans
  queue and inner rounds queues with current repo state, mutating queues only through cog
  queue-status-set or cog queue-append, then commit any reconciliation drift through /gc in the
  foreground. Second, review queue execution order and dependencies, mutating dependencies only
  through cog queue-deps-set, deriving physical order only through cog queue-reorder, and validating
  with cog queue-graph-check, then commit any queue-review drift through /gc in the foreground.
  Return STATUS: OK with a RESULT line that reports both phases, using NO_DRIFT for a phase that
  changed nothing. Return STATUS: FAILED on any scan, verify, graph-check, or commit failure.
  ```

After it returns, require `STATUS: OK` and verify a clean worktree plus a parseable result for both
phases: each phase is either `NO_DRIFT` or a parsed revision `REVISION_COMMIT_OK <sha>` / multi-repo
summary. The `review-implementation-plans` skill must have passed
`cog review-implementation-plans-verify`; if the result is missing, failed, dirty, or unparseable,
stop the entire run before selecting more work.

Assumption: `review-implementation-plans` already performs `cog review-implementation-plans-scan`,
`cog review-implementation-plans-verify`, `cog queue-deps-set`, `cog queue-reorder`,
`cog queue-graph-check`, and its own foreground `/gc`; this runner enforces the boundary and
postcondition.

## Rules

- Skill prose never hand-edits queues: no `yq -i`, no `sed -i`, and no redirects to queue files.
  Writing run-scoped state files under `$RUN_DIR` (for example `inner.env`, mirroring setup's
  `ctx.env`) is not a queue edit and is allowed.
- Inner-round `done` remains verify-only after the round delegate returns; it is owned by the queued executor prompt.
- Main-plan `done` is set only by `cog queue-status-set --schema plans --from todo --to done`.
- Revision queue mutations go only through `cog queue-status-set`, `cog queue-append`,
  `cog queue-deps-set`, and `cog queue-reorder`; graph validation goes through
  `cog queue-graph-check`.
- Run each round in a fresh `claude-delegate` subagent, foreground/blocking, one per round. Never use
  `run_in_background` for a dispatch.
- `/gc` is the only commit authority. The main runner commits round/main work; the revision subagent
  commits revision drift in up to two phases. Parse only `COMMIT_OK`, `COMMIT_PUSH_OK`, `COMMIT_FAILED`, or
  `COMMIT_PUSH_FAILED` lines, each optionally `repo=`-suffixed, from captured blocks.
- Always commit with `/gc -a` plus `--repo` per satellite, building the satellite list from the inner
  queue's repos (`INNER_REPOS`), not the main-queue `REPOS`; the clean-tree guard across every
  declared repo is what makes stage-all safe.
- Use queued prompts verbatim. Do not reconstruct executor commands. Any `/executor-*` prompt is accepted (matched by the prefix taxonomy); `/prex` is supported only as an alias for `/executor-prex`.
- Plan directories are flat siblings under `plans/`; the resolver fails closed on a nested target.
  Do not work around it by hand-resolving a nested path.
- Never delegate the main loop to a subagent. Never background Agent, queued executor prompts, `/gc`, or revision work.

## Failure Handling

Stop immediately on any failed guard or durable postcondition: setup rejecting invalid or ambiguous
queue schema; invalid YAML; duplicate item; existing `doing`; dirty tree; blocked dependencies;
`queue-select` failure; main-plan resolver failure or unsupported kind; inner queue not reaching
`state: complete`; inner-round delegate returning while the round is not `done`; main
`queue-status-set` guard failure because the item is no longer `todo`; missing or failed `COMMIT_*`;
revision returning `STATUS: FAILED`, lacking a verified clean postcondition, or not proving
`review-implementation-plans-verify` passed.

An intentional `--max` stop is normal and reports remaining work. Dry-run never dispatches, flips
status, commits, or runs revision. Report the run directory and the failing `claude-delegate`
subagent's returned structured result (`STATUS`/`RESULT`/`BLOCKERS`) so the user can see exactly
where the run stopped.
