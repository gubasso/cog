# Runner Orchestration Integration: Main-Queue Loop + Plans-Revision Boundary

> Plan: plan-queue-runner-main-revision | Round: 3 of 3 | Complexity: L | Generated: 2026-06-19 |
> Repo: /workspaces/cog | Executor: prex (EF 1.5)

## Context

The final behavior lives in `skills/claude/runner-queue/SKILL.md`. Today it drives ONE inner
`rounds:` queue: dispatch each `todo` round to a fresh `claude-delegate`, verify the round flipped
itself to `done`, commit with `/gc -a`, loop. This round edits that skill ONCE to: detect the queue
schema (from setup's `QUEUE_SCHEMA`), drive a top-level `plans:` MAIN queue inline (depth 0), resolve
each selected plan form, drive inner queues when needed, flip main plans `done` via
`cog queue-status-set`, and invoke the `plans-revision` skill as a foreground subagent after every
committed item (both inner-round and main-plan boundaries). The existing single inner-queue behavior
is preserved.

## Previous Rounds

Round 1 added schema-generic selection (`cog queue-select --schema`), `cog queue-status-set`,
`cog runner-queue-resolve-plan`, and `QUEUE_SCHEMA`/`MAIN_QUEUE_PATH` detection in setup.
Round 2 added `cog plans-revision-scan` / `cog plans-revision-verify`, the project-local
`.claude/skills/plans-revision/SKILL.md`, and `docs/decisions/0011-plan-queue-revision-boundary.md`.
Expected state: every deterministic primitive and the revision skill exist and are tested; only the
runner orchestration prose remains.

## Scope of This Round

- IN scope:
  - Refactor `skills/claude/runner-queue/SKILL.md`: frontmatter description + `argument-hint`;
    a "Queue Modes" section; a schema branch after setup; the INLINE main-queue loop; per-plan form
    handling; the plan-level `done` flip via `queue-status-set`; the "Plans-Revision Boundary"
    section; updated Rules and Failure Handling; `--max`/`--dry-run` at the plan level.
  - Preserve the existing inner `rounds:` mode unchanged (plus revision after each committed round).
  - Integration-ish `bats`/skill-lint coverage that is feasible without real Agent delegation; update
    help/snapshot/lint expectations for the touched skill.
- OUT of scope: changing `/prex` or `/gc` semantics; adding background orchestration; new `cog`
  commands (all landed in Rounds 1-2). No change to `cmd_runner_queue_parse_commit.sh` (reused).

## Current State

### Key Files

- `/workspaces/cog/skills/claude/runner-queue/SKILL.md` — the runner. Frontmatter
  `disable-model-invocation: true`, `allowed-tools: Bash Read Agent Skill`,
  `argument-hint: "[-n|--dry-run] [--max <n>] <plan-dir-or-queue-path>"`. Runs INLINE; dispatches each
  round to `claude-delegate` via the Agent tool (foreground, blocking). Today's Algorithm
  (lines 97-112): parse -> `cog runner-queue-setup` -> loop `cog queue-select` -> dispatch round
  -> re-read require `done` -> dispatch `/gc -a` (+ `--repo` satellites) -> parse `COMMIT_*` -> loop.
  Per-loop selection snippet (lines 133-143) and the satellite `REPO_FLAGS` rebuild (lines 63-67) are
  the integration points. Current Rules (254-267): "Never write `queue-rounds.yaml`"; "Verify, do not set";
  "use each entry's prompt verbatim"; "`/gc` is the only commit authority".

- Round-1/2 surfaces this round wires together: `cog queue-select --schema`,
  `cog runner-queue-resolve-plan`, `cog queue-status-set`, `cog plans-revision-scan/verify`, and
  `.claude/skills/plans-revision/SKILL.md`. The `claude-delegate` agent (`All tools`) is the existing
  isolation primitive.

- `/workspaces/cog/.implementation-plans/queue-plans.yaml` — the live `plans:` main queue used as the
  primary manual end-to-end target after this round.

### Existing Patterns

- `ctx.env` is `%q`-quoted key=value sourced by later Bash calls (cwd/vars do not persist between
  tool calls). The runner already rebuilds `REPO_FLAGS` from `REPOS`.
- Orchestration contract (`docs/reference/orchestration-contract.md`): Skill-inline = 0 depth;
  Agent-delegate/foreground = +1; hard cap 5. Env-first no-backgrounding (ADR-0010). Every boundary
  verifies a durable postcondition.
- `cog skill-lint` hard-fails the structural + orchestration anti-patterns listed in Round 2; run it
  on the touched skill.

## Implementation Steps

### First Step: Mark this round as started

In this plan's `queue-rounds.yaml`, set this round's (`item: runner-orchestration-integration`) `status` to
`doing`.

### Step 1: Frontmatter, intro, usage, "Queue Modes"

Update the description + `argument-hint` to accept either an inner `rounds:` queue OR a top-level
`plans:` main queue (e.g. `argument-hint: "[-n|--dry-run] [--max <n>] <queue-path|plan-dir>"`).
The live data is directory-only (`plan-dir` with `queue-rounds.yaml`); a `plans:` entry always
resolves to an `inner_queue`.
Add a "Queue Modes" section: `rounds:` -> inner mode (today's behavior); `plans:` -> main mode (select
plans in order, drive each to completion); auto-detected via `QUEUE_SCHEMA` from setup. Add usage
examples:

```bash
/runner-queue .implementation-plans/queue-plans.yaml
/runner-queue .implementation-plans/plans/build-orion-nixos-config
/runner-queue --max 1 .implementation-plans/queue-plans.yaml
```

### Step 2: Schema branch + inner-queue sub-procedure

After `cog runner-queue-setup`, source `ctx.env` and branch on `QUEUE_SCHEMA`. Refactor the
current 7-step loop into a named sub-procedure "Drive an inner queue" (unchanged dispatch/verify/`/gc`,
PLUS the revision call from Step 4), so BOTH the `rounds:` mode and the main mode's per-plan
`inner_queue` case reuse it. The selection snippet becomes schema-aware:

```bash
cog queue-select --schema "$QUEUE_SCHEMA" --queue "$QUEUE_PATH" --repo-root "$REPO_ROOT" \
  "${REPO_FLAGS[@]}" "$RUN_DIR/queue-select.json"
```

### Step 3: Inline main-queue loop (`plans` mode, depth 0)

Document the INLINE loop (no new subagent layer). Per iteration:

1. `cog queue-select --schema plans --queue "$MAIN_QUEUE_PATH" ...` to pick the next runnable `todo`
   plan; on `state: complete` finish; on `blocked` fail closed.
2. `cog runner-queue-resolve-plan --repo-root "$REPO_ROOT" --queue "$MAIN_QUEUE_PATH"
   --item "$PLAN_ITEM"` to resolve the plan's `inner_queue` form (it fails closed otherwise).
3. Execute the resolved `inner_queue`: rebuild `REPO_FLAGS` from the resolver's `repos`, then run the
   "Drive an inner queue" sub-procedure against `inner_queue_path` until `state: complete`.
4. Verify completion (inner `state: complete`), then flip the MAIN plan to done:

   ```bash
   cog queue-status-set --queue "$MAIN_QUEUE_PATH" --schema plans --item "$PLAN_ITEM" \
     --from todo --to done "$RUN_DIR/main-status-$RUN_COUNT.json"
   ```

5. Commit the plan's work + the main-queue status flip with `/gc -a` (+ satellite `--repo` flags),
   parse via `cog runner-queue-parse-commit`.
6. Run the plans-revision boundary (Step 4).
7. Honor `--max N` (plan-level), then loop.

State explicitly: the main-plan `done` flip is ALWAYS via `cog queue-status-set` (no `/prex` owns it);
inner-round `done` stays verify-only. And: "DO NOT delegate the main loop to a subagent" with the
depth math.

### Step 4: "Plans-Revision Boundary" section

Add a section invoked AFTER each successful `/gc` for a committed item (both an inner round and a
completed main plan) and BEFORE the next `queue-select`. It dispatches the project-local
`plans-revision` skill to a FOREGROUND Agent subagent (a SIBLING of the round delegate, +1 depth, NOT
nested), e.g.:

```text
Working repo (your cwd): <REPO_ROOT>

Run the project-local `plans-revision` skill for this repository after the committed queue item:

    --repo-root <REPO_ROOT>
    --main-queue <MAIN_QUEUE_PATH>

Reconcile the main plans queue and every inner rounds queue with the current repo state; apply only
allowed plan/queue edits (mutable todo/backlog items; mark implemented items done via
cog queue-status-set; append regressions/gaps via cog queue-append); preserve completed history;
commit any revision edits via /gc. If no drift, return NO_DRIFT with a verified clean tree. Return a
structured result with the scan/verify paths and any COMMIT_* lines.
```

Durable postcondition after it returns: either `NO_DRIFT` with a clean worktree, or a parsed revision
`COMMIT_*` with a clean worktree, AND `cog plans-revision-verify` passed. Otherwise STOP the whole run
(fail closed). Skip the revision boundary under `--dry-run`. Decide and document whether the runner or
the revision subagent issues the `/gc` (see the Round-2 open choice) and keep `/gc` foreground.

### Step 5: Update Rules + Failure Handling

Narrow the absolute "Never write `queue-rounds.yaml`" rule to:

- The skill prose never hand-edits queues (no `yq -i`, `sed -i`, or redirects).
- Inner-round `done` remains verify-only (owned by the round's `/prex`).
- Main-plan `done` is set ONLY by `cog queue-status-set --schema plans --from todo --to done`.
- All revision queue mutations go ONLY through `cog queue-status-set` / `cog queue-append`.

Extend Failure Handling with the main-queue + revision cases: invalid/ambiguous main shape; a plan
that doesn't reach its completion postcondition; a `queue-status-set` guard failure; a revision that
fails closed; `--max`/`blocked`/dirty-tree as today. Add the depth-shape note. Keep the file
<= 500 lines.

### Step 6: `--max` / `--dry-run` at the plan level

For a `plans:` main queue, `--max N` counts completed PLANS and `--dry-run` prints the selected plan,
its resolved `kind`, the prompt or inner queue it would drive, and the remaining `todo` plans — without
dispatching delegates, flipping status, committing, or running revision. Preserve the existing
round-level semantics for an inner `rounds:` queue.

### Step 7: Tests, skill-lint, docs

- `cog skill-lint skills/claude/runner-queue/SKILL.md` (and re-confirm
  `.claude/skills/plans-revision/SKILL.md`) pass; fix findings.
- Update any skill-trigger/snapshot tests (e.g. `test/integration/skills_claude.bats`) for the changed
  description/triggers. Do not attempt to integration-test real Agent delegation in `bats`; the
  deterministic pieces are covered by Rounds 1-2.
- Update `docs/reference/cli-commands.md` only for any residual command drift; update
  `docs/reference/orchestration-contract.md` if a one-line note about the sibling revision boundary
  clarifies the pattern; ensure `just lint` and `just test` pass.
- Manual end-to-end smoke (document results, do not automate): a `--dry-run` against
  `.implementation-plans/queue-plans.yaml` shows the next `todo` plan, its kind, and remaining plans.

### Final Step: Update the queue

1. In this plan's `queue-rounds.yaml`, set this round's (`item: runner-orchestration-integration`) `status`
   to `done`.
2. All rounds are now done, so set this plan's item (`plan-queue-runner-main-revision`) to `done` in
   the top-level `/workspaces/cog/.implementation-plans/queue-plans.yaml` (now achievable via
   `cog queue-status-set --schema plans`, or per the executing `/prex` final step). Leave the plan
   directory in place.

## Acceptance Criteria

- [ ] `/runner-queue <inner plan dir>` (inner `rounds:` mode) remains supported and unchanged
      except for the added revision boundary after each committed round.
- [ ] `/runner-queue .implementation-plans/queue-plans.yaml` drives the top-level `plans:` queue inline
      (depth 0), resolving every plan entry to its `inner_queue` form and failing closed on any entry
      that is not a directory carrying `queue-rounds.yaml`.
- [ ] Main-plan completion is set via `cog queue-status-set --schema plans`; inner-round completion
      stays verify-only; the skill never hand-edits a queue.
- [ ] The `plans-revision` skill runs as a foreground subagent after every committed inner round and
      every committed main plan, before the next selection; the runner verifies a clean tree +
      `plans-revision-verify` and STOPS on revision failure.
- [ ] Depth budget holds (main loop 0; round delegate +1; revision +1 sibling) and is stated in prose.
- [ ] `--max` / `--dry-run` operate at the plan level for a main queue.
- [ ] `cog skill-lint` passes for the touched skills; `just lint` and `just test` pass including drift
      checks.
- [ ] This plan's `queue-rounds.yaml` shows round `runner-orchestration-integration` as `done`, and the
      top-level `.implementation-plans/queue-plans.yaml` shows `plan-queue-runner-main-revision` as `done`.

## Next Round

This is the final round.
