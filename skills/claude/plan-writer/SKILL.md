---
name: plan-writer
description: >
  Synthesize the current conversation into an executor-aware implementation plan
  under .implementation-plans/plans/. Evaluates complexity (S/M/L/XL): S/M plans
  are generated as a single self-contained file (plans/<slug>.md); L/XL plans
  become a directory of self-contained rounds (plans/<slug>/), each sized for
  one prex run and directly consumable by /prex -ar. Includes an interactive
  interview to clarify scope, alternatives, and decisions before generating.
  Use when the user says "plan-writer", "write a plan", "capture this as a plan",
  or wants to export conversation findings as actionable implementation documents.

  Optional flag: --executor <prex|single-pass|limited> overrides the default
  executor assumption used to size rounds. The default is `prex` — assumes the
  /prex pipeline (Codex plan → Claude review → Codex implement → Claude
  review-loop with fixes), which absorbs in-round risk and produces fewer,
  larger, more cohesive rounds (Executor Factor 1.5). `single-pass` assumes one
  capable model with no review gate; raw complexity stands (EF 1.0). `limited`
  assumes a weaker model or tighter context and produces smaller, safer rounds
  (EF 0.8). Most users should not need to set this flag.
argument-hint: "[--executor <prex|single-pass|limited>] <orientation/focus/goal>"
disable-model-invocation: true
allowed-tools: Bash Read Write Grep Glob
---

<!-- trigger-tests: "plan-writer", "write a plan", "capture this as a plan", "export conversation findings" -->

# Plan Writer

Synthesize the current conversation into an executor-aware implementation plan. Output lives under
`.implementation-plans/plans/`: simple plans (S/M) are a single self-contained file; complex plans
(L/XL) are a directory of self-contained round files, each sized for one `/prex` run. The plan is
designed to be executed by a fresh LLM session with ZERO assumptions about prior conversation.

This skill runs **inline** (no fork) because it needs full access to the current conversation
context to extract decisions, findings, and explored code.

## Reference resolution

Shared references live in `$DOCS_NOTES_REPO`. Resolve at skill start:

DOCS_NOTES="${DOCS_NOTES_REPO:-}"

If `$DOCS_NOTES_REPO` is unset, the skill warns and continues without plan-rounds references.

References resolve to `$DOCS_NOTES_REPO/tech/tools/claude-code/plan-rounds/`.

## Inputs

- `$ARGUMENTS` — free-text orientation that specifies the angle, focus, or goal for the plan. This
  shapes the entire output. **Required.**

If `$ARGUMENTS` is empty, ask the user for an orientation before proceeding.

## Phase 1: Setup

### 1a — Parse arguments

Parse `$ARGUMENTS` for the optional `--executor` flag before deriving the slug. Apply these rules
strictly:

- If `$ARGUMENTS` begins with `--executor <value>` or `--executor=<value>`, consume the flag and the
  value. The value must be exactly one of `prex`, `single-pass`, `limited` — case-sensitive, no
  other forms accepted (e.g., `prex-foo` is invalid).
- If the flag is present but the value is missing (`--executor` alone, `--executor=` with empty RHS,
  or `--executor` followed by another flag), report
  `error: --executor requires a value (one of prex|single-pass|limited)` and stop.
- If the value is not in the allowed set, report
  `error: invalid --executor value '<value>' (must be prex|single-pass|limited)` and stop.
- An argument that starts with `--executor` but is neither `--executor` exactly, `--executor=...`,
  nor followed by a value (e.g., `--executor-foo`) is invalid; report the error and stop.
- If the flag is absent, default `EXECUTOR=prex`.
- The text after the flag (with surrounding whitespace trimmed) is the **orientation**. If it is
  empty, report `error: orientation is required (got: empty after --executor parsing)` and stop.

Map `EXECUTOR` to the Executor Factor (EF) used in Phase 5:

| EXECUTOR      | EF  |
| ------------- | --- |
| `prex`        | 1.5 |
| `single-pass` | 1.0 |
| `limited`     | 0.8 |

