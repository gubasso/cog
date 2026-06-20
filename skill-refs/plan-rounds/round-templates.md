# Round Plan Templates

Templates for the files generated under `.implementation-plans/`. Use `{{PLACEHOLDER}}` markers —
the generating skill substitutes them with actual values.

Every plan is a directory `plans/<slug>/` containing: `README.md` (Template B), one round file per
round (Template A, **no number prefix**), an inner `queue-rounds.yaml` (Template D), and — for XL
plans only — `STRATEGY.md` (Template C). The plan is also registered in the repo-wide
`.implementation-plans/queue-plans.yaml` (Template D). Plan directories are flat siblings, a single
level under `plans/` — **never nested** and never with plan subdirectories; ordering lives only in
`depends_on`.

The root files `.implementation-plans/README.md` (Template F) and
`.implementation-plans/queue-plans.yaml` (Template D, empty `plans:` list) are bootstrapped once,
the first time the generating skill runs in a repo.

All templates follow the repo's markdown rules: fenced code blocks must have language specifiers
(MD040). Use `text` when no specific syntax applies.

## Template A — Round file (`plans/<slug>/<topic>.md`)

Each round file is a self-contained task description for `/prex -ar`. The filename is the round's
`<topic>` slug with no number prefix; round order lives in the plan's `queue-rounds.yaml`. Topic
slugs must not be `readme`, `queue`, `strategy`, `queue-plans`, or `queue-rounds` (case-insensitive)
— those names are reserved for the meta files.

```markdown
# {{Title}}

> Plan: {{SLUG}} | Round: {{N}} of {{TOTAL}} | Complexity: {{GRADE}} | Generated: {{ISO_8601}} |
> Repo: {{REPO_ROOT}}

## Context

{{Full problem statement and motivation. Written so someone with ZERO prior context understands the
"why". Compact but complete — 10–20 lines of focused context. Do NOT reference external documents or
"the conversation".}}

## Previous Rounds

{{If this is not the first round: describe what prior rounds produced — specific files
created/modified, patterns established, types introduced. Describe the EXPECTED state, not actual
(the executor adapts to what it finds). If this is the first round: "This is the first round — no
prior rounds."}}

## Scope of This Round

{{Precise description of what this round implements. Explicitly state:}} {{- IN scope: what this
round delivers.}} {{- OUT of scope: what is deferred to later rounds (scope creep prevention).}}

## Current State

### Key Files

{{For each file relevant to THIS round:}}

- `{{absolute path}}` — {{role/purpose}} {{Key excerpts, signatures, or structural observations when
  needed.}}

### Existing Patterns

{{Conventions, naming patterns, structural rules the implementation must follow.}}

## Implementation Steps

### First Step: Mark this round as started

In this plan's `queue-rounds.yaml`, set this round's (`item: {{TOPIC}}`) `status` to `doing`.

### Step 1: {{title}}

{{Which file to create or modify (absolute path). What to add, change, or remove — specific enough
to implement. Why this step is needed. Ordering dependencies on other steps within this round.}}

### Step 2: {{title}}

{{details}}

### Final Step: Update the queue

Record completion in the queue — status lives in YAML; nothing moves on disk:

1. In this plan's `queue-rounds.yaml`, set this round's (`item: {{TOPIC}}`) `status` to `done`.

{{If this is the final round, also:}}

2. All rounds are now done, so in the top-level `.implementation-plans/queue-plans.yaml` set this
   plan's (`item: {{SLUG}}`) `status` to `done`. Leave the plan directory in place.

## Acceptance Criteria

{{Concrete, checkable criteria specific to THIS round. Each independently verifiable.}}

- [ ] {{criterion 1}}
- [ ] {{criterion 2}}
- [ ] This plan's `queue-rounds.yaml` shows round `{{TOPIC}}` as `done`. {{If this is the final
      round:}}
- [ ] The top-level `.implementation-plans/queue-plans.yaml` shows this plan as `done`.

## Next Round

{{If not the last round: brief preview of what comes next and what this round enables for it. If the
last round: "This is the final round."}}
```

### Round file guidelines

- The `## Context` section must be self-contained. Repeat the essential problem statement — do not
  say "see README" or "as discussed."
- `## Previous Rounds` describes expected output of prior rounds, not actual. The executor adapts to
  the real codebase state.
- `## Scope of This Round` prevents scope creep — the executor knows what NOT to do.
- `## Next Round` gives the executor awareness of the bigger picture without requiring it to read
  ahead.
- Implementation steps are in dependency order within the round.
- Every round file must open its implementation steps with a "First Step: Mark this round as
  started" that sets the round's `status` to `doing` in the plan's `queue-rounds.yaml` — a crashed
  or interrupted session then leaves a visible `doing` marker.
- Every round file must end with a "Final Step: Update the queue" that instructs the executor to set
  the round's `status` to `done` in the plan's `queue-rounds.yaml`.
- The **final round** must additionally instruct the executor to set the plan's `status` to `done`
  in the top-level `.implementation-plans/queue-plans.yaml`. **Nothing moves on disk** — there are
  no `01-todo`/`02-done` directories.
- Include enough code context (quoted lines, signatures) for the executor to locate exact insertion
  points. Do not just cite line numbers — they shift.

## Template B — Plan directory `README.md` (`plans/<slug>/README.md`)

The plan's human-facing index and decision record. The plan's `queue-rounds.yaml` (Template D) is
the source of truth for round order and status; `README.md` mirrors it for readers but must not
become a competing status source.

````markdown
# {{Plan Title}}

