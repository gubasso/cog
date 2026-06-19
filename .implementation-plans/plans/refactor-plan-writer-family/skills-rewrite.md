# Rewrite the plan-writer skill family for the new model

> Plan: refactor-plan-writer-family | Round: 3 of 6 | Complexity: L | Generated: 2026-06-19 |
> Repo: /workspaces/cog | Executor: prex (EF 1.5)

## Context

The producer skills must move to the new model: every plan is a directory (no single-file format),
rounds are uncapped, the two-layer decomposition (Layer 1 domain split → one or more flat sibling
dirs; Layer 2 per-dir grade → uncapped round split) is in effect, and the queue files are renamed
(`queue-plans.yaml` root / `queue-rounds.yaml` inner). Skills keep judgment/sequencing in prose and
delegate deterministic mechanics to cog (renamed in Round 2) and to the external spec (rewritten in
Round 1).

Skills in scope this round: `skills/claude/plan-writer` (canonical), `skills/codex/plan-writer`
(read-only non-interactive twin), `skills/claude/plan-writer-multi` (Claude-only coordinator). There
is NO `skills/codex/plan-writer-multi`. The consumer `plan-queue-runner` is Round 4.

Do NOT rename this plan's own `queue-rounds.yaml` (see the plan README's "Scaffolding vs. deliverable"); this
round edits **skill source** only.

## Previous Rounds

Round 1 rewrote the external spec (directory-only, two-layer, uncapped, renamed queues). Round 2
renamed the cog mechanics: `cog plan-init` now writes `queue-plans.yaml`; `cog plan-queue-runner-setup`
resolves `queue-rounds.yaml`; `fn_queue.sh` error strings are generic; the reserved-slug guard covers
`queue-plans` / `queue-rounds`. The skills now point at the new spec sections and call the renamed cog
mechanics.

## Scope of This Round

- **IN scope:** edit the three SKILL.md files (and `plan-writer`'s
  `references/orchestrator-invocation-contract.md`) for directory-always output, uncapped rounds, the
  two-layer model, and the new queue filenames; remove single-file (Phase 6c / Template E) handling;
  **remove the `plan-writer-multi` EF-sanity gate** that auto-rejects 4+ prex rounds; run
  `cog skill-lint` on each touched SKILL.md.
- **OUT of scope:** the consumer `plan-queue-runner` (Round 4), cog docs + ADR (Round 4), tests
  (Round 5), any live `.implementation-plans/` data.

## Current State

### Key Files

- `/workspaces/cog/skills/claude/plan-writer/SKILL.md` (~488 lines). Frontmatter `description` says
  "S/M plans are generated as a single self-contained file (plans/<slug>.md); L/XL plans become a
  directory of self-contained rounds (plans/<slug>/)" — change to "every plan is a directory of one
  or more self-contained rounds". Phase 1d reads the three external references. Phase 5 "Classify
  Complexity" maps grade→format and round count from grade; lines 252–254 read: "The grade selects the
  output format per the grade table in `complexity-heuristic.md` ... S/M → single file
  `$PLANS_DIR/$SLUG.md` (Template E); L/XL → directory `$PLANS_DIR/$SLUG/` (Templates A–D; C for XL
  only)." Phase 6a bootstrap: `cog queue-bootstrap --schema plans --queue "$PLAN_ROOT/QUEUE.yaml"`.
  Phase 6c "Write the single-file plan (S/M only)" (lines ~293–311) — REMOVE. Phase 6g inner queue:
  `cog queue-bootstrap --schema rounds --queue "$PLANS_DIR/$SLUG/QUEUE.yaml"`. Phase 6h registers the
  plan with `item: <slug>` (dir) or `item: <slug>.md` (single — remove the single-file branch). The
  "Writing guidelines" and Phase 7 confirm reference single-file commands and `QUEUE.yaml`.
