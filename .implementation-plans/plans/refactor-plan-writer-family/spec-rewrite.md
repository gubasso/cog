# Rewrite the external plan-rounds spec for the new model

> Plan: refactor-plan-writer-family | Round: 1 of 6 | Complexity: L | Generated: 2026-06-19 |
> Repo: /workspaces/cog | Executor: prex (EF 1.5)

## Context

The `plan-writer` skill family generates implementation plans under `.implementation-plans/`. The
heuristic, lifecycle, and templates that drive grade→format, round-splitting, and queue filenames are
the **single source of truth** — and they live in a SEPARATE repo, `/home/gbasso/DocsNNotes`, under
`tech/tools/claude-code/plan-rounds/`. Four changes originate HERE and everything else points at this
spec:

1. **Retire single-file plans** — every plan is a directory (even a one-round plan).
2. **Remove the round cap** — round count is driven by scope/cohesion, not by grade or the prex EF
   ceiling.
3. **Two-layer decomposition** — Layer 1: domain/scope split into one or more flat sibling plan dirs
   under `plans/`, related via the top-level queue's `depends_on` + shared slug prefix; Layer 2:
   per-dir grade + uncapped round split. Grade is retained but descriptive.
4. **Rename queue files** — root `QUEUE.yaml` → `queue-plans.yaml`; inner `QUEUE.yaml` →
   `queue-rounds.yaml`.

This is a **satellite-repo** round: all edits are in `/home/gbasso/DocsNNotes`. The spec is
foundational — skills and cog README text point at it — so it lands first.

## Previous Rounds

This is the first round — no prior rounds.

## Scope of This Round

- **IN scope:** edit the three spec files in
  `/home/gbasso/DocsNNotes/tech/tools/claude-code/plan-rounds/` —
  `complexity-heuristic.md`, `plan-lifecycle.md`, `round-templates.md` — to encode directory-only
  plans, the two-layer decomposition, uncapped rounds, and the queue rename. Also check the sibling
  `AGENTS.md` / `README.md` in that folder for restated retired rules and update them.
- **OUT of scope:** any edits in `/workspaces/cog` (cog commands, skills, tests, docs) — later rounds.
  Do NOT migrate or rename any live `.implementation-plans/` data in either repo. Do NOT rename this
  plan's own `QUEUE.yaml` (see the plan README's "Scaffolding vs. deliverable").

## Current State

### Key Files

- `/home/gbasso/DocsNNotes/tech/tools/claude-code/plan-rounds/complexity-heuristic.md` — the grade
  mapping + EF ceiling. The **"Grade mapping" table** currently has these columns: Grade | Adjusted |
  Rounds | Output format | Notes. Its Output-format column reads "Single file `plans/<slug>.md`" for
  S and M and "Directory `plans/<slug>/`" for L and XL; its Rounds column reads S=1, M=1, L=2–3,
  XL=4–8. The section **"EF is mandatory — reachable grades per executor"** encodes the cap with a
  table whose "Max rounds" column says "3 (L)" for prex, and the prose: "Under the default `prex`
  executor, **XL is unreachable** (max adjusted 13.3 → L) ... If a classification yields XL or 4+
  rounds under prex, the EF was not applied: recompute." A closing line states: "This grade table is
  the **single source of truth for grade→format**." The five scoring axes, the EF table (prex 1.5 /
  single-pass 1.0 / limited 0.8), the override guidance, and the "Round-splitting rules" (1–7) all
  stay (lightly updated).
- `/home/gbasso/DocsNNotes/tech/tools/claude-code/plan-rounds/plan-lifecycle.md` — the
  directory-structure diagram shows BOTH `<slug>.md` (single-file) AND `<slug>/` (dir); the prose
  says "an **S/M plan is a single file** (`plans/<slug>.md`) ... an **L/XL plan is a directory**".
  Reserved slugs are `readme`, `queue`, `strategy`. Queue source-of-truth semantics name `QUEUE.yaml`
  at both levels (sections "The queues are the source of truth", "`README.md` and `QUEUE.yaml`
  roles", "Lifecycle rules"). The "Executor capacity model" (Codex 600s/stage, single write session,
  ~<300 lines plan text) stays. The "Migrating a legacy `.plan/` tree" section references
  `_QUEUE.yaml` → `QUEUE.yaml`.
