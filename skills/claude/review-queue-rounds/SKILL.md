---
name: review-queue-rounds
description: >
  Run the queue-rounds revision boundary after a committed queue item: scan the
  plan vault before and after boundary edits, reconcile remaining plan/queue drift
  with the current code, verify the allowed drift, and commit it through /gc. Use
  when a runner reaches its revision boundary.
model: opus
effort: low
argument-hint: "--repo-root <dir> --main-queue <path>"
disable-model-invocation: true
allowed-tools: Bash Read Edit Write Skill
---

<!-- trigger-tests: "review-queue-rounds", "run the revision boundary", "reconcile plan drift" -->
<!-- cog-terminal-contract: STATUS -->

# Review Queue Rounds

Reconcile the resolved plan vault's queues and mutable plan files with the current repository state
after a committed queue item, before the parent runner selects the next item. This boundary is adaptive
and fail-closed: it marks finished mutable work done, revises remaining work the code has made obsolete,
appends newly discovered gaps, and stops the runner if it cannot reach a verified committed state.

## Inputs

`$ARGUMENTS` provides `--repo-root <dir>` and `--main-queue <path>`, where the main queue is the plan
vault's top-level `queue-plans.yaml` (local or global store). An optional `RUN_DIR` hint names an
existing scratch directory.

## Scratch

Obtain a run directory and keep every scan, verify, and commit-output artifact under it:

```bash
RUN_DIR="${RUN_DIR:-$(cog rundir review-queue-rounds)}"
```

## Vault resolution

Resolve the vault identically to the runners, so this boundary sees the same `plan_root` and
`main_queue` regardless of store scope:

```bash
cog plan runner-resolve --target "$MAIN_QUEUE" --json > "$RUN_DIR/runner-resolve.json"
```

Read `.plan_root` and `.main_queue` from that file.

## Cog contract

All deterministic mechanics live in `cog`:

- Inventory and fingerprints: `cog review-queue-rounds-scan --repo-root <repo> --main-queue <queue> [--plan-root <dir>] <out.json>`.
- Verification: `cog review-queue-rounds-verify --before <before-scan.json> --after <after-scan.json> <out.json>`.
- Status changes: `cog queue-status-set --queue <path> --schema <plans|rounds> --item <item> --from <status> --to <status> <out.json>`.
- New work: `cog queue-append --schema <plans|rounds> --queue <path> --item <item> --status <status> --prompt <prompt> [--depends-on csv] [--notes text] <out.json>`.
- Dependency changes: `cog queue-deps-set --queue <path> --schema <plans|rounds> --item <item> --depends-on <csv|""> [--expect <csv>] <out.json>`.
- Deterministic ordering: `cog queue-reorder --queue <path> --schema <plans|rounds> <out.json>`.
- Graph validation: `cog queue-graph-check --queue <path> --schema <plans|rounds> <out.json>`.
- Commit parsing: `cog runner-commit-parse <gc-output-file> --json`.

Mutate queues only through those verbs — `queue-status-set` for guarded status flips, `queue-append`
for new items, `queue-deps-set` for dependency edits, `queue-reorder` for physical ordering. Direct
prose edits apply only to mutable `todo` or `backlog` plan and round bodies.

## Workflow

1. Resolve `--repo-root` and `--main-queue` from `$ARGUMENTS`. If either is missing, return
   `STATUS: FAILED` with a concise reason.

2. Run the before scan into `$RUN_DIR/before-scan.json` with `cog review-queue-rounds-scan`. On scan
   failure, return `STATUS: FAILED` and stop.

3. Inspect the before scan and the repository state. Act only on items whose scan entry has
   `mutable: true` (status `todo` or `backlog`). Treat `doing` and `done` items as recorded history
   for this revision pass.

4. For mutable items already implemented by the current code, mark them `done` through
   `cog queue-status-set`, using the scanned `queue_path`, `schema`, `item`, current status as
   `--from`, and `done` as `--to`.

5. Revise remaining mutable plan or round bodies when needed to keep future work coherent with the
   current code. Leave `done` items' prompts, dependencies, notes, and prose as they were in the
   before scan.

6. For newly found gaps, regressions, or follow-up work, append entries through `cog queue-append` —
   `plans` for new main-plan entries, `rounds` for inner plan rounds. Every new plan is a flat sibling
   directory under `<PLAN_ROOT>/plans/` (`plans/<slug>/`) wired via `depends_on`. The scan fails closed
   on any nested plan it inventories.

7. Run the after scan into `$RUN_DIR/after-scan.json`, then verify with `cog review-queue-rounds-verify`
   into `$RUN_DIR/verify.json`. On verification failure, return `STATUS: FAILED`; the runner stops.

8. Read `$RUN_DIR/verify.json`. If reconciliation changed nothing, record `PLAN_REVIEW: NO_DRIFT`. If
   it changed work, run `/gc -a` in the foreground (the only commit authority) and capture its output
   in `$RUN_DIR/reconcile-commit.out`. Parse it with `cog runner-commit-parse`; on parse failure,
   return `STATUS: FAILED`.

9. Review execution order and dependencies for the main `plans` queue and each inner `rounds` queue.
   Apply judgment only by changing `depends_on` for mutable items via `cog queue-deps-set`, then run
   `cog queue-reorder` per queue so physical order is derived deterministically from the dependency
   graph, followed by `cog queue-graph-check` per queue. Leave `done` and `doing` items in place.

10. Run another after scan into `$RUN_DIR/after-order-scan.json`, then verify with
    `cog review-queue-rounds-verify` into `$RUN_DIR/verify-order.json`. On verification failure, return
    `STATUS: FAILED`.

11. Read `$RUN_DIR/verify-order.json`. If ordering review changed nothing, record `QUEUE_REVIEW:
    NO_DRIFT`. If it changed work, run `/gc -a` in the foreground and capture its output in
    `$RUN_DIR/order-commit.out`. Parse it with `cog runner-commit-parse`; on parse failure, return
    `STATUS: FAILED`.

12. Return `STATUS: OK` with a `RESULT:` line reporting both phases: `NO_DRIFT` for any phase that
    changed nothing, or the parsed revision commit result for each phase that committed drift, plus the
    before/after scan, verify, and commit-parse artifact paths.

13. On any `/gc` failure, `*_FAILED` result line, or unparseable commit output in either phase, return
    `STATUS: FAILED` and leave the next queue item unselected.

## Guardrails

- Adaptive revision changes only remaining `todo` and `backlog` work.
- Plan directories are flat siblings under `<PLAN_ROOT>/plans/`; appended plans stay flat. The scan
  fails closed on any nested plan, so reconciliation stops rather than silently ignoring it.
- Completed and in-flight history is immutable: a `done` or `doing` item keeps its status, prompt,
  dependencies, notes, recorded prose, and physical position. The verify gate enforces this for the
  queue-YAML fields (status, prompt, depends_on, notes); the prose-file content of a `done` item stays
  untouched (verify does not fingerprint it per item — see ADR-0012 "Verify Scope and Known
  Limitations").
- No-drift is a no-op and creates no commit; drift is committed through `/gc` before returning success.
- A foreground subagent depth spends one level from the fixed five-level budget.
- Describe only the structural queue/vault input contract; the boundary is blind to which skill
  produced the vault.
