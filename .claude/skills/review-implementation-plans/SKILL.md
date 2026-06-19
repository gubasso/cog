---
name: review-implementation-plans
description: >
  Reconcile implementation plans and queues with the current repository state
  after a committed runner-queue item, before selecting the next item, so
  remaining plans stay coherent with implemented code. Adaptive and fail-closed.
model: opus
effort: low
argument-hint: "--repo-root <dir> --main-queue <path>"
allowed-tools: Bash Read Edit Write Skill
disable-model-invocation: true
---

<!-- trigger-tests: "review-implementation-plans", "review-implementation-plans --repo-root <dir> --main-queue <path>" -->
<!-- cog-skill: plan-emitter -->

# Review Implementation Plans

Reconcile all implementation-plan queues and mutable plan files with the current repository state
after a committed runner-queue item. This skill is adaptive and fail-closed: it updates remaining
work when the code has made parts obsolete, appends newly discovered gaps, and stops the parent runner
if it cannot reach a verified committed state. Its Opus/low grade applies ADR-0013's no-Sonnet
model/effort policy.

## Phase 0: Plan-mode gate

<!-- cog-plan-mode-gate -->

This skill runs orchestrator-invoked by the runner (with `$RUN_DIR` set) and is never user-invoked
interactively, so this gate is a belt-and-suspenders guard. If — outside that runner flow — Claude
Code **plan mode** is active (a system-reminder says plan mode is on / that you must not make edits;
`Shift+Tab` or `/plan`), **STOP**: this skill mutates plan queues/files and cannot run read-only.
Tell the user to exit plan mode (`Shift+Tab`) and re-invoke; do not call `ExitPlanMode` yourself.
When invoked normally by the runner (`$RUN_DIR` set, not in plan mode), proceed.

## Inputs

`$ARGUMENTS` must provide `--repo-root <dir>` and `--main-queue <path>`. The main queue is the root
`.implementation-plans/queue-plans.yaml`. The skill must run with `$RUN_DIR` set so scan, verify, and
commit-output files can be written there.

## Cog Contract

All deterministic mechanics live in `cog`:

- Inventory and fingerprints: `cog review-implementation-plans-scan --repo-root <repo> --main-queue <queue> <out.json>`.
- Verification: `cog review-implementation-plans-verify --before <before.json> --after <after.json> <out.json>`.
- Status changes: `cog queue-status-set --queue <path> --schema <plans|rounds> --item <item> --from <status> --to <status> <out.json>`.
- New work: `cog queue-append --schema <plans|rounds> --queue <path> --item <item> --status <status> --prompt <prompt> [--depends-on csv] [--notes text] <out.json>`.
- Dependency changes: `cog queue-deps-set --queue <path> --schema <plans|rounds> --item <item> --depends-on <csv|""> [--expect <csv>] <out.json>`.
- Deterministic ordering: `cog queue-reorder --queue <path> --schema <plans|rounds> <out.json>`.
- Graph validation: `cog queue-graph-check --queue <path> --schema <plans|rounds> <out.json>`.
- Commit parsing: `cog runner-queue-parse-commit <gc-output-file> --json`.

Never mutate a queue by direct editing. Use `queue-status-set` for guarded status flips and
`queue-append` for new items. Use `queue-deps-set` for mutable dependency changes and
`queue-reorder` for physical ordering. Direct edits are allowed only for mutable `todo` or `backlog`
plan and round prose files.

## Workflow

1. Resolve `--repo-root` and `--main-queue` from `$ARGUMENTS`. If either is missing, return
   `STATUS: FAILED` and a concise reason. Do not guess.

2. Run the before scan into `$RUN_DIR/before.json` with `cog review-implementation-plans-scan`. If scan fails,
   return `STATUS: FAILED` and stop.

3. Inspect the before scan and the repository state. Consider only items whose scan entry has
   `mutable: true`, which means status `todo` or `backlog`. Treat `doing` and `done` items as recorded
   history for this revision pass.

