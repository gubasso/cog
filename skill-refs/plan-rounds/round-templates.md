# Round Plan Templates

Templates for the files generated under the resolved plan store (`cog plan project resolve` → `plan_root`; `cog plan new` → `plan_dir`). Use `{{PLACEHOLDER}}` markers — the generating skill substitutes them with actual values and never hardcodes `.implementation-plans/` ([ADR-0011](../../docs/decisions/0011-plan-vault-storage-and-resolution.md)).

Every plan is a directory `plans/<slug>/` containing: `README.md` (Template B), a `rounds/` subdir with one round file per round (Template A, **no number prefix**), an inner `queue-rounds.yaml` (Template D), and — for very large plans only — `STRATEGY.md` (Template C). The plan is also registered in the store-wide `<plan-root>/queue-plans.yaml` (Template D). Plan directories are flat siblings, a single level under `plans/` — **never nested**; ordering lives only in `depends_on`.

The root files `<plan-root>/README.md` (Template F) and `<plan-root>/queue-plans.yaml` (Template D, empty `plans:` list) are bootstrapped once, the first time the generating skill runs against a store.

All templates follow the repo's markdown rules: fenced code blocks must have language specifiers (MD040). Use `text` when no specific syntax applies.

Template A renders the structure; the _content_ each round must carry — concrete targets, machine-checkable acceptance criteria, requirement traceability, an end-to-end verification gate, and explicit out-of-scope — follows `cog skill-refs path plan-rounds/plan-quality-principles.md`.

## Template A — Round file (`<plan-dir>/rounds/<topic>.md`)

Each round file is a self-contained task description for `/<executor> -ar`. The filename is the round's `<topic>` slug with no number prefix; round order lives in the plan's `queue-rounds.yaml`. Topic slugs must not be `readme`, `queue`, `strategy`, `queue-plans`, or `queue-rounds` (case-insensitive) — those names are reserved for the meta files.

```markdown
# {{Title}}

> Plan: {{SLUG}} | Round: {{N}} of {{TOTAL}} | Complexity: {{GRADE}} | Generated: {{ISO_8601}} | Repo: {{REPO_ROOT}} Depends on: {{DEPENDENCIES_OR_NONE}} | Parallel with: {{PARALLEL_ROUNDS_OR_NONE}}

## Context

{{Full problem statement and motivation. Written so someone with ZERO prior context understands the "why". Compact but complete — 10–20 lines of focused context. Do NOT reference external documents or "the conversation".}}

## Previous Rounds

{{If this is not the first round: describe what prior rounds produced — specific files created/modified, patterns established, types introduced. Describe the EXPECTED state, not actual (the executor adapts to what it finds). If this is the first round: "This is the first round — no prior rounds."}}

## Scope of This Round

{{Precise description of what this round implements. Explicitly state:}} {{- IN scope: what this round delivers.}} {{- OUT of scope: what is deferred to later rounds or intentionally excluded (scope creep prevention). Include "Nothing else is in scope for this round."}}

## Current State

### Key Files

{{For each file relevant to THIS round:}}

- `{{absolute path}}` — {{role/purpose}} {{Key excerpts, signatures, or structural observations when needed.}}

### Existing Patterns

{{Conventions, naming patterns, structural rules the implementation must follow.}}

## Implementation Steps

### First Step: Mark this round as started

In this plan's `queue-rounds.yaml`, set this round's (`item: {{TOPIC}}`) `status` to `doing`.

### Step 1: {{title}}

{{Which file to create or modify (absolute path). What to add, change, or remove — specific enough to implement. Why this step is needed. Ordering dependencies on other steps within this round.}}

### Step 2: {{title}}

{{details}}

### Final Step: Update the queue

Record completion in the queue — status lives in YAML; nothing moves on disk:

1. In this plan's `queue-rounds.yaml`, set this round's (`item: {{TOPIC}}`) `status` to `done`.

{{If this is the final round, also:}}

2. All rounds are now done, so in the top-level `<plan-root>/queue-plans.yaml` set this plan's (`item: {{SLUG}}`) `status` to `done`. Leave the plan directory in place.

## End-to-End Verification Gate

{{Exact command(s), UI flow, or system check that proves this round works end to end from the user or caller boundary. Include expected observable output and any required setup data. This gate must be run before the final queue update unless explicitly impossible, in which case record the blocker and the closest completed verification.}}

## Acceptance Criteria

{{Concrete, checkable criteria specific to THIS round. Each independently verifiable and written in a Given-When-Then or EARS-checkable shape. Each criterion carries its `cog round-req`-stamped requirement ID: `- [ ] (R3) ...`. The IDs are allocated by `cog round-req stamp` and preserved across any split (`cog round-split coverage`).}}

- [ ] (R{{n}}) GIVEN {{precondition}}, WHEN {{action or command}}, THEN {{observable result}}.
- [ ] (R{{n}}) WHEN {{trigger or condition}}, THE SYSTEM SHALL {{required behavior}}.
- [ ] (R{{n}}) GIVEN the implementation is complete, WHEN the end-to-end verification gate runs, THEN it passes with {{expected output or signal}}.
- [ ] This plan's `queue-rounds.yaml` shows round `{{TOPIC}}` as `done`. {{If this is the final round:}}
- [ ] The top-level `<plan-root>/queue-plans.yaml` shows this plan as `done`.

## Next Round

{{If not the last round: brief preview of what comes next and what this round enables for it. If the last round: "This is the final round."}}
```

