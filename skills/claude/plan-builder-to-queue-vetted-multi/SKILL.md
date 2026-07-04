---
name: plan-builder-to-queue-vetted-multi
description: >
  Build a fully-vetted, complexity-right-sized, executor-routed multi-round implementation plan into the
  cog plan vault using dual-engine generation and dual-engine review: generate one full-scope plan with
  plan-vetted, cross-review it with review-plan-multi, grade complexity, split recursively to the
  single-session ceiling, match an executor to each round, and write the vault plan with executor-stamped
  queue prompts. The plan is full-scope and never summarized; length is resolved by splitting into rounds.
  Use when the user says "plan-builder-to-queue-vetted-multi", "vetted-multi plan builder", "build a
  dual-vetted executor-routed plan".
argument-hint: "[--store auto|local|global] [--title <text>] <orientation/focus/goal>"
disable-model-invocation: true
allowed-tools: Bash Read Write Edit Grep Glob Skill Agent AskUserQuestion
---

<!-- trigger-tests: "plan-builder-to-queue-vetted-multi", "vetted-multi plan builder", "build a dual-vetted executor-routed plan" -->
<!-- cog-skill: plan-emitter -->

# Plan Builder To Queue Vetted Multi

Build one fully-vetted, complexity-right-sized, executor-routed multi-round plan and land it in the
**cog plan vault** as executor-stamped queue items. This is an **inline coordinator**: the interview,
generation, and dual-engine review run in the live session; only the reviewers owned by
`review-plan-multi` cross fresh-context boundaries. It writes vault artifacts, so run it in a
**write-capable session** — native plan mode is read-only and would block its writes; if plan mode is
active, exit it before invoking.

## Inputs

`$ARGUMENTS` accepts an optional leading `--store auto|local|global` and `--title <text>`, then the
required orientation/focus/goal text that shapes the plan. If the orientation is empty, ask for one.

## Reference resolution

The plan-rounds references ship with `cog` and resolve at point of use; the resolver always succeeds:

```bash
TEMPLATES="$(cog skill-refs path plan-rounds/round-templates.md)"
SPLIT_CONTRACT="$(cog skill-refs path plan-rounds/round-splitting-contract.md)"
RUBRIC="$(cog skill-refs path plan-rounds/complexity-rubric.md)"
```

## Phase 0 — Pre-flight (deterministic)

Resolve the vault and create run state. The setup verb parses flags, makes the run dir, derives the
repo root and title, ensures the global vault exists git-by-default, and resolves the store:

```bash
cog plan-builder-to-queue-setup --json "$ARGUMENTS"
```

Capture `RUN_DIR`, `REPO_ROOT`, `ORIENTATION_FILE`, `TITLE`, `STORE`, `PLAN_ROOT`, `PLANS_DIR`,
`QUEUE_PATH`, `REQUEST_PATH`, `BRIEF_BODY`, `BRIEF_FILE`, `DRAFT_PATH`, `REVIEW_PATH`, and `WORK_DIR`.
`BRIEF_BODY`, `BRIEF_FILE`, and `REVIEW_PATH` are setup outputs retained for compatibility but unused
by this skill because `plan-vetted` and `review-plan-multi` own their own briefs. Shell state does not
persist; substitute literal paths into later calls. Stay producer-blind: locate output only through
these resolved paths (and `cog plan new` / `cog plan path`), never a hardcoded
`.implementation-plans/`. If a `--store local` resolve fails closed as untrusted, surface the
`cog plan trust` instruction it prints and stop.

## Phase 1 — Interview, then generate one full-scope plan with `plan-vetted` (inline)

Interview the operator with `AskUserQuestion` to settle open decisions (2–3 concrete questions only
when the orientation leaves them open; record skill-chosen defaults for anything deferred). Then chain
`plan-vetted` as a fresh full run — a `claude-delegate` Agent, or an inline-chain (read
`$HOME/.claude/skills/plan-vetted/SKILL.md` and follow it in this context) — never through the `Skill`
tool (`plan-vetted` sets `disable-model-invocation`), with the orientation and the decisions settled
above, writing its vetted plan to `DRAFT_PATH`:

- Run `plan-vetted` in this same context so its own `AskUserQuestion` interview reaches the operator.
- Pass the orientation as the prompt plus `--output "$DRAFT_PATH"`. `plan-vetted` accepts
  `<prompt-or-plan-path> [--output <abs.md>]`; passing orientation text takes its `needs-plan` route.

The draft is the maximally-complete **parent round** the rest of the pipeline right-sizes. It must be
full scope: every phase, stage, and step in dependency order; concrete files and exact commands;
machine-checkable acceptance criteria; explicit scope and out-of-scope; and an end-to-end
verification step. Do not summarize, collapse steps, use "etc.", or impose a size cap. Length is
never trimmed here; Phase 4-5 converts length into rounds.

## Phase 2 — Stamp requirement IDs

Stamp plan-scoped `R<n>` IDs onto the draft's acceptance criteria **before any split**, so downstream
coverage can anchor:

```bash
cog round-req stamp "$DRAFT_PATH" --json
```

## Phase 3 — Dual-engine review with `review-plan-multi` (inline)

Chain `review-plan-multi` as a fresh full run — a `claude-delegate` Agent, or an inline-chain (read
`$HOME/.claude/skills/review-plan-multi/SKILL.md` and follow it in this context) — never through the
`Skill` tool (it sets `disable-model-invocation`), over `DRAFT_PATH` as a plan file. It builds
its own request brief from the live context and dispatches its two reviewers — Claude via Agent and
Codex via `cog codex-runner` — itself.

