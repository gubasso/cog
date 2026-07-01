# Plan Lifecycle & Executor Routing

Shared specification for skills that produce implementation plans. Every plan is a directory of
self-contained round files, and each round is sized for one **single execution session**. Complexity
is executor-independent (`complexity-rubric.md`); the executor that runs a round is chosen downstream
and stamped into the round's queue `prompt:` ([ADR-0056](../../docs/decisions/0056-plan-round-executor-routing-contract.md)),
never baked into sizing.

Producers resolve the plan store through `cog plan project resolve` / `cog plan new` / `cog plan path`
and never hardcode `.implementation-plans/` ([ADR-0057](../../docs/decisions/0057-plan-vault-producer-retarget-and-global-git.md)).
The vault tree is **flat and queue-driven**: a plan's status, order, dependencies, and execution
command live in YAML queue files — never in directory or file names. There are no kanban
state-directories and no numeric prefixes.

## Directory structure

The plan root is whatever `cog plan project resolve` returns (`plan_root`); the structure under it is:

```text
<plan-root>/
├── README.md                    static explainer of the plan system (bootstrapped once)
├── queue-plans.yaml             top-level source of truth: every plan + status
└── plans/
    └── <slug>/                  one directory per plan
        ├── README.md            overview, strategy, decisions, rejected alternatives
        ├── STRATEGY.md          (very large plans only) architecture, dep graph, cross-cutting concerns
        ├── queue-rounds.yaml    this plan's rounds, in execution order
        └── rounds/
            └── <topic>.md       a round — self-contained task description (no number prefix)
```

Every plan is a directory (`plans/<slug>/`); round files live under its `rounds/` subdir
([ADR-0048](../../docs/decisions/0048-plan-vault-storage-and-resolution.md)). The complexity grade is
descriptive; it does not select a format or cap round count.

**Plan directories are always direct children of `plans/` and are never nested.** There is exactly
one level under `plans/` — `plans/<slug>/`. Never place a plan directory inside another plan
directory. All relationships and ordering between plans are expressed **only** through the
`depends_on` field in `queue-plans.yaml`, never through the filesystem; a shared slug prefix is a
naming convention, not a parent directory.

Right-sizing uses the recursive loop in `round-splitting-contract.md` and
[ADR-0050](../../docs/decisions/0050-recursive-round-right-sizing.md): grade against
`complexity-rubric.md`, and split any over-ceiling round into information-preserving children until
every round fits the single-session ceiling.

The root `README.md` and `queue-plans.yaml` are bootstrapped by the generating skill the first time
it runs against a store: `README.md` from its template (never overwritten afterwards),
`queue-plans.yaml` with an empty `plans:` list.

## Slug conventions

- 3–5 word lowercase slug derived from the plan orientation/goal.
- Characters: `[a-z0-9-]` only. Maximum 60 characters.
- Example: `refactor-auth-middleware`, `add-batch-export-api`.
- Round files use the same convention for their `<topic>` slug. **No `NN-` number prefix** — round
  order is defined by the order of entries in the plan's `queue-rounds.yaml`.
- The slugs `readme`, `strategy`, `queue`, `queue-plans`, and `queue-rounds` (case-insensitive) are
  **reserved** for both plan slugs and round topics — they collide with the meta files.

## The queues are the source of truth

`status` is one of: `backlog | todo | doing | done`.

- **`<plan-root>/queue-plans.yaml`** is the repo-wide ledger. It lists _every_ plan (completed plans
  stay, as `status: done`). Each entry: `item` (a `<slug>` dir), `status`, `depends_on` (list of other
  `item`s), `prompt` (`/runner-plan -ar @<plan-dir>/`), `notes` (free-form). Entry order reflects
  execution priority: active items first, then backlog, then done.
- **`<plan-dir>/queue-rounds.yaml`** lists that plan's `rounds:` in execution order. Each round entry
  has the same fields, with `item` = the round's `<topic>` and `prompt` =
  `/<matched-executor> -ar <plan-dir>/rounds/<topic>.md` — assembled by `cog round-prompt build` from
  the `cog power-grade match` result, never hardcoded.

**Every queue entry — both levels — carries a `prompt` field.**

## Round file contract

Each round file (`rounds/<topic>.md`) is a **self-contained task description** designed to be consumed
directly by `/<executor> -ar <path>` or included via `@` in `/runner-plan -ar @<plan-dir>/`.

Self-containment rules:

- Contains the full problem statement and motivation — no "see the conversation" or "as discussed."
- Includes all code references (absolute paths, relevant excerpts) needed for THIS round.
- Carries its `R<n>` requirement IDs (allocated by `cog round-req stamp`), preserved across any split
  (`cog round-split coverage` enforces no loss).
- Describes what previous rounds produced (expected state) without requiring the executor to read
  those round files.
- Specifies what is in scope and out of scope for this round.
- Has its own acceptance criteria, independently verifiable.

## Single-session sizing

Rounds are sized to the rubric's executor-independent **single-session ceiling** — one cohesive unit
of work completable in a single execution session — not to any executor's capacity. Targeting an
executor would re-entangle complexity with capability, the conflation
[ADR-0049](../../docs/decisions/0049-plan-complexity-rubric.md) removed.

- **One cohesive unit**: each round addresses one feature, one module refactor, or one layer of the
  stack. Quality degrades when a single session handles multiple loosely-related changes.
- **Mechanically-coupled changes belong together**: file count is incidental — co-changing edits stay
  in one round regardless of count. A round description usually fits under ~300 lines of plan text.
- **Executor routing is downstream**: after sizing, each final round's rubric score is matched to an
  executor (`cog power-grade match`) and stamped into its prompt; a reserved (`> 30`) round is never
  queued and is split further (ADR-0056).

## Lifecycle rules

1. **Generation**: The planning skill bootstraps the root (`README.md`, `queue-plans.yaml`) if
   missing, writes the plan as `plans/<slug>/` (`README.md`, `rounds/<topic>.md`, inner
   `queue-rounds.yaml`), and registers the plan in `<plan-root>/queue-plans.yaml`. It never executes.
2. **Execution**: Rounds are executed **one at a time**, each in its own executor session. When handed
   the plan directory or its `README.md`, the runner reads the plan's `queue-rounds.yaml`, runs the
   first round whose status is `todo`, then stops. When starting a round it sets that round's
   `status: doing`; after completing it, `status: done` — a crashed session leaves a visible `doing`
   marker. Never batch multiple rounds into a single session.
3. **Completion**: After all rounds are done, set the plan's `status: done` in
   `<plan-root>/queue-plans.yaml`. **Nothing moves on disk** — the plan directory stays where it is.

## `README.md` and queue file roles

- **`<plan-dir>/queue-rounds.yaml`** is the machine-readable source of truth for round order and status.
- **`<plan-dir>/README.md`** is the human-facing index and decision record: problem statement,
  strategy, execution commands, architectural decisions, and rejected alternatives. It mirrors the
  queue for readers but must not become a competing source of truth for status — the
  `queue-rounds.yaml` wins.
- **`<plan-root>/README.md`** is a static explainer of the whole system — structure, queue semantics,
  execution discipline. It carries no per-plan state.
