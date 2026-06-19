# Rename queue files in cog deterministic mechanics

> Plan: refactor-plan-writer-family | Round: 2 of 6 | Complexity: L | Generated: 2026-06-19 |
> Repo: /workspaces/cog | Executor: prex (EF 1.5)

## Context

`cog` owns the deterministic plan/queue mechanics that the skills delegate to (ADR 0008). The hard
queue rename (root `QUEUE.yaml` → `queue-plans.yaml`; inner `QUEUE.yaml` → `queue-rounds.yaml`) must
be applied to the cog code that hardcodes the literal filename. The queue schema machinery in
`lib/functions/fn_queue.sh` is mostly filename-AGNOSTIC — the queue PATH is passed as an argument to
`queue-bootstrap` / `queue-append` / `queue-select` — so this round is small and surgical: update the
two hardcoded callers, generalize the user-facing error strings, and extend the reserved-slug guard
for the new meta stems. **No dual-read shim** (hard cut, Q4).

**CAUTION — self-reference hazard.** This round runs via `/prex` (and possibly `/runner-queue`),
which read THIS plan's own live `.implementation-plans/.../queue-rounds.yaml`. Do **NOT** rename or move this
plan's own queue/status files or the live root ledger — only edit cog's *code*. See the plan README's
"Scaffolding vs. deliverable". The user migrates live on-disk plan data manually (Q4).

## Previous Rounds

Round 1 rewrote the external spec (`/home/gbasso/DocsNNotes/.../plan-rounds/`) so it describes
directory-only plans, the two-layer model, uncapped rounds, and the new queue filenames
`queue-plans.yaml` (root) / `queue-rounds.yaml` (inner), and extended the spec's reserved-slug list to
cover `queue-plans` / `queue-rounds`. The cog code must now match those filenames.

## Scope of This Round

- **IN scope:** rename the hardcoded `QUEUE.yaml` literals and generalize error strings in cog
  commands/functions, and extend the reserved-slug guard.
- **OUT of scope:** skill prose (Round 3), the consumer `runner-queue` skill + cog docs
  (Round 4), tests (Round 5), and any live `.implementation-plans/` data.

## Current State

### Key Files

- `/workspaces/cog/lib/commands/cmd_plan_init.sh` — bootstraps the root. **Hardcodes** the root queue
  at line 44: `root_queue="${plan_root}/QUEUE.yaml"`. The embedded root-README writer
  `__cog_plan_init_write_root_readme()` prints (lines ~25–30):
  - `` `QUEUE.yaml` is the source of truth for plan status, order, dependencies, and execution prompts. ``
  - `` Plans live under `plans/` as either a single self-contained markdown file or a directory containing ``
  - `` round files and an inner `QUEUE.yaml`. ``
  All three lines change: filenames → `queue-plans.yaml` (root) / `queue-rounds.yaml` (inner), and the
  "either a single self-contained markdown file or a directory" text → "every plan is a directory
  containing round files and an inner `queue-rounds.yaml`".
- `/workspaces/cog/lib/commands/cmd_runner_queue_setup.sh` — resolves the inner queue path.
  **Hardcodes** the inner filename in path resolution (lines ~86–87):
  ```text
  */QUEUE.yaml) queue_path="$target" ;;
  *) queue_path="${target}/QUEUE.yaml" ;;
  ```
  and references `QUEUE.yaml` in the not-found error (~line 91) and the too-many-targets / usage hint
  (~line 50, e.g. "pass exactly one plan dir or QUEUE.yaml path"). All become `queue-rounds.yaml`.
- `/workspaces/cog/lib/functions/fn_queue.sh` — schema machinery is filename-agnostic, BUT the
  user-facing error strings literally say `QUEUE.yaml` (in `cog::fn::queue_validate_file`, lines ~94,
  97, 101): "QUEUE.yaml not found", "QUEUE.yaml does not parse", "QUEUE.yaml has invalid top-level
  shape". This single function validates BOTH the `plans` and `rounds` flavors, so the messages must
  be **generic** (e.g., "queue file not found / does not parse / has invalid top-level shape"),
  keeping the `path: ${queue_path}` field for specificity.