Its output is byte-compatible with the single-plan reviewer contract: `APPROVED`, `MODIFIED`,
`REMOVED`, and `ADDED` annotations. Apply those annotations in this context to finalize the full plan
at `DRAFT_PATH`, then take one convergence `AskUserQuestion` confirmation before proceeding.

Apply annotations to correct and complete the plan, never to shrink it for brevity. `REMOVED` applies
only to genuinely wrong or redundant content; size reduction is the split phase's job alone. If
`review-plan-multi`'s Codex reviewer is unavailable, it proceeds Claude-only with a degradation note
and this build continues.

## Phase 4-5 — Grade and recursive right-sizing (ADR-0050 orchestrator)

Seed a work queue with the finalized plan as the single parent round. Loop until every round is at or
under the single-session ceiling or the splitter reports an irreducible round:

1. Grade the round through a `claude-delegate` Agent or an inline-chain (read
   `$HOME/.claude/skills/review-plan-complexity/SKILL.md` and follow it), not the `Skill` tool: `review-plan-complexity <round> "$WORK_DIR/complexity-reports/<round-slug>.yaml"`.
   Read `grade`, `score`, `splittable`, and `seam_hints` (requirement-ID partitions) from the report.
2. `cog plan-complexity over-ceiling --grade "<grade>" --json` — if not over ceiling, the round is final.
3. If over ceiling, split through a `claude-delegate` Agent or an inline-chain (read
   `$HOME/.claude/skills/plan-split/SKILL.md` and follow it), not the `Skill` tool: `plan-split <round> <seam-hints> "$WORK_DIR/split-verdicts/<round-slug>.yaml"`.
   The splitter re-stamps children (`cog round-req stamp`) and verifies no requirement loss via
   `cog round-split coverage --parent <p> --children <a> <b> --json` (refuses a lossy split).
   Re-enqueue both children; discard the parent.
4. Terminate per ADR-0050: a round is final when at/under ceiling **or** when `plan-split` returns
   `split_performed: false` (irreducible) — the splitter's fact overrides the evaluator's prediction,
   so the loop cannot run forever.

## Phase 6 — Executor association

For each final round, take its rubric score (from the grade report's deterministic extract) and match:

```bash
cog power-grade match --score "<n>" --json   # -> {executor, reserved}
```

If `reserved: true` (`score > 30`, `executor: null`), route the round back to Phase 5 to force a
split. If it is still reserved and irreducible, **fail closed** and surface that round to the operator
— never stamp `executor-prex` as a fallback.

## Phase 7 — Write the vault plan

Create the vault plan and write each final round:

```bash
cog plan new --title "$TITLE" --store "$STORE" --json   # -> plan_dir, plan_slug
```

For each final round, write `<plan_dir>/rounds/<topic>.md` using Template A from `$TEMPLATES`
(self-contained Context / Scope / Current State / Implementation Steps / Acceptance Criteria carrying
the `R<n>` IDs / Next Round; the first step flips status to `doing`, the final step to `done`). Then
stamp and queue each round, and record a per-round prediction:

```bash
cog round-prompt build --executor "<matched>" --round-path "<plan_dir>/rounds/<topic>.md" --json   # -> prompt
cog queue-append --schema rounds --queue "<plan_dir>/queue-rounds.yaml" \
  --item "<topic>" --status todo --depends-on "<csv>" --prompt "<prompt>" --json
cog match-telemetry record --kind prediction \
  --project-key "<project_key>" --plan-slug "<plan_slug>" --round-id "<topic>" \
  --requirement-ids "<R-csv>" --predicted-executor "<matched>" --score "<n>" --grade "<grade>" --json
```

Read `<project_key>` from `cog plan project resolve --store "$STORE" --json`. Register the plan in the
top-level ledger (bootstrap with `cog queue-bootstrap --schema plans` if missing):

```bash
cog queue-append --schema plans --queue "$PLAN_ROOT/queue-plans.yaml" \
  --item "<plan_slug>" --status todo --prompt "/runner-plan -ar @<plan_dir>/" --json
```

Before reporting, validate the stamped queues and the dependency graph — fail closed on any bad stamp:

```bash
cog round-prompt validate-queue --queue "<plan_dir>/queue-rounds.yaml" --schema rounds --json
cog round-prompt validate-queue --queue "$PLAN_ROOT/queue-plans.yaml" --schema plans --json
cog queue-graph-check --schema rounds --queue "<plan_dir>/queue-rounds.yaml" --json
```

## Phase 8 — Final response

Report the vault `plan_dir`; per-round topic + matched executor + grade; the exact run commands
(`/runner-plan -ar @<plan_dir>/` and per-round `/<executor> -ar <round>`); and any reserved/irreducible
rounds that failed closed and need operator attention. Runners stay producer-blind and unchanged. Do
not run git and do not implement anything.

## Guardrails

- This skill only WRITES the vault plan; it does not implement.
- Producer-blind: resolve every output path through `cog plan` verbs; never hardcode `.implementation-plans/`.
- Reserved (`>30`) rounds are never queued — hard split-or-fail (route through `plan-split`).
- Chain `plan-vetted` / `review-plan-multi` / `review-plan-complexity` / `plan-split` through a
  `claude-delegate` Agent or an inline-chain (read each target's `$HOME/.claude/skills/<name>/SKILL.md`
  and follow it); never through the `Skill` tool (all four set `disable-model-invocation`).
- Review runs through `review-plan-multi`; if its Codex reviewer is down, degrade gracefully to its
  Claude-only vetted review with the recorded note.
- Full scope is never summarized or capped — length is resolved only by the split phase.
- Do not run git commands.
