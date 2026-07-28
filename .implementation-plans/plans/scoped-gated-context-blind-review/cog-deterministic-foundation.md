# cog Deterministic Foundation: Rename, Scope, and Gate

> Plan: scoped-gated-context-blind-review | Round: 1 of 3 | Complexity: L | Generated: 2026-06-20 | Repo: /workspaces/cog

## Context

`runner-queue` runs an implementation-plan review boundary after every committed item. The boundary's deterministic mechanics live in `cog` commands: `review-implementation-plans-scan` (inventory + fingerprints), `review-implementation-plans-verify` (before/after diff), and the `queue-*` family. We are refactoring the boundary so the review skill becomes context-blind and **scoped** — between rounds it must analyze only one plan's `queue-rounds.yaml`; between plans it analyzes the whole tree — and so callers can cheaply decide, **without** spawning an LLM, whether anything changed.

This round delivers the pure-script foundation everything else builds on, with **no LLM behavior**: (1) rename the command family to `review-plan-implementation-plans-*` to match the skill's new name (`review-plan-implementation-plans`, landing in Round 2); (2) add an optional `--scope global|rounds` to scan plus scoped inventory/fingerprint helpers; (3) add a new deterministic `review-plan-implementation-plans-gate` command that emits a one-shot drift verdict; (4) migrate every reference across the repo; (5) rename/extend/add the bats suites. The **global** path must stay byte-identical so the runner main loop and existing tests are unaffected.

## Previous Rounds

This is the first round — no prior rounds.

## Scope of This Round

IN scope:

- Rename `review-implementation-plans-scan` / `-verify` commands, their modules, handlers, line-2 `desc:` sentinels, the helper file `fn_review_implementation_plans.sh`, and all `cog::fn::review_implementation_plans_*` functions to the `review_plan_implementation_plans_*` form.
- Add `--scope global|rounds` (default `global`) + `--queue <path>` to the scan command; add scoped inventory + scoped plan fingerprint helpers; add a defensive `before.scope == after.scope` assertion in verify.
- Add the new `review-plan-implementation-plans-gate` command (pure deterministic).
- Sweep every reference to the old command/helper names across `lib/`, `skills/`, `.claude/skills/`, `completions/`, `man/`, and `docs/` — purely mechanical token migration.
- Rename + extend the bats suites and add a new gate suite.

OUT of scope (Round 2+): rewriting the review skill body, `runner-queue` integration logic, the ADR, the golden rule, and the meta-tooling skills. This round only renames tokens in those prose files; it does not change their behavior.

## Current State

### Key Files

- `/workspaces/cog/lib/commands/cmd_review_implementation_plans_scan.sh` — `desc:` sentinel on line 2; handler `cog::cmd::review_implementation_plans_scan`. Builds JSON via `__cog_review_implementation_plans_scan_build_json` (lines ~32-57): resolves abs paths, calls `cog::fn::review_implementation_plans_inventory_json`, `..._repo_fingerprint`, `..._plans_fingerprint`, emits `{ok, repo_root, main_queue_path,
  repo_fingerprint, plans_fingerprint, queues[]}`. Self-check jq at lines 4-26 asserts field types (incl. `main_queue_path` is a non-empty absolute string).
- `/workspaces/cog/lib/commands/cmd_review_implementation_plans_verify.sh` — handler `cog::cmd::review_implementation_plans_verify`. Scan self-check jq at lines 4-26; verify self-check at lines 28-40 (`changed` boolean, `completed_history_preserved`, fingerprints, arrays, `graph_valid`). `.changed` computed by comparing before/after `plans_fingerprint` (lines ~105-109).
- `/workspaces/cog/lib/functions/fn_review_implementation_plans.sh` — `review_implementation_plans_queue_schema` (~27-55), `assert_flat` (~57-70), `__cog_review_implementation_plans_queue_json` (~72-97, enriches each item with `schema`, `queue_path`, `mutable`), `review_implementation_plans_inventory_json` (~99-130, globs main + `.implementation-plans/plans/*/queue-rounds.yaml`), `review_implementation_plans_repo_fingerprint` (~132-146, whole-repo sha256 excluding `.git`, `.implementation-plans`, caches), `review_implementation_plans_plans_fingerprint` (~148-163, sha256 of `.md/.yaml/.yml` under `.implementation-plans/`, excluding `*.tmp.*`).
- `/workspaces/cog/lib/functions/fn_refactor.sh` — `cog::fn::refactor_null_path_fingerprint` (~22-34): reads null-delimited paths on stdin, `cd` root, `LC_ALL=C sort -z`, `xargs -0 cat`, `sha256sum`. Reuse this for the scoped fingerprint.
- `/workspaces/cog/lib/functions/fn_queue.sh` — `cog::fn::queue_graph_check_items_json` (~214-274, pure-jq topo + dangling/cycles/blocked → `{ok, ..., dangling_refs, cycles, blocked,
  canonical_order}`) and `queue_graph_check_json` (~276-284). Reuse for the gate's graph check.