> Complexity: {{GRADE}} | Rounds: {{TOTAL}} | Generated: {{ISO_8601}} | Repo: {{REPO_ROOT}}

## Problem Statement

{{Why this work is needed. Full motivation and background.}}

## Strategy

{{High-level approach. How the work is split into rounds and why this splitting was chosen. For L
plans, 2–3 sentences. For XL, summarize and point to STRATEGY.md.}}

## Rounds

{{A readable overview of the rounds, in order. The authoritative order and status live in
`queue-rounds.yaml` — keep this list in sync but do not duplicate per-round status here.}}

1. `{{topic-1}}.md` — {{one-line topic summary}}
2. `{{topic-2}}.md` — {{one-line topic summary}}

## Execution Commands

```bash
# Execute the next todo round (executor reads queue-rounds.yaml, runs the first todo round, then stops):
/prex -ar @.implementation-plans/plans/{{SLUG}}/

# Or target a specific round file directly:
/prex -ar .implementation-plans/plans/{{SLUG}}/{{topic-1}}.md
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

{{Architectural decisions made during the interview. Include the reasoning behind each. Constraints
that apply across all rounds. Always include an `Executor: {{EXECUTOR}} (EF {{FACTOR}})` line.}}

## Rejected Alternatives

{{Approaches considered and dismissed, with the reason for rejection.}}

## Risks & Edge Cases

{{Known risks that span the full implementation. For each, note whether it needs handling or is
accepted.}}

## Completion

When all rounds are done, set each round `done` in this plan's `queue-rounds.yaml` and set this plan
`done` in the top-level `.implementation-plans/queue-plans.yaml`. Nothing moves on disk.
````

## Template C — `STRATEGY.md` (XL plans only)

Generated only for XL-grade plans where the round structure and cross-cutting concerns need detailed
documentation.

````markdown
# Strategy: {{Plan Title}}

## Architectural Overview

{{How the pieces fit together. The big picture of what is being built/changed and why the work is
structured this way.}}

## Round Dependency Graph

{{Which rounds depend on which. Why this ordering was chosen. Identify the critical path.}}

```text
{{round-a}} (foundations) ──→ {{round-b}} (core logic)
                         └──→ {{round-c}} (API layer) ──→ {{round-d}} (integration tests)
```

## Risk Mitigation

{{How the round splitting reduces risk. What happens if a round fails mid-way. Rollback
considerations. Which rounds are independently revertable.}}

## Cross-Cutting Concerns

{{Concerns that span multiple rounds. Each round file references this document for shared decisions.
Examples: error handling patterns, logging conventions, configuration approach, naming conventions
introduced in the first round that later rounds must follow.}}
````

## Template D — queue files

Two flavors, same schema. `status` is one of `backlog | todo | doing | done`. Every entry carries a
`prompt`.

### Inner queue — `plans/<slug>/queue-rounds.yaml`

Lists the plan's rounds in execution order.

```yaml
# Rounds for this plan, in execution order. status: backlog | todo | doing | done
rounds:
  - item: {{topic-1}}
    status: todo
    depends_on: []
    prompt: /prex -ar .implementation-plans/plans/{{SLUG}}/{{topic-1}}.md
    notes: "{{one-line context}}"
  - item: {{topic-2}}
    status: todo
    depends_on: [{{topic-1}}]
    prompt: /prex -ar .implementation-plans/plans/{{SLUG}}/{{topic-2}}.md
    notes: ""
```

### Top-level ledger — `.implementation-plans/queue-plans.yaml`

The repo-wide queue. Append the new plan among the active items by priority; never reorder or
rewrite existing entries. `item` is the `<slug>` dir. If the file does not exist yet, bootstrap it
with an empty `plans:` list.

```yaml
# Source of truth for the .implementation-plans/ queue. Status & order live HERE, not in paths.
# status: backlog | todo | doing | done
plans:
  - item: {{SLUG}}
    status: todo
    depends_on: []
    prompt: /prex -ar @.implementation-plans/plans/{{SLUG}}/
    notes: "{{one-line context}}"
```

## Template F — Root `README.md` (`.implementation-plans/README.md`)

A static explainer of the plan system, bootstrapped the first time the generating skill runs in a
repo and **never overwritten** afterwards. It carries no per-plan state.

````markdown
# Implementation Plans

Implementation plans generated by the `plan-writer` skill and executed by `/prex`. This tree is
**flat and queue-driven**: a plan's status, order, dependencies, and execution command live in queue
files — never in directory or file names.

## Structure

```text
.implementation-plans/
├── README.md        this file — static explainer, no per-plan state
├── queue-plans.yaml repo-wide ledger: every plan + status (source of truth)
└── plans/
    └── <slug>/      plan directory (flat sibling, never nested): README.md,
                     queue-rounds.yaml, <topic>.md round files, STRATEGY.md (XL only)
```

Plan directories are flat siblings — a single level under `plans/`. Never nest a plan directory
inside another; ordering between plans lives only in `queue-plans.yaml` `depends_on`.

## Queue semantics

`status` is one of `backlog | todo | doing | done`. Every queue entry carries a `prompt` field with
the exact execution command. Completed plans stay in the ledger as `done` — **nothing moves on
disk**; status, not path, records the lifecycle state.

## Execution discipline

- **One round per `/prex` session.** When pointed at a plan directory or its `README.md`, the
  executor reads that plan's `queue-rounds.yaml`, runs the first `todo` round, and stops. A fresh
  session is launched for each subsequent round.
- **Status flips.** Set a round to `doing` when starting and `done` when finished.
- **Completion.** After the final round, set the plan itself to `done` in this directory's
  `queue-plans.yaml`.
````