- `/workspaces/cog/skills/claude/plan-writer/references/orchestrator-invocation-contract.md` (~26
  lines) — the coordinator-mode draft-shape rules reference `QUEUE.yaml` and the S/M (Template E) vs
  L/XL split. Update to directory-only + new filenames.
- `/workspaces/cog/skills/codex/plan-writer/SKILL.md` (~126 lines). Read-only non-interactive twin;
  emits ONE plan draft as final message; never writes repo files. Step 4 describes "S/M → a
  single-file plan body (Template E shape)" and "L/XL → one structured document describing the
  directory plan inline". Echoes `cog queue-bootstrap ... QUEUE.yaml` mechanics in prose (lines
  ~93–106). "Plan contract" mentions "Template E for S/M".
- `/workspaces/cog/skills/claude/plan-writer-multi/SKILL.md` (~340 lines). Inline coordinator: runs
  Claude (Agent) + Codex (cog codex-runner) plan-writers in parallel, then synthesizes. Phase 8
  contains an **"EF-sanity gate (before reconciling)"** subsection stating that a draft proposing "XL
  or 4+ rounds under prex (EF 1.5)" applied the EF incorrectly and must be down-weighted/re-graded —
  this gate contradicts uncapped rounds and must be removed/reworked. Phase 8 also references the
  grade→format table and `QUEUE.yaml` at both levels (lines ~271–337). It already documents the
  optional `repos:` satellite list for plans that implement into another repo.

### Existing Patterns

- Skills keep judgment in prose; deterministic routines delegate to `cog` subcommands / `cog::fn::*`
  (ADR 0008). Validate against `docs/reference/skill-contract.md`; run `cog skill-lint`.
- The grade table is owned by the external spec — skills "point here", they do not restate the
  mapping.
- Source and installed skill copies are byte-identical; edit the **source** under `skills/` (the user
  re-syncs installed copies under `$HOME/.claude/skills/` separately — note it, do not hand-edit both).

## Implementation Steps

### First Step: Mark this round as started

In this plan's `queue-rounds.yaml`, set this round's (`item: skills-rewrite`) `status` to `doing`.

### Step 1: `plan-writer` (Claude) frontmatter + Phase 5

- Frontmatter `description`: replace the "S/M single-file vs L/XL directory" language with "every plan
  is a directory of one or more self-contained rounds, each sized for one prex run".
- Phase 5: remove grade→format selection (everything is a directory). Keep the 5-axis scoring + EF +
  adjusted grade as a **descriptive** difficulty/sizing signal. Add the two-layer model: Layer 1
  (domain/scope split → one or more flat sibling plan dirs under `plans/`, related via top-level
  `depends_on` + shared slug prefix); Layer 2 (per-dir grade + uncapped round split). Remove the
  "round count from grade" cap and any "XL unreachable / recompute if 4+ rounds" language — round
  count is scope-driven and uncapped. Point at the rewritten spec sections.

### Step 2: Remove single-file handling and rename queues in `plan-writer` Phase 6

- Delete Phase 6c "Write the single-file plan (S/M only)" entirely. Make the directory path
  (6b/6d–6h) apply to ALL plans, including a one-round plan (still a directory with `README.md`, one
  round file, and `queue-rounds.yaml`).
- Phase 6a: `cog queue-bootstrap --schema plans --queue "$PLAN_ROOT/queue-plans.yaml"`.
- Phase 6g: `cog queue-bootstrap --schema rounds --queue "$PLANS_DIR/$SLUG/queue-rounds.yaml"` and the
  matching `cog queue-append --schema rounds --queue "$PLANS_DIR/$SLUG/queue-rounds.yaml" ...`.
- Phase 6h: register with `item: <slug>` (always a dir) and
  `prompt: /prex -ar @.implementation-plans/plans/<slug>/`; remove the `<slug>.md` single-file branch
  and its prompt form; register into `$PLAN_ROOT/queue-plans.yaml`. Add Layer-1 guidance: when the
  domain split produced N sibling dirs, append one top-level entry per dir with `depends_on` wiring +
  a shared slug prefix.
