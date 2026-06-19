# Plans-Revision Mechanics: Scan/Verify Commands + Project-Local `plans-revision` Skill

> Plan: plan-queue-runner-main-revision | Round: 2 of 3 | Complexity: L | Generated: 2026-06-19 |
> Repo: /workspaces/cog | Executor: prex (EF 1.5)

## Context

Feature B: after each committed plan-queue-runner item the runner must reconcile the implementation
plans with the actual repo state before selecting the next item. This round adds the deterministic
`cog` mechanics and the dedicated project-local skill; wiring into the runner is Round 3.

Per the coordinator interview (firm decisions): revision is ADAPTIVE (revise remaining `todo`/`backlog`
plan & round files, mark already-implemented items `done`, append new rounds/plans for
regressions/gaps; NEVER edit recorded history of `done` items); runs at BOTH boundaries (after every
committed inner round AND every committed main plan), reconciling ALL plans (main + every inner
queue); is PACKAGED as a new project-local `.claude/skills/plans-revision/` skill invoked as a
dedicated foreground subagent, with deterministic state-vs-queue mechanics in NEW `cog` subcommands
(reusing the `fn_refactor` fingerprint prior art); and is AUTO-APPLY + FAIL-CLOSED (applies edits
unattended, commits via `/gc`, no-drift is a no-op, STOP the whole run if it cannot reach a clean,
committed, verifiable state). Revision MUST use ONLY the `cog queue-status-set` / `cog queue-append`
helpers from Round 1 — never a parallel mutation path.

## Previous Rounds

Round 1 (`queue-main-primitives`) produced: schema-aware selection (`cog::fn::queue_select_next_item`
/ `queue_validate_selectable`, `cog queue-select --schema`), `cog queue-status-set` (guarded
single-item flip), `cog plan-queue-runner-resolve-plan`, and `QUEUE_SCHEMA`/`MAIN_QUEUE_PATH`
detection in setup. Expected state: queues of either schema are selectable and statuses are flippable
deterministically.

## Scope of This Round