- Tests: `/workspaces/cog/test/integration/review_implementation_plans_scan.bats`, `.../review_implementation_plans_verify.bats`, plus the `queue_*` suites.
- Reference surface: `/workspaces/cog/completions/cog.bash`, `/workspaces/cog/man/cog.1.scd`, `/workspaces/cog/docs/reference/cli-commands.md`, and the help snapshots used by drift checks.

### Existing Patterns

- Command modules: `lib/commands/cmd_<slug_with_underscores>.sh`, handler `cog::cmd::<slug_with_underscores>`, mandatory line-2 `: 'desc: ...'` sentinel (root help, command reference, man summaries, and completion drift checks depend on it). User-facing names use dashes; the loader maps dashes to underscores.
- Shared helpers are `cog::fn::*` in `lib/functions/`.
- Every command supports `(<out.json>|--json)` output and `--help`.
- Determinism golden rule: deterministic routines belong in `cog`, never in skill prose.

## Implementation Steps

### First Step: Mark this round as started

In this plan's `queue-rounds.yaml`, set this round's (`item: cog-deterministic-foundation`) `status` to `doing`.

### Step 1: Rename the command + helper family

- Rename modules: `cmd_review_implementation_plans_scan.sh` → `cmd_review_plan_implementation_plans_scan.sh`; same for `_verify`. Rename handlers to `cog::cmd::review_plan_implementation_plans_scan` / `_verify` and update each line-2 `desc:` sentinel.
- Rename helper file `fn_review_implementation_plans.sh` → `fn_review_plan_implementation_plans.sh` and rename every `cog::fn::review_implementation_plans_*` function to `cog::fn::review_plan_implementation_plans_*` (and the private `__cog_review_implementation_plans_*` helpers in step).
- Update any loader/source lists that reference the old file name.
- Verify the loader resolves `cog review-plan-implementation-plans-scan` / `-verify` (dashes → underscores).

### Step 2: Add scoped inventory + scoped fingerprint helpers (siblings, not edits)

In `fn_review_plan_implementation_plans.sh`, add **new sibling** helpers — do not modify the existing global ones (the runner main loop and `runner-queue-resolve-plan` depend on them):

- `cog::fn::review_plan_implementation_plans_inventory_rounds_json(repo_root, rounds_queue)` — inventories exactly one `queue-rounds.yaml`: reuse the private per-queue JSON builder, assert `schema == rounds`, no glob, no main queue. Emit `{queues: [<single>]}`.
- `cog::fn::review_plan_implementation_plans_plan_fingerprint(repo_root, plan_dir)` — scoped plans fingerprint over `.implementation-plans/plans/<slug>/**` (`.md/.yaml/.yml`, exclude `*.tmp.*`), fed into `cog::fn::refactor_null_path_fingerprint "$repo_root"` so a file hashes identically scoped or global. Derive `plan_dir = dirname(--queue)`, `slug = basename`; fail-closed if `plan_dir` is not a direct child of `<repo>/.implementation-plans/plans/`.
- Code drift in rounds scope reuses the unchanged whole-repo `..._repo_fingerprint` (a round may touch code anywhere; sibling plan dirs are already pruned, so they never pollute the verdict).

### Step 3: Extend the scan command with `--scope`

In `cmd_review_plan_implementation_plans_scan.sh`:

- Add `--scope global|rounds` (default `global`) and `--queue <path>` (required iff `rounds`; forbid `--main-queue` in `rounds`). Fail-closed on missing/invalid combinations.
- `global` MUST call the **exact existing** build function with no behavioral branch — output stays byte-identical (regression-guarded by the "stable fingerprints" test).
- `rounds` builds JSON from the scoped inventory + scoped plans fingerprint + unchanged repo fingerprint. Emit additive fields `scope` and `scoped_queue_path`; keep `main_queue_path` present (set to the abs rounds-queue path) so the shared verify scan self-check (lines 4-26) still passes.
- Add `scope` (string `global|rounds`) to both self-check jq filters as an additive, non-breaking field where they are reused.

### Step 4: Add the deterministic gate command