- "Writing guidelines" + Phase 7 confirm: drop single-file commands; reference `queue-rounds.yaml` /
  `queue-plans.yaml`; remove "Template E" mentions.

### Step 3: `plan-writer` orchestrator-invocation-contract reference

- Update `references/orchestrator-invocation-contract.md` so the coordinator-mode draft shape is
  directory-only (no Template E / single-file body) and uses the new queue filenames. A coordinator
  draft for any plan describes a directory plan inline (README body + round files + inner
  `queue-rounds.yaml`), and may describe multiple sibling dirs when Layer 1 splits by domain.

### Step 4: `plan-writer` (Codex twin)

- Mirror the model change: directory-only output, uncapped rounds, the two-layer decomposition.
  Replace the Template E / single-file body references (incl. Step 4 "S/M → single-file plan body")
  with directory-only output; allow the twin to emit one OR MORE sibling implementation-dir drafts
  (each with README body + round bodies + inner `queue-rounds.yaml`, plus a proposed top-level
  `queue-plans.yaml` entry list). Update the echoed `cog` mechanics prose to `queue-plans.yaml` /
  `queue-rounds.yaml`. Preserve its read-only, emit-one-final-message contract (never writes repo
  files).

### Step 5: `plan-writer-multi` (coordinator) — incl. removing the EF-sanity gate

- **Remove the "EF-sanity gate (before reconciling)" subsection** in Phase 8 (the rule treating "XL
  or 4+ rounds under prex" as an EF-application error). Replace it, if anything, with a brief note
  that round count is scope-driven and uncapped, and that the judge compares drafts on **domain-split
  quality (Layer 1)** and **per-dir round-split quality (Layer 2)** instead of policing a round
  ceiling.
- Update Phase 8 synthesis/reconciliation to the directory-always model and the new queue filenames at
  both levels; remove grade→format selection. The final output may be a single dir or **multiple flat
  sibling dirs** (Layer 1) — register each via `cog queue-append --schema plans --queue
  "$PLAN_ROOT/queue-plans.yaml"` with `depends_on` wiring, and bootstrap/append each dir's
  `queue-rounds.yaml`.
- Keep the parallel Claude(Agent) + Codex(cog codex-runner) fan-out and the `repos:` satellite
  handling. Ensure it still instructs each inner `queue-rounds.yaml` to carry `repos:` when that
  plan implements into a satellite repo.

### Step 6: Lint the touched skills

- Run `cog skill-lint` on each touched SKILL.md and resolve findings. Validate against
  `docs/reference/skill-contract.md` (judgment in prose; mechanics delegated to cog). Note in the
  round summary that the installed copies under `$HOME/.claude/skills/` must be re-synced by the user.

### Final Step: Update the queue

1. In this plan's `queue-rounds.yaml`, set this round's (`item: skills-rewrite`) `status` to `done`.

## Acceptance Criteria

- [ ] No skill references a single-file plan format, Template E, or `<slug>.md` plan output.
- [ ] All three skills (+ the orchestrator-invocation-contract reference) use `queue-plans.yaml` /
      `queue-rounds.yaml`; no `QUEUE.yaml` literal remains in them.
- [ ] `plan-writer` Phase 5 documents the two-layer model and uncapped rounds; grade is descriptive,
      not a format selector or round cap.
- [ ] `plan-writer-multi` no longer contains an EF-sanity gate that rejects 4+ prex rounds, and can
      synthesize multiple flat sibling plan dirs with top-level `depends_on`.
- [ ] The Codex twin can emit one or more directory-plan drafts and references the new filenames.
- [ ] `cog skill-lint` passes on each touched SKILL.md.
- [ ] This plan's `queue-rounds.yaml` shows round `skills-rewrite` as `done`.

## Next Round

Round 4 updates the consumer `plan-queue-runner` (reads the inner queue), the cog docs that mention
the queue postcondition, and records a superseding ADR for the format change + rename.
