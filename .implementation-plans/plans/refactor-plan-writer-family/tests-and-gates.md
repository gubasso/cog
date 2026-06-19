# Update the test blast radius and run the quality gates

> Plan: refactor-plan-writer-family | Round: 5 of 5 | Complexity: L | Generated: 2026-06-19 |
> Repo: /workspaces/cog | Executor: prex (EF 1.5)

## Context

The queue rename and format change touch ~24 test references. Most tests use `QUEUE.yaml` as an
arbitrary temp/fixture path (the queue helpers are path-agnostic — naming hygiene), but two
integration test files assert the **literal product path** and MUST change. Pre-commit is the source
of truth for quality gates; this final round lands the test updates, sweeps for stale references, and
proves the whole change green via `just lint` and `just test`.

Do NOT touch any live `.implementation-plans/` data, including this plan's own `QUEUE.yaml`, except the
required status flips (see the plan README's "Scaffolding vs. deliverable").

## Previous Rounds

Round 1 rewrote the external spec; Round 2 renamed the cog mechanics; Round 3 rewrote the producer
skills (and removed the EF-sanity gate); Round 4 updated the consumer + docs + a superseding ADR. The
product now writes/reads `queue-plans.yaml` (root) and `queue-rounds.yaml` (inner); the tests must
assert the new names and the repo must be free of stale references.

## Scope of This Round

- **IN scope:** update test files that reference `QUEUE.yaml`, fix the literal-assertion tests, run a
  stale-reference sweep across the repo, run the lint + test gates, and resolve any failures
  introduced by Rounds 1–4.
- **OUT of scope:** live `.implementation-plans/` data (migrated manually by the user) and the
  external satellite repo (handled in Round 1).

## Current State

### Key Files (test blast radius — 24 references)

**Literal-assertion tests (HARD requirements):**

- `/workspaces/cog/test/integration/plan_init.bats` — asserts the literal
  `.implementation-plans/QUEUE.yaml` at lines ~20, 25, 37 (e.g. `grep -F "plans: []"
  "${repo}/.implementation-plans/QUEUE.yaml"` and `.queue_path | endswith(".implementation-plans/QUEUE.yaml")`).
  MUST become `queue-plans.yaml`.
- `/workspaces/cog/test/integration/plan_queue_runner_setup.bats` — writes `repo/plan/QUEUE.yaml` and
  asserts the resolved `queue_path` ends with `/plan/QUEUE.yaml` (lines ~17, 31, 40). MUST become
  `queue-rounds.yaml` (write `repo/plan/queue-rounds.yaml`; assert `endswith("/plan/queue-rounds.yaml")`).

**Fixture-path tests (naming hygiene — helpers are path-agnostic; update for consistency with the
schema each exercises):**

- `/workspaces/cog/test/unit/queue.bats` (uses `plans/QUEUE.yaml` and `rounds/QUEUE.yaml` →
  `plans/queue-plans.yaml`, `rounds/queue-rounds.yaml`; and bare `QUEUE.yaml` fixtures).
- `/workspaces/cog/test/unit/cmd_queue_select.bats`
- `/workspaces/cog/test/unit/cmd_queue_append.bats`
- `/workspaces/cog/test/integration/queue_bootstrap.bats`
- `/workspaces/cog/test/integration/queue_select.bats`
- `/workspaces/cog/test/integration/queue_append.bats`

### Existing Patterns

- Tests are `bats`; queue assertions use `yq`. `just lint` = `pre-commit run --all-files`; `just test`
  = the unit hook + the integration hook. `test-live` / `test-e2e` are manual-stage hooks (not run
  here). **Run no git commands.**

## Implementation Steps

### First Step: Mark this round as started

In this plan's `QUEUE.yaml`, set this round's (`item: tests-and-gates`) `status` to `doing`.

### Step 1: Fix the literal-assertion integration tests

- `plan_init.bats`: change every asserted root-queue path to `.implementation-plans/queue-plans.yaml`.
- `plan_queue_runner_setup.bats`: change the written fixture and the resolved-path assertion to
  `queue-rounds.yaml` (e.g., write `repo/plan/queue-rounds.yaml`; assert `queue_path` ends with
  `/plan/queue-rounds.yaml`).

### Step 2: Update the fixture-path tests for consistency

- In the six unit/integration queue tests, rename fixture queue paths to `queue-plans.yaml`
  (plans-schema fixtures) and `queue-rounds.yaml` (rounds-schema fixtures), matching the schema each
  test exercises. Generic single-queue fixtures may use either; prefer the schema-matching name.

### Step 3: Stale-reference sweep across the repo

- Grep `/workspaces/cog` (EXCLUDING `.implementation-plans/` live data and `.git/`) for stragglers and
  fix any product/skill/doc/test references:
  ```text
  QUEUE.yaml
  plans/<slug>.md
  Template E
  single-file
  single self-contained markdown file
  max rounds
  4+ rounds under prex
  XL is unreachable
  ```
- Classify each remaining hit as either intentionally historical (e.g., a superseded-ADR body, or the
  legacy `.plan/` migration note updated in Round 1) or stale product text. Fix stale product text;
  leave intentional history.
- Confirm no command-reference / man-page / completion drift was introduced: the changes rename
  behavior but add/remove no commands, so the line-2 `: 'desc: ...'` sentinels and the command set are
  unchanged. If `just lint` includes a man-page-sync or completion-drift hook, ensure it passes (Step 4).

### Step 4: Run the quality gates

- Run `cog skill-lint` on each skill touched in Rounds 3–4
  (`skills/claude/plan-writer/SKILL.md`, `skills/codex/plan-writer/SKILL.md`,
  `skills/claude/plan-writer-multi/SKILL.md`, `skills/claude/plan-queue-runner/SKILL.md`).
- Run `just lint` (pre-commit, all files) and `just test` (unit + integration). Resolve any failures
  surfaced by Rounds 1–4 (skill-lint, markdownlint MD040, bats assertions). The change is complete
  only when both are green. If a gate fails for a pre-existing, unrelated reason, capture the exact
  failure and run the most focused fallback covering the changed behavior, and record it in the round
  summary.

### Final Step: Update the queue

1. In this plan's `QUEUE.yaml`, set this round's (`item: tests-and-gates`) `status` to `done`.
2. All rounds are now done, so in the top-level `.implementation-plans/QUEUE.yaml` set this plan's
   (`item: refactor-plan-writer-family`) `status` to `done`. Leave the plan directory in place —
   nothing moves on disk.

## Acceptance Criteria

- [ ] `plan_init.bats` asserts `queue-plans.yaml`; `plan_queue_runner_setup.bats` asserts
      `queue-rounds.yaml`.
- [ ] No `QUEUE.yaml` reference remains in product code, skills, cog docs, or tests (live
      `.implementation-plans/` data and intentional history excluded).
- [ ] No stale `single-file` / `Template E` / `max rounds` / `4+ rounds under prex` product text
      remains.
- [ ] `cog skill-lint` passes for the touched skills; `just lint` and `just test` both pass (or
      documented focused fallback for any pre-existing unrelated failure).
- [ ] This plan's `QUEUE.yaml` shows round `tests-and-gates` as `done`.
- [ ] The top-level `.implementation-plans/QUEUE.yaml` shows this plan as `done`.

## Next Round

This is the final round.