- `/home/gbasso/DocsNNotes/tech/tools/claude-code/plan-rounds/round-templates.md` — Templates A–F.
  **Template E** is the single-file plan (to retire). The format-selector preamble (top of file) maps
  S/M → Template E and L/XL → Templates A–D. **Template D** ("`QUEUE.yaml`", two flavors: inner
  `rounds:` and top-level `plans:`) and the structure diagrams hardcode `QUEUE.yaml`. Template A and
  Template B bodies say "this plan's `QUEUE.yaml`" and "`.implementation-plans/QUEUE.yaml`". Template
  F (root README) hardcodes `QUEUE.yaml` and shows the `<slug>.md` single-file line. The top-level
  ledger example in Template D includes an `item: {{SLUG}}.md` single-file entry. Reserved-name notes
  for topic slugs appear in Templates A and the slug conventions.

### Existing Patterns

- The spec is the single source of truth; skills/coordinators "point here" and must not restate the
  grade mapping. Keep that discipline.
- Markdown fenced code blocks must declare a language (MD040 — use `text` when generic).

## Implementation Steps

### First Step: Mark this round as started

In this plan's `QUEUE.yaml`, set this round's (`item: spec-rewrite`) `status` to `doing`.

### Step 1: Rewrite grade→format and remove the cap in `complexity-heuristic.md`

- In the "Grade mapping" table, change the **Output format** column to "Directory `plans/<slug>/`" for
  **all** grades (S/M/L/XL); remove the "Single file `plans/<slug>.md`" entries. Replace the closing
  "single source of truth for grade→format" line with "single source of truth for the difficulty
  grade" (format is no longer grade-selected — every plan is a directory).
- Turn the **Rounds** column into descriptive guidance, not a ceiling — e.g., S/M "typically 1", L
  "several", XL "many" — and add a sentence that round count is ultimately set by the Layer-2
  round-splitting rules and is **uncapped**.
- Rewrite the section "EF is mandatory — reachable grades per executor": KEEP the adjusted-score
  computation (raw ÷ EF) and the grade mapping, but REMOVE the per-executor "Max rounds" ceiling
  column and the "XL is unreachable under prex" / "If a classification yields XL or 4+ rounds under
  prex, the EF was not applied: recompute" rule. Replace with: the EF still maps complexity to a
  descriptive grade; round count is then chosen by the round-splitting rules, uncapped; under any
  executor, more rounds are valid when the work needs them — the hard ceiling is per-round
  `/prex` capacity, not a count.

### Step 2: Add the two-layer decomposition to `complexity-heuristic.md`

- Add a new section ("Two-layer decomposition") describing **Layer 1** (group tasks by domain/scope
  into one or more **flat sibling** plan dirs under `plans/`, related via the top-level queue's
  `depends_on` + a shared slug prefix; one domain → one dir, N domains → N dirs) and **Layer 2**
  (grade the difficulty of each dir with the 5 axes + EF, then split into uncapped rounds). State
  explicitly that the grade is **per-dir and descriptive** — it no longer selects a format or caps
  round count.
- Make explicit the distinction between "multiple implementation **dirs**" (Layer 1, top-level
  `queue-plans.yaml` + `depends_on`) and "multiple **rounds** in one dir" (Layer 2, inner
  `queue-rounds.yaml`) so future skills don't collapse the two layers.
- Keep the "Round-splitting rules" (module/layer/dependency/cohesion/atomic/foundations/
  tests-with-code) as the Layer-2 rules and reinforce the prex sizing goal (a good `/prex` chunk;
  ~<300 lines plan text; one Codex 600s session; never so small a `/prex` session is wasteful).

### Step 3: Retire single-file format in `plan-lifecycle.md`

- Update the directory-structure diagram to show ONLY `<slug>/` directories under `plans/` (remove
  the `<slug>.md` single-file line). Rename `QUEUE.yaml` → `queue-plans.yaml` (root) and
  `queue-rounds.yaml` (inner) throughout the diagram and prose.
