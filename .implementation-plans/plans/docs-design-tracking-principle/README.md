# Docs-Design Principle: Tracking Files for Periodic Revalidation

> Complexity: S | Rounds: 1 | Generated: 2026-06-19 | Repo: /workspaces/cog (writes to $DOCS_NOTES_REPO)

## Problem Statement

Documentation and reference material frequently contain **perishable facts** — figures, benchmarks,
prices, API shapes, model rosters — that are correct when written but silently drift. There is no
general docs-design guidance capturing the pattern of a *tracking file*: a machine-readable registry
that records which artifacts need periodic re-research, how often, how to revalidate them, and what
depends on them, so that coding agents (the primary audience) and humans can flag and refresh stale
content during a normal codebase sweep.

The `cog` repo is building a concrete instance of this (the `repo-update-tracking` plan:
`docs/reference/maintenance-tracking.yaml` + `cog tracking-scan`). This plan generalizes that into a
reusable **docs-design principle** in the shared docs-design shelf at
`$DOCS_NOTES_REPO/tech/programming/docs-design/`, so any project can adopt it.

## Strategy

A single round adds one new principle file to the docs-design shelf, slotting into the existing
numbered sequence, and updates the shelf's index, AI-agent digest, and review checklist. It writes
**entirely outside the cog repo**, into `$DOCS_NOTES_REPO` (resolved on this machine to
`/home/gbasso/DocsNNotes`).

## Rounds

1. `tracking-file-doc-design-principle.md` — add the tracking-file/periodic-revalidation principle to the docs-design shelf + index/digest/checklist updates.

## Execution Commands

```bash
# Execute the next todo round (executor reads queue-rounds.yaml, runs the first todo round, then stops):
/prex -ar @.implementation-plans/plans/docs-design-tracking-principle/

# Or target the round file directly:
/prex -ar .implementation-plans/plans/docs-design-tracking-principle/tracking-file-doc-design-principle.md
```

## Execution Discipline

**Rounds must be executed one at a time.** Each round is a self-contained unit of work designed for
a single `/prex` session. Do not implement multiple rounds in one session.

When `/prex` is pointed at this directory or this `README.md`, it MUST:

1. Read this plan's `queue-rounds.yaml`.
2. Find the first round with status `todo`.
3. Set that round's `status` to `doing`, execute ONLY that round, then set it to `done` and stop.
4. End the session — a fresh `/prex` session is launched for any subsequent round.

## Decisions & Constraints

- `Executor: prex (EF 1.5)`.
- **Independent plan** (`depends_on: []`). It defines the general pattern that `repo-update-tracking`
  instantiates; it may run before or after that plan. It cites the cog instance as a worked example,
  so running it after `repo-update-tracking` lets it point at concrete files — but it does not
  require them.
- **Writes outside the cog repo**, into `$DOCS_NOTES_REPO/tech/programming/docs-design/`. The cog
  working tree is not modified by this plan (other than this `.implementation-plans/` plan metadata).
- Follow the docs-design shelf's existing conventions (numbered principle files, `AGENTS.md` digest
  with a last-synced date, `99-checklist.md`, `README.md` index).

## Rejected Alternatives

- **Document the pattern only inside `cog`.** Rejected: the user wants it as a reusable docs-design
  *principle* available to any project, with the cog tracker as one instance.
- **Fold it into an existing principle file (e.g. `04-single-source-of-truth.md`).** Rejected: it is
  a distinct, named pattern (perishability + revalidation cadence) worth its own file; it references
  SoT but is not the same concern.

## Risks & Edge Cases

- **`$DOCS_NOTES_REPO` unset or absent.** The round must resolve it first and stop with a clear
  message if missing — it cannot write the principle without the shelf.
- **Numbering collision** if the shelf gained files since this plan was written. The round picks the
  next free number before `99-checklist.md`.
- **Cross-repo commit.** The DocsNNotes change is committed in the DocsNNotes repo (the executor's
  `/gc` step handles satellite repos); the human reviews it separately.

## Completion

When the round is done, set it `done` in this plan's `queue-rounds.yaml` and set this plan `done` in
the top-level `.implementation-plans/queue-plans.yaml`. Nothing moves on disk.