Derive a 3–5 word lowercase slug from the orientation by delegating to `cog plan-slug`.
The helper owns the `[a-z0-9-]`, 60-character maximum, and reserved-name guard for `readme`,
`queue`, and `strategy` (case-insensitive). If the helper rejects the derived slug, pick different
wording or ask the user for a rename. The same reserved-name rule applies to round topic slugs in
Phase 6b; use the helper for each generated topic before writing files.

```bash
REPO_ROOT="<repo root from the current workspace>"
SLUG_JSON="$(cog plan-slug --text "$ORIENTATION" --json)"
SLUG="$(jq -r '.slug' <<<"$SLUG_JSON")"
cog plan-init --repo-root "$REPO_ROOT" --json
PLAN_ROOT="$REPO_ROOT/.implementation-plans"
PLANS_DIR="$PLAN_ROOT/plans"
```

The plan's output target is decided in Phase 5 by grade: a single file `$PLANS_DIR/$SLUG.md` for
S/M, or a directory `$PLANS_DIR/$SLUG/` for L/XL.

### 1b — Collision check

If `$PLANS_DIR/$SLUG.md` exists, or `$PLANS_DIR/$SLUG/` exists and is non-empty, ask the user:
`[u]pdate (overwrite; rely on git/filesystem history), [a]bort, [r]ename (append suffix)?`

Do not silently overwrite.

### 1c — Validate

If `cog plan-init` reports that `$PLAN_ROOT` cannot be created or validated, report the
error and stop.