- Rewrite the prose "an S/M plan is a single file ... an L/XL plan is a directory" to "every plan is a
  directory" and describe the two-layer model + uncapped rounds.
- Update the sections "The queues are the source of truth", "`README.md` and `QUEUE.yaml` roles", and
  "Lifecycle rules" to the new filenames; remove the "Single-file plans have no inner queue ..."
  carve-outs (every plan now has an inner `queue-rounds.yaml`).
- Update the reserved-slug list to also cover the new meta stems (`queue-plans`, `queue-rounds`)
  alongside `readme`, `queue`, and `strategy` — coordinate the exact set with Round 2's guard change
  (the recommendation in Round 2 is to reserve `readme`, `strategy`, `queue`, `queue-plans`,
  `queue-rounds`).
- Leave the "Migrating a legacy `.plan/` tree" section as a historical note, but update its filename
  references to the new names where it describes the CURRENT target layout.

### Step 4: Update templates in `round-templates.md`

- **Remove Template E** (single-file plan) and every reference to it: the format-selector preamble at
  the top, the "S/M → Template E" mapping, and the Template D top-level-ledger `item: {{SLUG}}.md`
  example entry. Update the preamble to say every plan is a directory built from Templates A/B/D (and
  C for XL).
- Rename `QUEUE.yaml` → `queue-rounds.yaml` (inner) and `queue-plans.yaml` (root) in Template D, the
  structure diagrams, and Template F. In Template A and Template B bodies, replace every "this plan's
  `QUEUE.yaml`" with "this plan's `queue-rounds.yaml`" and every "`.implementation-plans/QUEUE.yaml`"
  with "`.implementation-plans/queue-plans.yaml`".
- Update Template F (root README) structure diagram + queue-semantics prose to directory-only and the
  new filenames; remove its `<slug>.md` single-file line and the "Single-file plans flip their entry
  ..." sentence.

### Step 5: Sweep the satellite folder for retired rules

- Check `/home/gbasso/DocsNNotes/tech/tools/claude-code/plan-rounds/AGENTS.md` and `README.md` (and
  any other file in that folder) for restated single-file / round-cap / grade→format / `QUEUE.yaml`
  language and update to match the new model.
- Grep that folder for stragglers: `QUEUE.yaml`, `plans/<slug>.md`, `Template E`, `single-file`,
  `single file`, `max rounds`, `4+ rounds`, `XL is unreachable`. Fix any product references (keep
  intentional historical/migration notes, updated to the new target names).

### Final Step: Update the queue

1. In this plan's `QUEUE.yaml`, set this round's (`item: spec-rewrite`) `status` to `done`.

## Acceptance Criteria

- [ ] No spec file under `/home/gbasso/DocsNNotes/tech/tools/claude-code/plan-rounds/` describes a
      single-file plan format or Template E as a generated format.
- [ ] The grade mapping shows "Directory `plans/<slug>/`" for all grades; no per-grade round ceiling
      and no "XL unreachable under prex / recompute if 4+ rounds" rule remains.
- [ ] A "Two-layer decomposition" section documents Layer 1 (domain split → flat sibling dirs via
      top-level `depends_on`) and Layer 2 (per-dir grade → uncapped rounds), with the grade explicitly
      per-dir/descriptive.
- [ ] All three spec files use `queue-plans.yaml` (root) and `queue-rounds.yaml` (inner) — no
      `QUEUE.yaml` remains in that folder except intentionally historical notes updated to new names.
- [ ] The reserved-slug list in the spec covers `queue-plans` and `queue-rounds`.
- [ ] Markdown fenced blocks all declare a language.
- [ ] This plan's `QUEUE.yaml` shows round `spec-rewrite` as `done`.

## Next Round

Round 2 renames the queue-filename literals in cog's deterministic mechanics (`cmd_plan_init.sh`,
`cmd_plan_queue_runner_setup.sh`), generalizes the `fn_queue.sh` error strings, and extends the
reserved-slug guard to the new meta stems.
