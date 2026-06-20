---
name: plan-writer
description: >
  Synthesize the current conversation into an executor-aware implementation plan
  under .implementation-plans/plans/. Evaluates complexity (S/M/L/XL): every
  plan is generated as one or more plan directories under
  `.implementation-plans/plans/`; each directory holds self-contained round
  files sized for one `/executor-prex -ar` run. Includes an interactive
  interview to clarify scope, alternatives, and decisions before generating.
  Use when the user says "plan-writer", "write a plan", "capture this as a plan",
  or wants to export conversation findings as actionable implementation documents.

  Optional flag: --executor <prex|single-pass|limited> overrides the default
  executor assumption used to size rounds. The default is `prex` — assumes the
  `/executor-prex` pipeline (Codex plan → Claude review → Codex implement → Claude
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
<!-- cog-skill: plan-emitter -->

# Plan Writer

Synthesize the current conversation into an executor-aware implementation plan under
`.implementation-plans/plans/` — one or more directories of self-contained round files, each sized
for one `/executor-prex` run and executable by a fresh LLM session with ZERO assumptions about prior
conversation. Runs **inline** (no fork): it needs full access to the live conversation to extract
decisions, findings, and explored code.

<!-- cog-plan-mode-gate -->
**Plan-mode gate (before anything else):** if Claude Code **plan mode** is active (a system-reminder
says plan mode is on / that you must not edit; `Shift+Tab` or `/plan`), **STOP** before parsing args,
researching, interviewing, or writing — this skill writes the plan under `.implementation-plans/` and
cannot run read-only. Tell the user in one line to exit plan mode (`Shift+Tab`) and re-invoke; do not
call `ExitPlanMode` yourself.

## Reference resolution

The plan-rounds references ship with `cog` and resolve in-repo (or from the XDG deploy) via
`cog skill-refs path <rel>`. Resolve each at the point of use, e.g.
`$(cog skill-refs path plan-rounds/round-templates.md)`. The resolver always succeeds, so no
graceful-degrade fallback is needed for these references.

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

The slug names a plan directory under `$PLANS_DIR/$SLUG/`. Phase 5 may split the work into multiple
flat sibling directories that share a slug prefix.

### 1b — Collision check

If `$PLANS_DIR/$SLUG/` exists and is non-empty, ask the user:
`[u]pdate (overwrite; rely on git/filesystem history), [a]bort, [r]ename (append suffix)?`

Do not silently overwrite. When Phase 5 splits the work into multiple flat sibling directories, the
sibling slugs are not known yet here — re-run this same collision check for every planned sibling
directory in Phase 6b, once the Layer 1 split is decided and before any writes.

### 1c — Validate

If `cog plan-init` reports that `$PLAN_ROOT` cannot be created or validated, report the
error and stop.

If a legacy `$REPO_ROOT/.plan/` directory exists, inform the user that this repo still carries
plans in the legacy layout (migration is manual — see `plan-lifecycle.md` § "Migrating a legacy
`.plan/` tree") and continue with the new layout. Do not migrate automatically. `plan-init` reports
this as `legacy_plan_dir`; the judgment and user-facing explanation stay in this skill.

### 1d — Load shared references

Read all three reference files into context:

- `$(cog skill-refs path plan-rounds/plan-lifecycle.md)` — directory structure,
  executor model, lifecycle rules.
- `$(cog skill-refs path plan-rounds/complexity-heuristic.md)` — scoring axes,
  grade mapping, splitting rules.
- `$(cog skill-refs path plan-rounds/round-templates.md)` — directory-plan
  templates, round files, `README.md`, `queue-plans.yaml`, `queue-rounds.yaml`, optional
  `STRATEGY.md`.

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
`$(cog skill-refs path plan-rounds/complexity-heuristic.md)`.

State the executor profile and EF up front (from Phase 1a): `Executor: $EXECUTOR (EF = <factor>)`.

1. Score each axis (1–4).
2. Sum to produce the **raw score** (5–20).
3. Divide the raw score by the EF to produce the **adjusted score**.
4. Map the **adjusted score** to grade: S / M / L / XL per the table in `complexity-heuristic.md`.
5. Apply override judgment if the formula does not fit (document the reason).

Use the grade as a sizing signal, not a format selector or round cap. Apply the two-layer model:

- **Layer 1** — split by domain/scope into one or more flat sibling plan directories under `plans/`,
  wired with top-level `depends_on` for ordering. **Plan directories are always direct children of
  `plans/` (`plans/<slug>/`) — never nest a plan directory inside another, and never create
  subdirectories inside a plan directory.** Relationships and execution order are expressed **only**
  through `depends_on` in the queue files, never through the filesystem. A "shared slug prefix" is a
  naming convention (e.g. `auth-backend`, `auth-frontend`), not a parent directory.
- **Layer 2** — for each directory, use the adjusted grade as a sizing signal only, then split into
  uncapped, scope-driven rounds.

Report the classification to the user:

- The grade with a one-sentence rationale.
- Per-axis scores plus EF in brief form (e.g., "files:2 cross-cut:1 deps:2 novelty:3 risk:2 → raw 10
  ÷ EF 1.5 (prex) → 6.7 → M").
- The proposed Layer 1 directory split.
- Each directory's Layer 2 round split with topic summaries. Get user confirmation before
  generating.

## Phase 6: Generate Output

### 6a — Bootstrap the plan root

Ensure the shared root files exist by delegating to the helper. It creates missing root files only
and never overwrites existing ones:

```bash
cog plan-init --repo-root "$REPO_ROOT" --json
cog queue-bootstrap --schema plans --queue "$PLAN_ROOT/queue-plans.yaml" --json
```

The helper-owned bootstrap covers:

- `$PLAN_ROOT/README.md` — static explainer of the plan system, from Template F in
  `$(cog skill-refs path plan-rounds/round-templates.md)`.
- `$PLAN_ROOT/queue-plans.yaml` — the repo-wide ledger. If missing, create it with an empty
  `plans:` list per Template D.

### 6b — Plan the Layer 1 directories and Layer 2 rounds

Decide whether the work is one plan directory or multiple flat sibling directories. Every plan
directory is a direct child of `$PLANS_DIR` (`$PLANS_DIR/<slug>/`) — never nested under another plan
directory and never containing plan subdirectories; ordering between siblings lives only in
`depends_on`. Once the Layer 1 split is known, run the Phase 1b collision check for **every** planned
sibling directory (`$PLANS_DIR/<sibling-slug>/`), not just the base `$SLUG` — do not silently
overwrite any existing non-empty sibling directory. For each directory, apply the round-splitting rules from
`$(cog skill-refs path plan-rounds/complexity-heuristic.md)` and assign each
implementation step to an uncapped, scope-driven round. Verify no circular dependencies between
rounds or sibling directories. Use `cog plan-slug` to validate every round topic slug; the helper
owns charset, max-length, and the reserved-name set.

Steps 6c–6f below produce **one complete plan directory**. When Layer 1 split the work into multiple
flat sibling directories, repeat 6c–6f for **each** sibling directory, substituting that sibling's
slug for `$SLUG` throughout (read the per-directory steps with a per-sibling `$SLUG`). Each sibling
must be a fully executable plan in its own right: its own `README.md`, optional `STRATEGY.md`, round
files, and `queue-rounds.yaml`. Only after every sibling directory is written do you register them in
6g.

### 6c — Write the plan directory `README.md`

Create `$PLANS_DIR/$SLUG/` and write `$PLANS_DIR/$SLUG/README.md` using Template B from
`$(cog skill-refs path plan-rounds/round-templates.md)`.

Include:

- Full problem statement.
- Strategy summary (how the work is split and why).
- A rounds overview that mirrors the plan's `queue-rounds.yaml` (which is the source of truth for
  round order and status — do not duplicate status into prose that can drift).
- Exact execution commands (`/executor-prex -ar` per-round or full-directory; `/prex` remains a
  supported compatibility form for existing queues).
- **Execution discipline section** — a prominent, clearly labeled section (not just a bullet) that
  states the following rules unambiguously:
  1. **One round per `/executor-prex` session.** Each round executes in its own isolated
     `/executor-prex` invocation. Never execute multiple rounds in a single session.
  2. **Directory or README invocation selects one round, not all.** When the executor receives the
     plan directory (`/executor-prex -ar @.implementation-plans/plans/<slug>/`) or the `README.md`
     (`/executor-prex -ar .implementation-plans/plans/<slug>/README.md`), it MUST read this plan's
     `queue-rounds.yaml`, identify the first round with status `todo`, execute ONLY that single round,
     then stop. It does NOT proceed to the next round in the same session.
  3. **Status flips.** When starting a round, set its `status` to `doing` in the plan's
     `queue-rounds.yaml`; on completion, set it to `done`. A crashed or interrupted session thus
     leaves a visible `doing` marker.
  4. **Sequential sessions.** After completing a round (marking it `done` in the plan's
     `queue-rounds.yaml`), the executor session ends. The user launches a new `/executor-prex`
     session for the next round.
  5. **Why:** Fresh sessions prevent context contamination between rounds, keep token usage
     predictable, and allow the user to review intermediate results before proceeding.
- Decisions and constraints from the interview (with reasoning). **Always include a
  `Executor: $EXECUTOR (EF <factor>)` line** here so a future re-plan or re-execution knows which
  capability assumption sized the rounds.
- Rejected alternatives (with reasons for rejection).
- Risks and edge cases that span the full plan.

### 6d — Write optional `STRATEGY.md`

When the external plan-rounds spec calls for a separate strategy document, write
`$PLANS_DIR/$SLUG/STRATEGY.md` using Template C from
`$(cog skill-refs path plan-rounds/round-templates.md)`.

Include: architectural overview, round dependency graph, risk mitigation approach, cross-cutting
concerns that span multiple rounds.

### 6e — Write round files

For each round, write `$PLANS_DIR/$SLUG/<topic>.md` (a kebab-case topic slug, **no number
prefix** — round order lives in the plan's `queue-rounds.yaml`) using Template A from
`$(cog skill-refs path plan-rounds/round-templates.md)`.

Each round file must be **self-contained** per the contract in
`$(cog skill-refs path plan-rounds/plan-lifecycle.md)`:

- The `## Context` section repeats the problem statement compactly (10–20 lines). No "see README" or
  "as discussed" references.
- `## Current State` includes code references relevant to THIS round (absolute paths, quoted
  excerpts).
- `## Previous Rounds` describes what earlier rounds produced (expected state, not actual).
- `## Scope of This Round` explicitly names what is in and out of scope.
- `## Acceptance Criteria` is specific to this round and independently verifiable.
- `## Next Round` previews what comes next (or states "Final round").

### 6f — Write the plan's inner `queue-rounds.yaml`

Create `$PLANS_DIR/$SLUG/queue-rounds.yaml` through the helper and append one round entry at a time in
execution order. Each entry still follows Template D: `item` (the round's `<topic>`),
`status: todo`, `depends_on` (list of earlier round `<topic>`s, or `[]`),
`prompt: /executor-prex -ar .implementation-plans/plans/<slug>/<topic>.md`, and `notes`.

```bash
cog queue-bootstrap --schema rounds --queue "$PLANS_DIR/$SLUG/queue-rounds.yaml" --json
cog queue-append \
  --schema rounds \
  --queue "$PLANS_DIR/$SLUG/queue-rounds.yaml" \
  --item "$TOPIC" \
  --status todo \
  --depends-on "$DEPENDS_ON_CSV" \
  --prompt "/executor-prex -ar .implementation-plans/plans/$SLUG/$TOPIC.md" \
  --notes "$NOTES" \
  --json
```

### 6g — Register the plan in the top-level `queue-plans.yaml`

Append an entry to `$PLAN_ROOT/queue-plans.yaml` (created in 6a if it did not exist) through the
helper:

- `item: <slug>` always names a directory.
- `status: todo`, `depends_on` (other plan `item`s, or `[]`), and `notes`.
- `prompt: /executor-prex -ar @.implementation-plans/plans/<slug>/`.
- If Layer 1 produced multiple sibling directories, append one top-level entry per directory,
  sharing a slug prefix and wired with `depends_on` for ordering.

```bash
cog queue-append \
  --schema plans \
  --queue "$PLAN_ROOT/queue-plans.yaml" \
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
  started" that sets the round's `status` to `doing` in the plan's `queue-rounds.yaml`, and end with
  a "Final Step: Update the queue" that sets it to `done`. Both steps are defined in Template A and
  must not be omitted.
- The **last round** must additionally instruct the executor to set this plan's `status` to `done`
  in the top-level `.implementation-plans/queue-plans.yaml`. The plan directory stays in place —
  **nothing is moved on disk** (there are no `01-todo`/`02-done` directories). This is defined in
  Template A's final-round conditional and must not be omitted.
- Prefer concrete examples over abstract descriptions.
- Include enough code context that the implementor can locate the exact insertion point or
  modification target.

## Phase 7: Confirm

After writing all files, report to the user:

1. The absolute path to the plan directory or directories.
2. File count and approximate total line count.
3. Complexity grade and round count per directory.
4. A list of each round file with its topic (one line per round).
5. The exact execution commands to run:
   - Single round: `/executor-prex -ar .implementation-plans/plans/<slug>/<topic>.md`
   - Sequential rounds: list each `/executor-prex -ar` command in order.
   - Full directory: `/executor-prex -ar @.implementation-plans/plans/<slug>/`
6. A reminder that **each `/executor-prex` invocation executes exactly one round** — even when pointing at
   the directory or `README.md`. The executor reads the plan's `queue-rounds.yaml`, picks the next
   `todo` round, executes it, and stops. A new `/executor-prex` session is required for each
   subsequent round.

Do NOT display the full contents of the generated files unless the user asks.

## Orchestrator Invocation Contract (coordinator mode)

The coordinator-mode contract lives in `references/orchestrator-invocation-contract.md`. Read that
reference when this skill is invoked non-interactively by a coordinator such as `plan-writer-multi`.
Normal interactive `/plan-writer` use ignores coordinator mode.


## Guardrails

- This skill only WRITES the plan output. It does not implement anything.
- **Flat layout is a hard constraint.** Every plan directory is a direct child of
  `.implementation-plans/plans/` (`plans/<slug>/`). Never nest a plan directory inside another and
  never create subdirectories within a plan directory; relationships and order live only in
  `depends_on`. `cog plan-init`, `cog review-implementation-plans-scan`, and `cog runner-queue-resolve-plan`
  fail closed on any nested plan.
- Do not modify any existing files in the repository (only write to `.implementation-plans/`; in
  coordinator mode, write only to the given scratch `<output-path>`).
- Never overwrite `.implementation-plans/README.md` or rewrite existing entries in
  `.implementation-plans/queue-plans.yaml` — bootstrap-if-missing and append-only, respectively.
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
  load-bearing for how `/executor-prex` consumes the plan.