- IN scope:
  - Add a shared helper `lib/functions/fn_plans_revision.sh` (`cog::fn::plans_revision_*`) for queue
    inventory and repo/plan fingerprints, reusing `cog::fn::refactor_scan_fingerprint`.
  - Add `cog plans-revision-scan` — enumerate the main `plans:` queue + every inner `rounds:` queue
    under `.implementation-plans/plans/`, with each item's `schema/queue_path/item/status/depends_on/
    prompt/notes/mutable` and stable repo/plan fingerprints, as machine JSON.
  - Add `cog plans-revision-verify` — compare a before/after scan and assert completed-history
    immutability + queue validity; the deterministic postcondition the skill and runner check.
  - Add `.claude/skills/plans-revision/SKILL.md` (project-local; sibling of
    `.claude/skills/skill-builder/`): a prose orchestrator that scans, applies only allowed edits via
    `cog queue-status-set` / `cog queue-append` and direct edits to mutable `todo`/`backlog` plan/round
    files, commits via `/gc` (or no-ops), and verifies. Fail closed.
  - `bats` tests for the new commands; `cog skill-lint` on the new skill; a new ADR; doc/man/completion
    drift updates.
- OUT of scope: calling plans-revision from `plan-queue-runner` and any change to
  `plan-queue-runner/SKILL.md` (Round 3). No queue-schema change; no reordering of existing entries;
  no editing recorded history of `done` items.

## Current State

### Key Files

- `/workspaces/cog/lib/functions/fn_refactor.sh` — drift fingerprint prior art to reuse/extend:

  ```bash
  cog::fn::refactor_scan_fingerprint() {
    local scan="${1:-}"
    __cog_refactor_require_scan_dir "$scan"
    ( cd "$scan" && find . -type f -print0 | LC_ALL=C sort -z \
      | xargs -0 cat 2>/dev/null | sha256sum | cut -d' ' -f1 )
  }
  ```

  and `/workspaces/cog/lib/commands/cmd_refactor_scan_drift.sh` — the closest existing
  "current state vs plan" mechanism. Prefer extracting a shared fingerprint helper if the existing one
  cannot be reused as-is (exclude `.git`, run dirs, and caches from the repo fingerprint).

- Round-1 helpers and commands: `cog queue-status-set`, `cog queue-append` (`--schema plans|rounds`),
  `cog::fn::queue_*` (validate/count/has_item/select). Revision MUST use these, never a parallel
  writer.

- `/workspaces/cog/.claude/skills/skill-builder/SKILL.md` — the project-local skill template:
  frontmatter `name`/`description`/`model`/`effort`, a `<!-- trigger-tests: ... -->` comment, a prose
  orchestrator that calls `cog` for all deterministic mechanics, runs `cog skill-builder-validate
  --draft` + `cog skill-lint` before presenting. Model the new skill on this shape.

- `/workspaces/cog/skills/claude/gc/SKILL.md` — `/gc` is the ONLY commit authority. Result lines:
  `COMMIT_OK <sha>` (single repo) or `COMMIT_OK <sha> repo=<root>` (multi); parsed by
  `cog plan-queue-runner-parse-commit`, which fails closed on any `*_FAILED`. `/gc -a` stages all
  dirty session files in declared repos; multi-repo via `--repo <dir>`; never `--no-verify`.

- `/workspaces/cog/.implementation-plans/queue-plans.yaml` and `.implementation-plans/plans/*/queue-rounds.yaml` —
  the live queues to inventory. Observed top-level keys: main -> `[plans]`; inner ->
  `[rounds]` or `[repos, rounds]`.

### Existing Patterns

- Project-local skills live at `/workspaces/cog/.claude/skills/` (NOT `skills/claude/`, which holds the
  stowed/shipped skills). New project-internal skills belong here.
- Skill contract (`docs/reference/skill-contract.md`): Claude-skill frontmatter allowlist enumerated
  there; `cog skill-lint` hard-fails on bad frontmatter, >500-line `SKILL.md`, untagged fences, emoji,
  missing `trigger-tests`, and orchestration anti-patterns (`orchestration-background-codex`,
  `orchestration-pretooluse-guarantee`, `orchestration-claude-p-recursion`,
  `orchestration-unlimited-depth`, `orchestration-removed-codex-foreground`).
- ADRs in `docs/decisions/` (template at `docs/decisions/template.md`; latest accepted is `0010`).
  Accepted ADRs are never deleted; record new decisions as new ADRs. Markdown fences must declare a
  language.
- Orchestration contract: foreground Agent delegation only at true isolation boundaries; verify a
  durable postcondition at every boundary; env-first no-backgrounding; 5-level depth cap.

## Implementation Steps

### First Step: Mark this round as started

In this plan's `queue-rounds.yaml`, set this round's (`item: plans-revision-mechanics`) `status` to `doing`.

### Step 1: Shared revision helper `fn_plans_revision.sh`

Create `lib/functions/fn_plans_revision.sh` with `cog::fn::plans_revision_*` helpers (deterministic,
machine-facing):

- `cog::fn::plans_revision_inventory_json <repo_root> <main_queue>` — emit a JSON inventory of the main
  queue and every inner queue under `.implementation-plans/plans/`, each item carrying
  `schema/queue_path/item/status/depends_on/prompt/notes` and a `mutable` flag (`true` for
  `todo`/`backlog`, `false` for `done`/`doing`).
- `cog::fn::plans_revision_repo_fingerprint <repo_root>` — stable fingerprint of implementation-relevant
  repo state (exclude `.git`, run dirs, caches), built on `refactor_scan_fingerprint` (extract a shared
  helper if needed).
- `cog::fn::plans_revision_plans_fingerprint <repo_root>` — fingerprint of `.implementation-plans/`
  plan + queue files, separate from implementation source (so "did plans change" is distinguishable
  from "did code change").

### Step 2: Add `cog plans-revision-scan`

Create `lib/commands/cmd_plans_revision_scan.sh` (line-2 `: 'desc: Inventory all implementation-plan
queues and repo/plan fingerprints.'`, handler `cog::cmd::plans_revision_scan`). Flags:
`--repo-root <dir> --main-queue <path> (<out.json>|--json)`. Output JSON:
`{ok, repo_root, main_queue_path, repo_fingerprint, plans_fingerprint, queues: [{path, schema,
items: [{item, status, depends_on, prompt, notes, mutable}]}]}` with a self-check predicate. Exit `0`
on success; `$EX_USAGE` (2) for bad flags; non-zero for missing/invalid/ambiguous queue or duplicate
items.

### Step 3: Add `cog plans-revision-verify`

Create `lib/commands/cmd_plans_revision_verify.sh` (line-2 `: 'desc: Verify a plans-revision against a
before/after scan.'`, handler `cog::cmd::plans_revision_verify`). Flags:
`--before <scan.json> --after <scan.json> [--allow-noop] (<out.json>|--json)`. It asserts:

- Completed-history immutability: every item that was `done` in `before` still exists, is still `done`,
  and its `prompt`/`depends_on` are unchanged (prefer strict; allow `notes` only if explicitly
  documented).
- Every queue in `after` is still valid (re-validate via `queue_validate_file`).
- Reports `changed` (any queue/plan file changed), `new_items`, and `status_changes`.

Output JSON: `{ok, changed, completed_history_preserved, before_plans_fingerprint,
after_plans_fingerprint, changed_queues, new_items, status_changes}` with a self-check predicate.
Exit `0` when verification passes; non-zero when completed history was edited, a queue became invalid,
or a scan is malformed (fail-closed).

### Step 4: Add the `plans-revision` project skill

Create `/workspaces/cog/.claude/skills/plans-revision/SKILL.md` modeled on `skill-builder`. Suggested
frontmatter (within the skill-contract allowlist):

```yaml
---
name: plans-revision
description: >
  Reconcile implementation plans and queues with the current repository state
  after a committed plan-queue-runner item, before selecting the next item, so
  remaining plans stay coherent with implemented code. Adaptive and fail-closed.
model: sonnet
effort: high
argument-hint: "--repo-root <dir> --main-queue <path>"
allowed-tools: Bash Read Edit Write Skill
disable-model-invocation: true
---
```

Include a `<!-- trigger-tests: ... -->` comment. Prose orchestration only — all deterministic work
delegates to `cog`. Skill behavior:

1. `cog plans-revision-scan --repo-root <repo> --main-queue <queue> "$RUN_DIR/before.json"`.
2. Inspect current repo state vs the remaining MUTABLE (`todo`/`backlog`) items.
3. Mark already-implemented mutable items `done` via `cog queue-status-set` (guarded `--from`/`--to`).
4. Revise remaining mutable plan & round files for coherence with current code (judgment; Edit/Write
   on `todo`/`backlog` plan files only). Never touch `done` items' recorded history.
5. Append new rounds/plans for regressions or newly-found gaps via `cog queue-append --schema
   plans|rounds`.
6. `cog plans-revision-scan ... "$RUN_DIR/after.json"`, then
   `cog plans-revision-verify --before "$RUN_DIR/before.json" --after "$RUN_DIR/after.json"
   "$RUN_DIR/verify.json"`.
7. If `verify.changed == false`: confirm a clean worktree and return `STATUS: OK`, `RESULT: NO_DRIFT`.
8. If changed: commit the plan edits via `/gc -a` (foreground; never background), parse the
   `COMMIT_*` line via `cog plan-queue-runner-parse-commit`, and return `RESULT: REVISION_COMMIT_OK
   <sha>`.
9. Fail closed (non-OK structured result) if scan/verify fails, completed history was touched, or the
   commit fails — the parent runner will stop the whole run.

Prose constraints: foreground only; no backgrounding; deterministic mechanics in `cog`; do not embed
nontrivial shell beyond reading env and extracting JSON fields (skill-lint premise checks). Keep the
file <= 500 lines and add an `<!-- cog-skill-lint: allow-inline-shell <reason> -->` marker only if a
genuinely necessary inline snippet trips the premise linter.

> Open implementation choice for the executor to settle and document: whether the revision subagent
> itself runs `/gc` (self-contained; recommended, matches "executed as an agent calling that skill"),
> or only revises and returns a `changed` result for the RUNNER to commit (Round 3). Either way the
> edits MUST be committed via `/gc` before the next item and verified clean.

### Step 5: ADR

Write `docs/decisions/0011-plan-queue-revision-boundary.md` (from `docs/decisions/template.md`)
recording the plans-revision decision: adaptive authority, both-boundaries cadence, project-skill +
foreground-agent packaging, auto-apply + fail-closed posture, deterministic-mechanics-in-`cog`
boundary, and the sibling-subagent depth shape. (If Round 3 needs to amend it before acceptance, do so
in the same change set.)

### Step 6: Tests, skill-lint, drift

- New `test/integration/plans_revision_scan.bats`: inventories a main queue + an inner queue; marks
  `done` items immutable / `todo`/`backlog` mutable; fails on both/neither schema in one queue;
  emits stable fingerprints.
- New `test/integration/plans_revision_verify.bats`: passes a no-op; detects a completed-history
  rewrite (fail closed); reports changed fingerprints / new items / status changes.
- `cog skill-lint .claude/skills/plans-revision/SKILL.md` passes (extend
  `test/integration/cmd_skill_lint.bats` only if a new expectation is genuinely required).
- Update `docs/reference/cli-commands.md`, `completions/cog.bash`, `man/cog.1.scd` (regenerate
  `man/cog.1`), and help snapshots for the two new commands.

### Final Step: Update the queue

1. In this plan's `queue-rounds.yaml`, set this round's (`item: plans-revision-mechanics`) `status` to `done`.

## Acceptance Criteria

- [ ] `cog plans-revision-scan` inventories the main queue + every inner queue with `mutable` flags
      and stable repo/plan fingerprints; each new command module has its line-2 `: 'desc:'` sentinel.
- [ ] `cog plans-revision-verify` passes a no-op and FAILS closed on any completed-history edit or
      invalidated queue.
- [ ] `.claude/skills/plans-revision/SKILL.md` exists, passes `cog skill-lint`, orchestrates purely in
      prose, and mutates queues ONLY via `cog queue-status-set` / `cog queue-append` (no parallel path).
- [ ] The skill commits via `/gc` when there is drift and no-ops (no commit) when there is none; it
      never edits recorded history of `done` items and fails closed on unrecoverable state.
- [ ] `docs/decisions/0011-plan-queue-revision-boundary.md` is written.
- [ ] No change to `plan-queue-runner/SKILL.md` this round.
- [ ] `just lint` and `just test` pass, including drift checks.
- [ ] This plan's `queue-rounds.yaml` shows round `plans-revision-mechanics` as `done`.

## Next Round

Round 3 (`runner-orchestration-integration`) rewrites `plan-queue-runner/SKILL.md` to drive the main
queue inline and invoke this `plans-revision` skill as a foreground subagent after every committed
item.