### Round file guidelines

- The `## Context` section must be self-contained. Repeat the essential problem statement — do not say "see README" or "as discussed."
- `## Previous Rounds` describes expected output of prior rounds, not actual. The executor adapts to the real codebase state.
- `## Scope of This Round` prevents scope creep — the executor knows what NOT to do.
- `## Next Round` gives the executor awareness of the bigger picture without requiring it to read ahead.
- Implementation steps are in dependency order within the round.
- Every round file must open its implementation steps with a "First Step: Mark this round as started" that sets the round's `status` to `doing` in the plan's `queue-rounds.yaml` — a crashed or interrupted session then leaves a visible `doing` marker.
- Every round file must end with a "Final Step: Update the queue" that instructs the executor to set the round's `status` to `done` in the plan's `queue-rounds.yaml`.
- The **final round** must additionally instruct the executor to set the plan's `status` to `done` in the top-level `<plan-root>/queue-plans.yaml`. **Nothing moves on disk** — there are no `01-todo`/`02-done` directories.
- Include enough code context (quoted lines, signatures) for the executor to locate exact insertion points. Do not just cite line numbers — they shift.

## Template B — Plan directory `README.md` (`<plan-dir>/README.md`)

The plan's human-facing index and decision record. The plan's `queue-rounds.yaml` (Template D) is the source of truth for round order and status; `README.md` mirrors it for readers but must not become a competing status source.

````markdown
# {{Plan Title}}

> Complexity: {{GRADE}} | Rounds: {{TOTAL}} | Generated: {{ISO_8601}} | Repo: {{REPO_ROOT}}

## Problem Statement

{{Why this work is needed. Full motivation and background.}}

## Strategy

{{High-level approach. How the work is split into rounds and why this splitting was chosen.}}

## Rounds

{{A readable overview of the rounds, in order. The authoritative order and status live in `queue-rounds.yaml` — keep this list in sync but do not duplicate per-round status here.}}

1. `rounds/{{topic-1}}.md` — {{one-line topic summary}}
2. `rounds/{{topic-2}}.md` — {{one-line topic summary}}

## Executor Routing

{{One row per round: its rubric score, grade, the matched executor (from `cog power-grade match`), and the stamped prompt (assembled by `cog round-prompt build`). Reserved (`> 30`) rounds are never queued — they are split further (ADR-0015).}}

| Round         | Score     | Grade     | Matched executor       | Prompt                                                    |
| ------------- | --------- | --------- | ---------------------- | --------------------------------------------------------- |
| `{{topic-1}}` | {{score}} | {{grade}} | `{{matched-executor}}` | `/{{matched-executor}} -ar {{ROUNDS_DIR}}/{{topic-1}}.md` |

## Execution Commands

```bash
# Run the whole plan (runner reads queue-rounds.yaml, runs the first todo round, then stops):
/runner-plan -ar @{{PLAN_DIR}}/

# Or target a specific round file directly with its matched executor:
/{{MATCHED_EXECUTOR}} -ar {{ROUNDS_DIR}}/{{topic-1}}.md
```

## Execution Discipline

**Rounds must be executed one at a time.** Each round is a self-contained unit of work designed for a single execution session. Do not implement multiple rounds in one session.

When a runner is pointed at this directory or this `README.md`, it MUST:

1. Read this plan's `queue-rounds.yaml`.
2. Find the first round with status `todo`.
3. Dispatch that round's `prompt` verbatim (set `status: doing`, run, set `done`), then stop.
4. End the session — a fresh session is launched for any subsequent round.

## Decisions & Constraints

{{Architectural decisions made during the interview. Include the reasoning behind each. Constraints that apply across all rounds. Complexity is executor-independent; the per-round executor lives in the Executor Routing table above, not in a sizing factor.}}

## Rejected Alternatives