4. For mutable items that are already implemented by the current code, mark them `done` only through
   `cog queue-status-set`, using the scanned `queue_path`, `schema`, `item`, current status as
   `--from`, and `done` as `--to`.

5. Revise remaining mutable plan or round prose files only when needed to keep future work coherent
   with the current code. Do not edit prompts, dependency lists, notes, or prose for items that were
   `done` in the before scan.

6. For newly found gaps, regressions, or follow-up work, append new queue entries only through
   `cog queue-append`. Use `plans` for new main-plan entries and `rounds` for inner plan rounds.
   Any new plan is a flat sibling directory under `.implementation-plans/plans/` (`plans/<slug>/`)
   wired via `depends_on` — never a nested directory. `cog review-implementation-plans-scan` fails
   closed on any nested plan it inventories.

7. Run the after scan into `$RUN_DIR/after.json`, then verify with `cog review-implementation-plans-verify` into
   `$RUN_DIR/verify.json`. If verification fails, return `STATUS: FAILED`; the parent runner must stop.

8. Read `$RUN_DIR/verify.json`. If reconciliation changed nothing, record `PLAN_REVIEW:
   NO_DRIFT`. If it changed work, run `/gc -a` in the foreground and capture its output in
   `$RUN_DIR/gc-plan-review.out`. Never background commit work. Parse the captured output with
   `cog runner-queue-parse-commit`; if parsing fails, return `STATUS: FAILED`.

9. Review queue execution order and dependencies for the main `plans` queue and each inner `rounds`
   queue. Apply model judgment only by changing `depends_on` for mutable (`todo`/`backlog`) items
   with `cog queue-deps-set`. Then run `cog queue-reorder` for each queue so physical order is derived
   deterministically from the dependency graph, followed by `cog queue-graph-check` for each queue.
   Never move or re-depend `done` or `doing` items.

10. Run another after scan into `$RUN_DIR/after-order.json`, then verify with
    `cog review-implementation-plans-verify` into `$RUN_DIR/verify-order.json`. If verification fails,
    return `STATUS: FAILED`.

11. Read `$RUN_DIR/verify-order.json`. If ordering review changed nothing, record `QUEUE_REVIEW:
    NO_DRIFT`. If it changed work, run `/gc -a` in the foreground and capture its output in
    `$RUN_DIR/gc-queue-review.out`. Parse it with `cog runner-queue-parse-commit`; if parsing fails,
    return `STATUS: FAILED`.

12. Return `STATUS: OK` and a `RESULT:` line that reports both phases: `NO_DRIFT` for any phase that
    changed nothing, or the parsed revision commit result for each phase that committed drift. Do not
    create empty commits.

13. If `/gc` fails, emits any `*_FAILED` result line, or cannot be parsed in either phase, return
    `STATUS: FAILED`.
    Do not select or start the next queue item.

## Guardrails

- Adaptive revision may change only remaining `todo` and `backlog` work.
- Plan directories are flat siblings under `plans/`; appended plans are never nested. The scan fails
  closed on any nested plan, so reconciliation stops rather than silently ignoring it.
- Completed and in-flight history is immutable: never edit a `done` or `doing` item's status,
  prompt, dependencies, notes, recorded prose, or physical position. The verify gate
  deterministically enforces this for the queue-YAML fields (status, prompt, depends_on, notes); the
  prose-file content of a `done` item is your responsibility to leave untouched (verify does not
  fingerprint it per item — see ADR-0012 "Verify Scope and Known Limitations").
- Mutate mutable items only through `cog queue-status-set`, `cog queue-append`,
  `cog queue-deps-set`, and `cog queue-reorder`. Re-depend mutable (`todo`/`backlog`) items only via
  `cog queue-deps-set` as model judgment; physical order is then derived deterministically by
  `cog queue-reorder` as a topological sort of `depends_on`. Never move or re-depend `done`/`doing`
  items, and never edit queue YAML directly.
- `doing` is in-flight and not mutable during revision.
- No-drift is a no-op and must not create a commit.
- Drift must be committed through `/gc` before returning success.
- Foreground subagent depth spends one level from the fixed five-level budget.