Create `/workspaces/cog/lib/commands/cmd_review_plan_implementation_plans_gate.sh`, handler `cog::cmd::review_plan_implementation_plans_gate`, line-2 `: 'desc: Deterministic drift gate for implementation-plan review (no LLM).'`. Pure deterministic.

- Inputs: `--scope global|rounds` (default `global`), `--repo-root`, `--main-queue` (global) | `--queue` (rounds), `--baseline <scan.json>`, `(<out.json>|--json)`, `--help`.
- Validate `--baseline` with the shared scan self-check (fail-closed on a malformed baseline).
- Compute a fresh scan internally via the same builder (reuse, do not duplicate).
- Compute: `code_drift = repo_fingerprint(current) != repo_fingerprint(baseline)`; `plans_drift = plans_fingerprint(current) != plans_fingerprint(baseline)` (scoped in rounds); `graph_valid` by running `cog::fn::queue_graph_check_items_json` on each current queue and **reporting** (never dying) — `false` if any `.ok != true`.
- Emit `{ok, scope, drift, reasons[], graph_valid, repo_fingerprint, plans_fingerprint,
  baseline_repo_fingerprint, baseline_plans_fingerprint}` where `drift = code_drift || plans_drift || !graph_valid` and `reasons` ⊆ `["code_drift","plans_drift","graph_invalid"]`.

### Step 5: Add the verify scope-match assertion

In `cmd_review_plan_implementation_plans_verify.sh`, once `scope` is present in scan artifacts, add a defensive assertion that `before.scope == after.scope`; fail-closed otherwise. No other behavior change — `.changed` already derives from `plans_fingerprint`, which is the scoped fingerprint when fed scoped scans.

### Step 6: Repo-wide reference sweep

Migrate every `review-implementation-plans-scan` / `-verify` token (and the `cog::fn::` / `cog::cmd::` / file-name forms) to the new names across: `lib/`, `skills/claude/runner-queue/SKILL.md`, `.claude/skills/review-implementation-plans/SKILL.md` (Round 2 rewrites it, but keep it coherent now), `completions/cog.bash`, `man/cog.1.scd`, `docs/reference/cli-commands.md`, and any help snapshots. Add the new `review-plan-implementation-plans-gate` command to completions, the man page, and `cli-commands.md`. This is a pure token migration — no behavioral change to the prose.

### Step 7: Rename, extend, and add tests

- Rename `test/integration/review_implementation_plans_scan.bats` → `review_plan_implementation_plans_scan.bats` and `_verify.bats` similarly; update every invoked command name inside.
- Extend the scan suite: rounds scope emits exactly one queue + `scope=="rounds"` + a scoped `plans_fingerprint`; **isolation** (add a second plan dir to the fixture and assert it does not change the scoped fingerprint and is absent from `queues[]`); rounds forbids `--main-queue`; outside-tree `--queue` fails closed; **regression** — existing global tests pass unchanged with no `--scope` flag (default = global, byte-identical fingerprints).
- Extend the verify suite: a rounds-scoped before/after pair confines `.changed` and history-preservation to the one plan.
- Add `test/integration/review_plan_implementation_plans_gate.bats`: no-op → `drift==false`, `reasons==[]`; code-file change → `code_drift`; scoped plan-file change → `plans_drift`; dangling dep in the live queue → `graph_valid==false` + `graph_invalid` (gate reports, does not die); sibling-plan change in rounds scope → clean; malformed `--baseline` fails closed; `--help` dispatches.

### Final Step: Update the queue

In this plan's `queue-rounds.yaml`, set this round's (`item: cog-deterministic-foundation`) `status` to `done`.

## Acceptance Criteria

- [ ] `cog review-plan-implementation-plans-scan` and `-verify` exist and work; the old command names no longer resolve anywhere in `lib/`, `completions/`, `man/`, or `docs/`.
- [ ] `cog review-plan-implementation-plans-scan --scope rounds --queue <plan>/queue-rounds.yaml` inventories exactly that plan and emits a scoped `plans_fingerprint`; the global path output is byte-identical to before.
- [ ] `cog review-plan-implementation-plans-gate` returns `drift:false` on a no-op and `drift:true` with correct `reasons` for code / scoped-plan / graph-invalid changes, and never dies on an invalid graph.
- [ ] `just lint` and `just test` pass, including the renamed + extended + new gate suites and the global regression guard.
- [ ] This plan's `queue-rounds.yaml` shows round `cog-deterministic-foundation` as `done`.

## Next Round

Round 2 relocates and rewrites the review skill as a context-blind, scoped, gated, auto-applying tool built on these renamed commands and the new gate, rewires `runner-queue` to drive it per context, and lands the superseding ADR plus the caller-owns-context golden rule.