{{Approaches considered and dismissed, with the reason for rejection.}}

## Risks & Edge Cases

{{Known risks that span the full implementation. For each, note whether it needs handling or is accepted.}}

## Completion

When all rounds are done, set each round `done` in this plan's `queue-rounds.yaml` and set this plan `done` in the top-level `<plan-root>/queue-plans.yaml`. Nothing moves on disk.
````

## Template C — `STRATEGY.md` (very large plans only)

Generated only for very-high-grade plans where the round structure and cross-cutting concerns need detailed documentation.

````markdown
# Strategy: {{Plan Title}}

## Architectural Overview

{{How the pieces fit together. The big picture of what is being built/changed and why the work is structured this way.}}

## Round Dependency Graph

{{Which rounds depend on which. Why this ordering was chosen. Identify the critical path.}}

```text
{{round-a}} (foundations) ──→ {{round-b}} (core logic)
                         └──→ {{round-c}} (API layer) ──→ {{round-d}} (integration tests)
```

## Risk Mitigation

{{How the round splitting reduces risk. What happens if a round fails mid-way. Rollback considerations. Which rounds are independently revertable.}}

## Cross-Cutting Concerns

{{Concerns that span multiple rounds. Each round file references this document for shared decisions. Examples: error handling patterns, logging conventions, configuration approach, naming conventions introduced in the first round that later rounds must follow.}}
````

## Template D — queue files

Two flavors, same schema. `status` is one of `backlog | todo | doing | done`. Every entry carries a `prompt`.

### Inner queue — `<plan-dir>/queue-rounds.yaml`

Lists the plan's rounds in execution order. Each round `prompt` is `/<matched-executor> -ar
<rounds-dir>/<topic>.md`, assembled by `cog round-prompt build` from the `cog power-grade match` result — never hardcoded to a fixed executor.

```yaml
# Rounds for this plan, in execution order. status: backlog | todo | doing | done
rounds:
  - item: {{topic-1}}
    status: todo
    depends_on: []
    prompt: /{{MATCHED_EXECUTOR}} -ar {{ROUNDS_DIR}}/{{topic-1}}.md
    notes: "{{one-line context}}"
  - item: {{topic-2}}
    status: todo
    depends_on: [{{topic-1}}]
    prompt: /{{MATCHED_EXECUTOR}} -ar {{ROUNDS_DIR}}/{{topic-2}}.md
    notes: ""
```

### Top-level ledger — `<plan-root>/queue-plans.yaml`

The store-wide queue. Append the new plan among the active items by priority; never reorder or rewrite existing entries. `item` is the `<slug>` dir. If the file does not exist yet, bootstrap it with an empty `plans:` list.

```yaml
# Source of truth for the plan-vault queue. Status & order live HERE, not in paths.
# status: backlog | todo | doing | done
plans:
  - item: {{SLUG}}
    status: todo
    depends_on: []
    prompt: /runner-plan -ar @{{PLAN_DIR}}/
    notes: "{{one-line context}}"
```

## Template F — Root `README.md` (`<plan-root>/README.md`)

A static explainer of the plan system, bootstrapped the first time the generating skill runs against a store and **never overwritten** afterwards. It carries no per-plan state.

````markdown
# Implementation Plans

Implementation plans built by the `plan-builder-to-queue` skill and executed by the matched executor stamped into each round (`/runner-plan` dispatches them). This tree is **flat and queue-driven**: a plan's status, order, dependencies, and execution command live in queue files — never in directory or file names.

## Structure

```text
<plan-root>/
├── README.md        this file — static explainer, no per-plan state
├── queue-plans.yaml store-wide ledger: every plan + status (source of truth)
└── plans/
    └── <slug>/      plan directory (flat sibling, never nested): README.md,
                     queue-rounds.yaml, rounds/<topic>.md round files, STRATEGY.md (large plans only)
```

Plan directories are flat siblings — a single level under `plans/`. Never nest a plan directory inside another; ordering between plans lives only in `queue-plans.yaml` `depends_on`.

## Queue semantics

`status` is one of `backlog | todo | doing | done`. Every queue entry carries a `prompt` field with the exact execution command. Completed plans stay in the ledger as `done` — **nothing moves on disk**; status, not path, records the lifecycle state.

## Execution discipline

- **One round per session.** When pointed at a plan directory or its `README.md`, the runner reads that plan's `queue-rounds.yaml`, dispatches the first `todo` round's stamped prompt, and stops. A fresh session is launched for each subsequent round.
- **Status flips.** Set a round to `doing` when starting and `done` when finished.
- **Completion.** After the final round, set the plan itself to `done` in this directory's `queue-plans.yaml`.
````