- `/workspaces/cog/lib/commands/cmd_plan_slug.sh` — the reserved-slug guard. It rejects `readme`,
  `queue`, `strategy` (case-insensitive). New meta filename stems are `queue-plans` / `queue-rounds`.
  Extend the reserved set so a plan slug OR a round topic cannot collide with the new meta files.
  Recommended final set: `readme`, `strategy`, `queue`, `queue-plans`, `queue-rounds` (keep bare
  `queue` as a safety alias). The `__cog_plan_slug_self_check` JSON contract and the `reserved` /
  `reason` output shape stay the same.

### Existing Patterns

- Command handlers are `cog::cmd::<slug>`; shared helpers are `cog::fn::*`. Keep mechanics
  deterministic and DRY (ADR 0008). The command name → handler mapping is derived by the loader.
- Error raising uses `cog::fn::error_raise` / `cog::helpers::die` with structured fields.
- Every command module keeps its line-2 `: 'desc: ...'` sentinel (help / man / completion depend on
  it) — do not disturb it.

## Implementation Steps

### First Step: Mark this round as started

In this plan's `queue-rounds.yaml`, set this round's (`item: cog-mechanics-rename`) `status` to `doing`.

### Step 1: Rename the root queue in `cmd_plan_init.sh`

- Change line 44: `root_queue="${plan_root}/QUEUE.yaml"` → `root_queue="${plan_root}/queue-plans.yaml"`.
- In `__cog_plan_init_write_root_readme()`, update the three printed lines: the queue-name line →
  `` `queue-plans.yaml` is the source of truth ... ``; the "either a single self-contained markdown
  file or a directory" line → "every plan is a directory"; the inner-queue line → "round files and an
  inner `queue-rounds.yaml`".
- Note: `cog::fn::queue_bootstrap_file` / `queue_validate_file` are called with `$root_queue`, so they
  follow the new path automatically.

### Step 2: Rename the inner queue resolution in `cmd_runner_queue_setup.sh`

- Change the path-resolution case to match `*/queue-rounds.yaml` and default to
  `"${target}/queue-rounds.yaml"`. Update the not-found error and the usage/too-many-targets hint to
  `queue-rounds.yaml`.

### Step 3: Generalize the error strings in `fn_queue.sh`

- In `cog::fn::queue_validate_file`, replace the literal `QUEUE.yaml` in the not-found / does-not-parse
  / invalid-top-level-shape messages with generic wording ("queue file …") so the same function
  serves both `queue-plans.yaml` and `queue-rounds.yaml`. Keep the `path: ${queue_path}` detail.

### Step 4: Extend the reserved-slug guard in `cmd_plan_slug.sh`

- Extend the reserved `case` to also reject `queue-plans` and `queue-rounds` (keep `readme`,
  `strategy`, and `queue`). Ensure both plan slugs and round topics are guarded (the same helper
  validates both).

### Step 5: Smoke-check the renamed mechanics

- `cog plan-init --repo-root "$(mktemp -d)" --json` should report a `queue_path` ending in
  `queue-plans.yaml` and create it.
- `cog plan-slug --text "queue plans" --json` and `--text "queue rounds"` should report
  `reserved: true`.
- (Do NOT run any git commands; do NOT touch this plan's own live queue.)

### Final Step: Update the queue

1. In this plan's `queue-rounds.yaml`, set this round's (`item: cog-mechanics-rename`) `status` to `done`.

## Acceptance Criteria

- [ ] `cog plan-init` writes `queue-plans.yaml` at the plan root and the generated README text says
      every plan is a directory (no "single self-contained markdown file" wording).
- [ ] `cog runner-queue-setup` resolves `queue-rounds.yaml` for both a bare plan-dir target and
      an explicit `.../queue-rounds.yaml` path.
- [ ] No `QUEUE.yaml` literal remains in `cmd_plan_init.sh`, `cmd_runner_queue_setup.sh`, or the
      `fn_queue.sh` error strings.
- [ ] `cog plan-slug` rejects `queue-plans` and `queue-rounds` (plus `readme`, `queue`, `strategy`).
- [ ] No command module's line-2 `: 'desc: ...'` sentinel was disturbed.
- [ ] This plan's `queue-rounds.yaml` shows round `cog-mechanics-rename` as `done`.

## Next Round

Round 3 rewrites the producer skills (`plan-writer`, the Codex twin, `plan-writer-multi`) to the
directory-always / uncapped / two-layer model and the new filenames, delegating to the now-renamed cog
mechanics — and removes the `plan-writer-multi` EF-sanity gate that auto-rejects 4+ prex rounds.
