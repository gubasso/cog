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

<!-- trigger-tests: "plans-revision", "plans-revision --repo-root <dir> --main-queue <path>" -->

# Plans Revision

Reconcile all implementation-plan queues and mutable plan files with the current repository state
after a committed plan-queue-runner item. This skill is adaptive and fail-closed: it updates remaining
work when the code has made parts obsolete, appends newly discovered gaps, and stops the parent runner
if it cannot reach a verified committed state.

## Inputs

`$ARGUMENTS` must provide `--repo-root <dir>` and `--main-queue <path>`. The main queue is the root
`.implementation-plans/queue-plans.yaml`. The skill must run with `$RUN_DIR` set so scan, verify, and
commit-output files can be written there.

## Cog Contract

All deterministic mechanics live in `cog`:

- Inventory and fingerprints: `cog plans-revision-scan --repo-root <repo> --main-queue <queue> <out.json>`.
- Verification: `cog plans-revision-verify --before <before.json> --after <after.json> <out.json>`.
- Status changes: `cog queue-status-set --queue <path> --schema <plans|rounds> --item <item> --from <status> --to <status> <out.json>`.
- New work: `cog queue-append --schema <plans|rounds> --queue <path> --item <item> --status <status> --prompt <prompt> [--depends-on csv] [--notes text] <out.json>`.
- Commit parsing: `cog plan-queue-runner-parse-commit <gc-output-file> --json`.

Never mutate a queue by direct editing. Use `queue-status-set` for guarded status flips and
`queue-append` for new items. Direct edits are allowed only for mutable `todo` or `backlog` plan and
round prose files.

## Workflow

1. Resolve `--repo-root` and `--main-queue` from `$ARGUMENTS`. If either is missing, return
   `STATUS: FAILED` and a concise reason. Do not guess.

2. Run the before scan into `$RUN_DIR/before.json` with `cog plans-revision-scan`. If scan fails,
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
   Do not reorder existing entries. Any new plan is a flat sibling directory under
   `.implementation-plans/plans/` (`plans/<slug>/`) wired via `depends_on` — never a nested
   directory. `cog plans-revision-scan` fails closed on any nested plan it inventories.

7. Run the after scan into `$RUN_DIR/after.json`, then verify with `cog plans-revision-verify` into
   `$RUN_DIR/verify.json`. If verification fails, return `STATUS: FAILED`; the parent runner must stop.

8. Read `$RUN_DIR/verify.json`. If `changed` is `false`, confirm the worktree is clean using the
   runner's normal read-only cleanliness check, then return exactly `STATUS: OK` and
   `RESULT: NO_DRIFT`.

9. If `changed` is `true`, run `/gc -a` in the foreground and capture its output in `$RUN_DIR/gc.out`.
   Never background commit work. Parse the captured output with `cog plan-queue-runner-parse-commit`.
   If parsing succeeds, return `STATUS: OK` and `RESULT: REVISION_COMMIT_OK <sha>` for a single repo,
   or the parsed multi-repo commit summary when multiple repos were committed.

10. If `/gc` fails, emits any `*_FAILED` result line, or cannot be parsed, return `STATUS: FAILED`.
    Do not select or start the next queue item.

## Guardrails

- Adaptive revision may change only remaining `todo` and `backlog` work.
- Plan directories are flat siblings under `plans/`; appended plans are never nested. The scan fails
  closed on any nested plan, so reconciliation stops rather than silently ignoring it.
- Completed history is immutable: never edit a `done` item's status, prompt, dependencies, notes, or
  recorded prose. The verify gate deterministically enforces this for the queue-YAML fields
  (status, prompt, depends_on, notes); the prose-file content of a `done` item is your responsibility
  to leave untouched (verify does not fingerprint it per item — see ADR-0012 "Verify Scope and
  Known Limitations").
- Mutate mutable items only through `cog queue-status-set` / `cog queue-append` (append-only, no
  reordering, no direct prompt/notes rewrite). Verify reports these changes but does not reject a
  hand-edit, so the discipline is yours to keep.
- `doing` is in-flight and not mutable during revision.
- No-drift is a no-op and must not create a commit.
- Drift must be committed through `/gc` before returning success.
- Foreground subagent depth spends one level from the fixed five-level budget.