If a legacy `$REPO_ROOT/.plan/` directory exists, inform the user that this repo still carries
plans in the legacy layout (migration is manual — see `plan-lifecycle.md` § "Migrating a legacy
`.plan/` tree") and continue with the new layout. Do not migrate automatically. `plan-init` reports
this as `legacy_plan_dir`; the judgment and user-facing explanation stay in this skill.

### 1d — Load shared references

Read all three reference files into context:

- `$DOCS_NOTES_REPO/tech/tools/claude-code/plan-rounds/plan-lifecycle.md` — directory structure,
  executor model, lifecycle rules.
- `$DOCS_NOTES_REPO/tech/tools/claude-code/plan-rounds/complexity-heuristic.md` — scoring axes,
  grade mapping, splitting rules.
- `$DOCS_NOTES_REPO/tech/tools/claude-code/plan-rounds/round-templates.md` — templates for round
  files, single-file plans, `README.md`, `QUEUE.yaml`, STRATEGY.md.

## Phase 2: Synthesize Conversation Context

Walk the full conversation history and extract every piece of information relevant to the
orientation. Organize findings into these buckets:

1. **Problem statement** — What problem or goal was identified? Why does this work matter? What
   triggered the conversation?

2. **Decisions made** — Every technical decision, architectural choice, or constraint that was
   established during the conversation. Include the reasoning behind each decision, not just the
   conclusion.

3. **Code explored** — Every file path read, function examined, pattern identified, or dependency
   traced. Record the absolute path AND the relevant content (signatures, key lines, structural
   observations).

4. **Current state** — What exists now in the codebase that is relevant? What works, what does not,
   what is missing?

5. **Requirements discussed** — Functional requirements, non-functional constraints, compatibility
   needs, performance expectations.

6. **Rejected alternatives** — Approaches that were considered and dismissed, with the reason they
   were rejected. This prevents the implementor from re-treading dead ends.

7. **Open questions resolved** — Questions that came up during exploration and their answers.

8. **Unresolved items** — Anything flagged but not yet decided. The implementor needs to know what
   is settled vs. what still needs a judgment call.

Do NOT invent information that was not discussed. If a bucket is empty (nothing relevant was
discussed), omit it from the output. But do NOT omit information that WAS discussed just because it
seems minor — the implementor has no other source of context.

## Phase 3: Research the Codebase

Using the orientation and conversation context, actively gather code references the implementor will
need. This phase goes **beyond** what was explicitly discussed — it proactively collects surrounding
context.

For each relevant file or code path:

- Read the file with the Read tool.
- Extract the specific lines, function signatures, type definitions, or patterns the implementor
  will need to reference.
- Note the absolute file path.
- Note any conventions, naming patterns, or structural rules the code follows that the implementor
  must match.

Also gather:

- **Repo conventions** — Read `CLAUDE.md` or any project-level instruction files that establish
  conventions the implementor must follow.
- **Similar prior art** — Find existing implementations of similar features or patterns in the repo
  that the implementor should use as reference. Grep for related patterns.
- **Dependencies** — Identify files, modules, or external tools the implementation will interact
  with.

Limit research to what the orientation calls for. Do not exhaustively catalog the entire repo —
focus on the implementation surface.

## Phase 4: Interview

Collaborate with the user to clarify scope, resolve ambiguities, and make decisions that shape the
plan. This phase is interactive — ask questions, present alternatives, and refine understanding
until the plan structure is clear.

### Interview rules

- **Adaptive batching**: Start with a batch of 2–3 key questions (scope, approach, sizing). Then ask
  follow-ups one at a time only for items that need clarification. Balance speed with depth.
- **Present concrete options**: When alternatives exist, describe each with trade-offs. Do not ask
  open-ended questions when you can offer structured choices.
- **Skip known answers**: If the conversation already settled a question, do not re-ask. Note the
  answer as "established in conversation" and move on.
- **"You decide" is valid**: If the user defers a decision, pick the best default and note it as a
  skill-chosen default in the plan's Decisions & Constraints section.
- **No fixed question list**: Adapt questions to the specific task. The categories below are
  guidance, not a checklist.

### Question categories

Draw from these as relevant to the task:

1. **Scope boundaries** — "The conversation touched X, Y, Z. Which are in scope for this plan?
   Should we include W?"
2. **Implementation approach** — "I see two ways to do this: (A) extend FooService, (B) create
   BarService. A is simpler but couples to the old pattern. B is cleaner but more files. Which do
   you prefer?"
3. **Ordering / priority** — "If we split this into rounds, should we start with the data layer or
   the API surface?"
4. **Risk tolerance** — "This change touches shared infrastructure. Should the plan include a
   rollback step?"
5. **Testing strategy** — "Should each round include its own tests, or should we have a dedicated
   testing round at the end?"
6. **Architecture decisions** — "The current code uses pattern X. Should the plan follow it or
   introduce pattern Y?"
7. **Executor sizing** — "This looks like it could be 1 large round or 3 smaller ones. Smaller
   rounds are safer but have more overhead. Preference?"

### Convergence

After gathering enough answers to classify complexity and split rounds, summarize all decisions made
and ask for a final "ready to generate?" confirmation before proceeding to Phase 5.

## Phase 5: Classify Complexity

Using the synthesized context, research findings, and interview answers, evaluate the implementation
against the five scoring axes defined in
`$DOCS_NOTES_REPO/tech/tools/claude-code/plan-rounds/complexity-heuristic.md`.

State the executor profile and EF up front (from Phase 1a): `Executor: $EXECUTOR (EF = <factor>)`.

1. Score each axis (1–4).
2. Sum to produce the **raw score** (5–20).
3. Divide the raw score by the EF to produce the **adjusted score**.
4. Map the **adjusted score** to grade: S / M / L / XL per the table in `complexity-heuristic.md`.
5. Confirm the grade is **reachable** under the EF (`complexity-heuristic.md` § "EF is mandatory —
   reachable grades per executor"); if it is not, the EF was skipped — recompute.
6. Apply override judgment if the formula does not fit (document the reason).
7. Determine round count based on the grade.

The grade selects the output format per the grade table in `complexity-heuristic.md` (the single
source of truth for grade→format): S/M → single file `$PLANS_DIR/$SLUG.md` (Template E); L/XL →
directory `$PLANS_DIR/$SLUG/` (Templates A–D; C for XL only). Never select a format directly.

Report the classification to the user:

- The grade with a one-sentence rationale.
- Per-axis scores plus EF in brief form (e.g., "files:2 cross-cut:1 deps:2 novelty:3 risk:2 → raw 10
  ÷ EF 1.5 (prex) → 6.7 → M").
- The output format (single file vs. directory).
- For L/XL: the proposed round split with topic summaries for each round. Get user confirmation
  before generating.

## Phase 6: Generate Output

### 6a — Bootstrap the plan root

Ensure the shared root files exist by delegating to the helper. It creates missing root files only
and never overwrites existing ones:

```bash
cog plan-init --repo-root "$REPO_ROOT" --json
cog queue-bootstrap --schema plans --queue "$PLAN_ROOT/QUEUE.yaml" --json
```

The helper-owned bootstrap covers:

- `$PLAN_ROOT/README.md` — static explainer of the plan system, from Template F in
  `$DOCS_NOTES_REPO/tech/tools/claude-code/plan-rounds/round-templates.md`.
- `$PLAN_ROOT/QUEUE.yaml` — the repo-wide ledger. If missing, create it with an empty `plans:` list
  per Template D.

### 6b — Plan the round split (L/XL only)

For S/M the plan is a single round by definition — skip to 6c.

For L/XL: apply the round-splitting rules from
`$DOCS_NOTES_REPO/tech/tools/claude-code/plan-rounds/complexity-heuristic.md`. Assign each
implementation step to a round. Verify no circular dependencies between rounds. Round topic slugs
must not be `readme`, `queue`, or `strategy` (case-insensitive). Then skip to 6d.

### 6c — Write the single-file plan (S/M only)

Write `$PLANS_DIR/$SLUG.md` using Template E from
`$DOCS_NOTES_REPO/tech/tools/claude-code/plan-rounds/round-templates.md`. It merges the
README-level record with the executable round body in one self-contained file:

- Problem statement (full motivation, standalone).
- Decisions and constraints from the interview (with reasoning). **Always include an
  `Executor: $EXECUTOR (EF <factor>)` line.**
- Rejected alternatives (with reasons for rejection).
- Current state with code references (absolute paths, quoted excerpts).
- Implementation steps in dependency order, opening with a "First Step: Mark this plan as started"
  that sets this plan's `status` to `doing` in the top-level `$PLAN_ROOT/QUEUE.yaml`.
- A "Final Step: Update the queue" instructing the executor to set this plan's `status` to `done`
  in the top-level `$PLAN_ROOT/QUEUE.yaml` — single-file plans have no inner queue.
- Acceptance criteria, independently verifiable.
- Risks and edge cases.

Then skip to 6h (registration).

### 6d — Write the plan directory `README.md` (L/XL)

Create `$PLANS_DIR/$SLUG/` and write `$PLANS_DIR/$SLUG/README.md` using Template B from
`$DOCS_NOTES_REPO/tech/tools/claude-code/plan-rounds/round-templates.md`.

Include:

- Full problem statement.
- Strategy summary (how the work is split and why).
- A rounds overview that mirrors the plan's `QUEUE.yaml` (which is the source of truth for round
  order and status — do not duplicate status into prose that can drift).
- Exact execution commands (`/prex -ar` per-round or full-directory).
- **Execution discipline section** — a prominent, clearly labeled section (not just a bullet) that
  states the following rules unambiguously:
  1. **One round per `/prex` session.** Each round executes in its own isolated `/prex` invocation.
     Never execute multiple rounds in a single session.
  2. **Directory or README invocation selects one round, not all.** When the executor receives the
     plan directory (`/prex -ar @.implementation-plans/plans/<slug>/`) or the `README.md`
     (`/prex -ar .implementation-plans/plans/<slug>/README.md`), it MUST read this plan's
     `QUEUE.yaml`, identify the first round with status `todo`, execute ONLY that single round,
     then stop. It does NOT proceed to the next round in the same session.
  3. **Status flips.** When starting a round, set its `status` to `doing` in the plan's
     `QUEUE.yaml`; on completion, set it to `done`. A crashed or interrupted session thus leaves a
     visible `doing` marker.
  4. **Sequential sessions.** After completing a round (marking it `done` in the plan's
     `QUEUE.yaml`), the executor session ends. The user launches a new `/prex` session for the
     next round.
  5. **Why:** Fresh sessions prevent context contamination between rounds, keep token usage
     predictable, and allow the user to review intermediate results before proceeding.
- Decisions and constraints from the interview (with reasoning). **Always include a
  `Executor: $EXECUTOR (EF <factor>)` line** here so a future re-plan or re-execution knows which
  capability assumption sized the rounds.
- Rejected alternatives (with reasons for rejection).
- Risks and edge cases that span the full plan.

### 6e — Write `STRATEGY.md` (XL only)

Write `$PLANS_DIR/$SLUG/STRATEGY.md` using Template C from
`$DOCS_NOTES_REPO/tech/tools/claude-code/plan-rounds/round-templates.md`.

Include: architectural overview, round dependency graph, risk mitigation approach, cross-cutting
concerns that span multiple rounds.

### 6f — Write round files (L/XL)

For each round, write `$PLANS_DIR/$SLUG/<topic>.md` (a kebab-case topic slug, **no number
prefix** — round order lives in the plan's `QUEUE.yaml`) using Template A from
`$DOCS_NOTES_REPO/tech/tools/claude-code/plan-rounds/round-templates.md`.

Each round file must be **self-contained** per the contract in
`$DOCS_NOTES_REPO/tech/tools/claude-code/plan-rounds/plan-lifecycle.md`:

- The `## Context` section repeats the problem statement compactly (10–20 lines). No "see README" or
  "as discussed" references.
- `## Current State` includes code references relevant to THIS round (absolute paths, quoted
  excerpts).
- `## Previous Rounds` describes what earlier rounds produced (expected state, not actual).
- `## Scope of This Round` explicitly names what is in and out of scope.
- `## Acceptance Criteria` is specific to this round and independently verifiable.
- `## Next Round` previews what comes next (or states "Final round").

### 6g — Write the plan's inner `QUEUE.yaml` (L/XL)

Create `$PLANS_DIR/$SLUG/QUEUE.yaml` through the helper and append one round entry at a time in
execution order. Each entry still follows Template D: `item` (the round's `<topic>`),
`status: todo`, `depends_on` (list of earlier round `<topic>`s, or `[]`),
`prompt: /prex -ar .implementation-plans/plans/<slug>/<topic>.md`, and `notes`.

```bash
cog queue-bootstrap --schema rounds --queue "$PLANS_DIR/$SLUG/QUEUE.yaml" --json
cog queue-append \
  --schema rounds \
  --queue "$PLANS_DIR/$SLUG/QUEUE.yaml" \
  --item "$TOPIC" \
  --status todo \
  --depends-on "$DEPENDS_ON_CSV" \
  --prompt "/prex -ar .implementation-plans/plans/$SLUG/$TOPIC.md" \
  --notes "$NOTES" \
  --json
```

### 6h — Register the plan in the top-level `QUEUE.yaml`

Append an entry to `$PLAN_ROOT/QUEUE.yaml` (created in 6a if it did not exist) through the helper:

- `item: <slug>` for a directory plan, or `item: <slug>.md` for a single-file plan.
- `status: todo`, `depends_on` (other plan `item`s, or `[]`), and `notes`.
- `prompt: /prex -ar @.implementation-plans/plans/<slug>/` for a directory plan, or
  `prompt: /prex -ar .implementation-plans/plans/<slug>.md` for a single-file plan.

```bash
cog queue-append \
  --schema plans \
  --queue "$PLAN_ROOT/QUEUE.yaml" \
  --item "$QUEUE_ITEM" \
  --status todo \
  --depends-on "$DEPENDS_ON_CSV" \
  --prompt "$PROMPT" \
  --notes "$NOTES" \
  --json
```

This round's helper appends at the end and enforces append-only byte preservation of existing
entries. If priority insertion is required, ask the user and handle that as a separate future queue
operation; do not silently reorder or rewrite existing entries in this skill.

**Every queue entry — both levels — MUST carry a `prompt` field** with the exact execution command.

### Writing guidelines

- Use fenced code blocks with language specifiers for ALL code (enforced by markdownlint MD040). Use
  `text` when no specific syntax applies.
- File paths are always absolute.
- When referencing existing code, quote the relevant lines — do not just cite a line number (line
  numbers shift).
- Write implementation steps in dependency order within each round.
- Each step should be independently verifiable.
- Every round file must open its implementation steps with a "First Step: Mark this round as
  started" that sets the round's `status` to `doing` in the plan's `QUEUE.yaml`, and end with a
  "Final Step: Update the queue" that sets it to `done`. Both steps are defined in Template A and
  must not be omitted.
- The **last round** must additionally instruct the executor to set this plan's `status` to `done`
  in the top-level `.implementation-plans/QUEUE.yaml`. The plan directory stays in place — **nothing
  is moved on disk** (there are no `01-todo`/`02-done` directories). This is defined in Template A's
  final-round conditional and must not be omitted.
- A single-file plan's "Final Step: Update the queue" targets the top-level
  `.implementation-plans/QUEUE.yaml` directly (it has no inner queue). This is defined in Template E
  and must not be omitted.
- Prefer concrete examples over abstract descriptions.
- Include enough code context that the implementor can locate the exact insertion point or
  modification target.

## Phase 7: Confirm

After writing all files, report to the user:

1. The absolute path to the plan file (S/M) or plan directory (L/XL).
2. File count and approximate total line count.
3. Complexity grade, output format, and round count.
4. For directory plans: a list of each round file with its topic (one line per round).
5. The exact execution commands to run:
   - Single-file plan: `/prex -ar .implementation-plans/plans/<slug>.md`
   - Single round: `/prex -ar .implementation-plans/plans/<slug>/<topic>.md`
   - Sequential rounds: list each `/prex -ar` command in order.
   - Full directory: `/prex -ar @.implementation-plans/plans/<slug>/`
6. A reminder that **each `/prex` invocation executes exactly one round** — even when pointing at
   the directory or `README.md`. The executor reads the plan's `QUEUE.yaml`, picks the next `todo`
   round, executes it, and stops. A new `/prex` session is required for each subsequent round.

Do NOT display the full contents of the generated files unless the user asks.

## Orchestrator Invocation Contract (coordinator mode)

The coordinator-mode contract lives in `references/orchestrator-invocation-contract.md`. Read that
reference when this skill is invoked non-interactively by a coordinator such as `plan-writer-multi`.
Normal interactive `/plan-writer` use ignores coordinator mode.


## Guardrails

- This skill only WRITES the plan output. It does not implement anything.
- Do not modify any existing files in the repository (only write to `.implementation-plans/`; in
  coordinator mode, write only to the given scratch `<output-path>`).
- Never overwrite `.implementation-plans/README.md` or rewrite existing entries in
  `.implementation-plans/QUEUE.yaml` — bootstrap-if-missing and append-only, respectively.
- Do not run git commands (no staging, committing, or branching).
- Every plan file must be self-contained — no references to "the conversation", "as we discussed",
  or "see README."
- Do not fabricate code references. If you are unsure about a file's contents, read it in Phase 3
  before citing it.
- If the conversation context is too thin to produce a useful plan (e.g., the user just started
  talking and there is almost nothing to synthesize), say so and suggest the user explore more
  before invoking this skill.
- The generated `README.md` of a directory plan must make the one-round-per-session rule impossible
  to miss. This is a hard constraint, not a suggestion — the execution discipline section is
  load-bearing for how `/prex` consumes the plan.
