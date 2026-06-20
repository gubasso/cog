# Plan Lifecycle & Executor Model

Shared specification for skills that produce implementation plans. Every plan is a directory of
self-contained round files, and each round is sized for execution by a single `/prex` run.

The `.implementation-plans/` tree is **flat and queue-driven**: a plan's status, order,
dependencies, and execution command live in YAML queue files — never in directory or file names.
There are no kanban state-directories and no numeric prefixes.

## Directory structure

```text
<repo-root>/.implementation-plans/
├── README.md                    static explainer of the plan system (bootstrapped once)
├── queue-plans.yaml             top-level source of truth: every plan + status
└── plans/
    └── <slug>/                  one directory per plan
        ├── README.md            overview, strategy, decisions, rejected alternatives
        ├── STRATEGY.md          (XL plans only) architecture, dep graph, cross-cutting concerns
        ├── queue-rounds.yaml    this plan's rounds, in execution order
        ├── <topic>.md           a round — self-contained task description (no number prefix)
        └── <topic>.md           another round
```

Every plan is a directory (`plans/<slug>/`). The complexity grade is descriptive; it does not select
a format or cap round count.

**Plan directories are always direct children of `plans/` and are never nested.** There is exactly
one level under `plans/` — `plans/<slug>/`. Never place a plan directory inside another plan
directory, and never create subdirectories within a plan directory (round files are flat
`<topic>.md` files in the plan dir). All relationships and ordering between plans are expressed
**only** through the `depends_on` field in `queue-plans.yaml`, never through the filesystem; a
shared slug prefix is a naming convention, not a parent directory.

Planning uses two layers (see `complexity-heuristic.md` § "Two-layer decomposition"). Layer 1 splits
work by domain or scope into one or more flat sibling plan dirs under `plans/`, related through the
top-level `queue-plans.yaml` `depends_on` field. Layer 2 grades each dir and splits it into uncapped
rounds in that dir's `queue-rounds.yaml`.

The root `README.md` and `queue-plans.yaml` are bootstrapped by the generating skill the first time
it runs in a repo: `README.md` from its template (never overwritten afterwards), `queue-plans.yaml`
with an empty `plans:` list.

Whether `.implementation-plans/` is committed or gitignored is the **host repo's** choice — some
repos track plans as part of their history, others ignore them. The generating skill must not assume
one or modify `.gitignore`.

## Slug conventions

- 3–5 word lowercase slug derived from the plan orientation/goal.
- Characters: `[a-z0-9-]` only. Maximum 60 characters.
- Example: `refactor-auth-middleware`, `add-batch-export-api`.
- Round files use the same convention for their `<topic>` slug. **No `NN-` number prefix** — round
  order is defined by the order of entries in the plan's `queue-rounds.yaml`.
- The slugs `readme`, `strategy`, `queue`, `queue-plans`, and `queue-rounds` (case-insensitive) are
  **reserved** for both plan slugs and round topics — they collide with the meta files (`README.md`,
  `queue-plans.yaml`, `queue-rounds.yaml`, `STRATEGY.md`).

## The queues are the source of truth

`status` is one of: `backlog | todo | doing | done`.

- **`.implementation-plans/queue-plans.yaml`** is the repo-wide ledger. It lists _every_ plan (full
  ledger — completed plans stay, as `status: done`). Each entry: `item` (a `<slug>` dir), `status`,
  `depends_on` (list of other `item`s), `prompt` (exact execution command), `notes` (free-form).
  Entry order reflects execution priority: active items first, then backlog, then done.
- **`plans/<slug>/queue-rounds.yaml`** lists that plan's `rounds:` in execution order. Each round
  entry has the same fields, with `item` = the round's `<topic>` and `prompt` =
  `/prex -ar .implementation-plans/plans/<slug>/<topic>.md`.

**Every queue entry — both levels — carries a `prompt` field.**

## Round file contract

Each round file (`<topic>.md`) is a **self-contained task description** designed to be consumed
directly by `/prex -ar <path>` or included via `@` in `/prex -ar @<plan-dir>/`.

Self-containment rules:

- Contains the full problem statement and motivation — no "see the conversation" or "as discussed."
- Includes all code references (absolute paths, relevant excerpts) needed for THIS round.
- Describes what previous rounds produced (expected state) without requiring the executor to read
  those round files.
- Specifies what is in scope and out of scope for this round.
- Has its own acceptance criteria, independently verifiable.

## Executor capacity model

Rounds are sized against the capabilities of a single `/prex` run:

- **Codex timeout**: 600 seconds per stage (planning and implementation). A round must describe work
  completable within this window.
- **Single write session**: Codex implements in one continuous session. The round must be cohesive —
  changes that require iterative feedback loops across sessions should be separate rounds.
- **Quality threshold**: Quality degrades when a single prex run handles multiple loosely-related
  changes. Each round should address one cohesive chunk of work (one feature, one module refactor,
  one layer of the stack).
- **Practical sizing**: A well-scoped round delivers one coherent feature or architectural layer.
  File count is incidental — mechanically-coupled changes belong together regardless of count. A
  round description usually fits in under 300 lines of plan text.

## Lifecycle rules

1. **Generation**: The planning skill bootstraps the root (`README.md`, `queue-plans.yaml`) if
   missing, writes the plan as `plans/<slug>/` (`README.md`, round files, inner `queue-rounds.yaml`,
   `STRATEGY.md` for XL), and registers the plan in the top-level
   `.implementation-plans/queue-plans.yaml`. It never executes rounds.
2. **Execution**: Rounds are executed **one at a time**, each in its own `/prex -ar` session. When
   handed the plan directory or its `README.md`, the executor reads the plan's `queue-rounds.yaml`,
   runs the first round whose status is `todo`, then stops. When starting a round it sets that
   round's `status: doing`; after completing it, `status: done` — a crashed or interrupted session
   thus leaves a visible `doing` marker. Never batch multiple rounds into a single session — each
   round is a self-contained unit sized for one `/prex` run.
3. **Completion**: After all rounds are done, set the plan's `status: done` in the top-level
   `.implementation-plans/queue-plans.yaml`. **Nothing moves on disk** — the plan directory stays
   where it is. Status, not path, records the lifecycle state.

## `README.md` and queue file roles

- **`plans/<slug>/queue-rounds.yaml`** is the machine-readable source of truth for round order and
  status.
- **`plans/<slug>/README.md`** is the human-facing index and decision record: problem statement,
  strategy, execution commands (exact `/prex` invocations), architectural decisions, and rejected
  alternatives. It mirrors the queue for readers but must not become a competing source of truth for
  status — when in doubt, the `queue-rounds.yaml` wins.
- **`.implementation-plans/README.md`** (root) is a static explainer of the whole system —
  structure, queue semantics, execution discipline. It carries no per-plan state.

## Migrating a legacy `.plan/` tree

Earlier versions of this spec used `<repo-root>/.plan/` with underscore-prefixed meta files.
Migration is manual:

1. `git mv .plan .implementation-plans` (or plain `mv` if untracked).
2. `mkdir .implementation-plans/plans` and move every `<slug>/` dir into it.
3. Rename meta files: `_QUEUE.yaml` → `queue-plans.yaml` at the root and `queue-rounds.yaml` inside
   plan dirs; `_README.md` → `README.md` at both levels.
4. Rewrite every `prompt:` field to the new paths
   (`/prex -ar .implementation-plans/plans/<slug>/<topic>.md`, etc.).
5. Bootstrap the root `README.md` from the template on the next generating-skill run (or copy it
   manually).

The generating skill detects a legacy `.plan/` dir and informs the user, but never migrates
automatically.
