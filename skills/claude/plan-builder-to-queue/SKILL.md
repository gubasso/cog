---
name: plan-builder-to-queue
description: >
  Build a fully-vetted, complexity-right-sized, executor-routed multi-round implementation plan into
  the cog plan vault: generate one full-blown plan, cross-engine review it, grade complexity, split
  recursively to the single-session ceiling, match an executor to each round, and write the vault plan
  with executor-stamped queue prompts. Use when the user says "plan-builder-to-queue", "cog plan builder",
  "build a full vetted plan", "capture this as an executor-routed plan".
argument-hint: "[--store auto|local|global] [--title <text>] <orientation/focus/goal>"
disable-model-invocation: true
allowed-tools: Bash Read Write Edit Grep Glob Skill Agent AskUserQuestion
---

<!-- trigger-tests: "plan-builder-to-queue", "cog plan builder", "build a full vetted plan", "executor-routed plan" -->
<!-- cog-skill: plan-emitter -->
<!-- cog-skill: input-fidelity -->

# Plan Builder To Queue

Build one fully-vetted, complexity-right-sized, executor-routed multi-round plan and land it in the **cog plan vault** as executor-stamped queue items. This is an **inline coordinator**: the interview and generation run in the live session; only the opposite-engine Codex review crosses a fresh-context boundary. It writes vault artifacts, so run it in a **write-capable session** — native plan mode is read-only and would block its writes; if plan mode is active, exit it before invoking.

**Context-brief gate.** Before dispatching to any fresh-context worker, build and validate its input brief per `$(cog skill-refs path orchestration/context-brief-gate.md)` — build it with `cog context-brief build --request` and confirm it with `cog context-brief validate`.

## Inputs

`$ARGUMENTS` accepts an optional leading `--store auto|local|global` and `--title <text>`, then the required orientation/focus/goal text that shapes the plan. If the orientation is empty, ask for one.

## Reference resolution

The plan-rounds references ship with `cog` and resolve at point of use; the resolver always succeeds:

```bash
TEMPLATES="$(cog skill-refs path plan-rounds/round-templates.md)"
SPLIT_CONTRACT="$(cog skill-refs path plan-rounds/round-splitting-contract.md)"
RUBRIC="$(cog skill-refs path plan-rounds/complexity-rubric.md)"
```

## Phase 0 — Pre-flight (deterministic)

Resolve the vault and create run state. The setup verb parses flags, makes the run dir, derives the repo root and title, ensures the global vault exists git-by-default, and resolves the store:

```bash
cog plan-builder-to-queue-setup --json "$ARGUMENTS"
```

Capture `RUN_DIR`, `REPO_ROOT`, `ORIENTATION_FILE`, `TITLE`, `STORE`, `PLAN_ROOT`, `PLANS_DIR`, `QUEUE_PATH`, `REQUEST_PATH`, `BRIEF_BODY`, `BRIEF_FILE`, `DRAFT_PATH`, `REVIEW_PATH`, and `WORK_DIR`. Shell state does not persist; substitute literal paths into later calls. Stay producer-blind: locate output only through these resolved paths (and `cog plan new` / `cog plan path`), never a hardcoded `.implementation-plans/`. If a `--store local` resolve fails closed as untrusted, surface the `cog plan trust` instruction it prints and stop.

`TITLE` is auto-derived from the orientation's first line and is overridable: pass a top-level `--title "<multi-word text>"` to `cog plan-builder-to-queue-setup` for a clean title up front, or supply `--title "$TITLE"` at Phase 7's `cog plan new`. A weak auto-derived title never requires re-running setup.

## Phase 1 — Interview, then generate one full-blown plan (inline)

Interview the operator with `AskUserQuestion` to settle open decisions (2–3 concrete questions only when the orientation leaves them open; record skill-chosen defaults for anything deferred). Then chain `plan-oneshot` as a fresh full run — a `claude-delegate` Agent, or an inline-chain (read `$HOME/.claude/skills/plan-oneshot/SKILL.md` and follow it in this context) — never through the `Skill` tool (`plan-oneshot` sets `disable-model-invocation`), with the orientation and the decisions settled above, capturing its lean plan-doc to `DRAFT_PATH`:

- Run `plan-oneshot` in this same context so its own `AskUserQuestion` interview reaches the operator.
- Pass `--output "$DRAFT_PATH"` and the orientation; let it research the repo as needed.

The draft is the maximally-complete **parent round** the rest of the pipeline right-sizes. The draft is one undivided full-scope plan and carries no `### Round N` headings — rounds are created only by the Phase 4-5 loop's coverage-checked splits.

## Phase 2 — Stamp requirement IDs

Stamp plan-scoped `R<n>` IDs onto the draft's acceptance criteria **before any split**, so downstream coverage can anchor:

```bash
cog round-req stamp "$DRAFT_PATH" --json
```

Stamped requirement IDs take the parenthesized `(R<n>)` form on acceptance-criteria bullets; bare `R<n>` round references and `### Round N` headings are a distinct textual form that the stamper and `cog round-split coverage` never read as requirement IDs.

## Phase 3 — Cross-engine adversarial review (opposite engine)

Build the reviewer's brief, then run the **opposite-engine** reviewer (this builder runs on Claude → review on Codex):

```bash
cog context-brief template --out "$BRIEF_BODY"
# Fill BRIEF_BODY: oriented objective, output format (an annotated plan review), scope/boundaries,
# the full substance + the stamped draft as an artifact pointer; omit your own verdict.
cog context-brief build --request "$REQUEST_PATH" --body "$BRIEF_BODY" --out "$BRIEF_FILE"
cog context-brief validate "$BRIEF_FILE"
```

Dispatch the Codex `review-plan-oneshot` over `DRAFT_PATH` + the validated brief through `cog codex-runner`. Write a Codex prompt that opens with `$(cog codex-runner orientation write)`, names `$review-plan-oneshot`, inlines `BRIEF_FILE`, points at `DRAFT_PATH`, and writes the annotated review to `REVIEW_PATH`:

```bash
cog codex-runner run-exec --mode danger --access write --effort high \
  --prompt "$RUN_DIR/review-prompt.txt" --output "$RUN_DIR/review-last.txt" \
  --events "$RUN_DIR/review-events.jsonl" --stderr "$RUN_DIR/review-stderr.log" \
  --state "$RUN_DIR/review.longrun.json"
cog codex-runner finalize --state "$RUN_DIR/review.longrun.json" --max-wall 300   # re-run while exit 75
```

Apply the review annotations (`APPROVED/MODIFIED/REMOVED/ADDED`) in this context to finalize the full plan, then take one convergence `AskUserQuestion` confirmation before proceeding. **Fail closed** if the Codex review cannot run — do not silently fall back to a Claude-only review.

## Phase 4-5 — Recursive right-sizing (ADR-0013, cog-owned loop)

`cog round-rightsize` owns the queue and every control decision — the single-parent seed, the over-ceiling compare, the coverage-gated enqueue of split children, termination, and the baseline conservation assertion. This skill runs only the grader and splitter workers on the exact round cog hands back and feeds their structured verdicts in. Rounds enter the queue only through a coverage-passing binary split cog performs.

Seed the loop with the finalized, stamped draft as the single parent round:

```bash
cog round-rightsize init --state "$WORK_DIR/rightsize.state.json" --baseline "$DRAFT_PATH" --json
```

Advance the state machine until it reports terminal:

1. Read the current batch: `cog round-rightsize pending --state "$WORK_DIR/rightsize.state.json" --json`. When `terminal` is true, go to finalize; otherwise process both buckets this pass.
2. For each round in `awaiting_grade` (fan out in parallel), grade it through a `claude-delegate` Agent or an inline-chain (read `$HOME/.claude/skills/review-plan-complexity/SKILL.md` and follow it), not the `Skill` tool: `review-plan-complexity <round-path> "$WORK_DIR/complexity-reports/<round-id>.yaml"`. Feed each report's `grade`, `score`, and `splittable` back — cog runs the ceiling compare and marks the round final, awaiting-split, or irreducible:

   ```bash
   cog round-rightsize record-grade --state "$WORK_DIR/rightsize.state.json" \
     --round-id "<round-id>" --grade "<grade>" --score "<score>" \
     --splittable "<true|false>" --report "$WORK_DIR/complexity-reports/<round-id>.yaml" --json
   ```

3. For each round in `awaiting_split` (fan out in parallel over disjoint rounds), split it through a `claude-delegate` Agent or an inline-chain (read `$HOME/.claude/skills/plan-split/SKILL.md` and follow it), not the `Skill` tool, passing the round and its `seam_hints` from the report and writing the two children under `$WORK_DIR/rounds-work/`: `plan-split <round-path> <seam-hints> "$WORK_DIR/split-verdicts/<round-id>.yaml"`. Feed the verdict back — cog runs `round-split coverage` and enqueues the two children, or fails closed on a lossy split:

   ```bash
   cog round-rightsize record-split --state "$WORK_DIR/rightsize.state.json" \
     --round-id "<round-id>" --split-performed "<true|false>" \
     --child "<child-a.md>" --child "<child-b.md>" --json
   ```

   When `record-split` fails closed on coverage, surface the lost requirements and stop; do not hand-patch the split.
4. Loop back to step 1.

When `pending` reports `terminal`, close the loop; cog asserts the final union still covers the baseline and returns each round with its retained grade and score:

```bash
cog round-rightsize finalize --state "$WORK_DIR/rightsize.state.json" --json
```

Read `final_rounds[]` (each carries `round_id`, `path`, `grade`, `score`, `status`) — the input to Phase 6 and Phase 7. If finalize fails the conservation assertion, fail closed and surface it.

## Phase 6 — Executor association

For each final round, take its rubric score (from the grade report's deterministic extract) and match:

```bash
cog power-grade match --score "<n>" --json   # -> {executor, reserved}
```

If `reserved: true` (`score > 30`, `executor: null`), reopen that round in the loop and re-run Phase 4-5 over it:

```bash
cog round-rightsize reopen --state "$WORK_DIR/rightsize.state.json" --round-id "<round-id>" \
  --reason executor-reserved --json
```

Then resume Phase 4-5 (`pending` → grade/split → `finalize`) and re-match the resulting rounds. If a reopened round returns irreducible (`split_performed: false`), **fail closed** and surface it to the operator — never stamp `executor-prex` as a fallback.

## Phase 7 — Write the vault plan

Create the vault plan and write each final round:

```bash
cog plan new --title "$TITLE" --store "$STORE" --json   # -> plan_dir, plan_slug
```

For each final round, write `<plan_dir>/rounds/<topic>.md` using Template A from `$TEMPLATES` (self-contained Context / Scope / Current State / Implementation Steps / Acceptance Criteria carrying the `R<n>` IDs / Next Round; the first step flips status to `doing`, the final step to `done`). Then stamp and queue each round, and record a per-round prediction:

```bash
cog round-prompt build --executor "<matched>" --round-path "<plan_dir>/rounds/<topic>.md" --json   # -> prompt
cog queue-append --schema rounds --queue "<plan_dir>/queue-rounds.yaml" \
  --item "<topic>" --status todo --depends-on "<csv>" --prompt "<prompt>" --json
cog match-telemetry record --kind prediction \
  --project-key "<project_key>" --plan-slug "<plan_slug>" --round-id "<topic>" \
  --requirement-ids "<R-csv>" --predicted-executor "<matched>" --score "<n>" --grade "<grade>" --json
```

Read `<project_key>` from `cog plan project resolve --store "$STORE" --json`. Register the plan in the top-level ledger (bootstrap with `cog queue-bootstrap --schema plans` if missing):

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

Report the vault `plan_dir`; per-round topic + matched executor + grade; the exact run commands (`/runner-plan -ar @<plan_dir>/` and per-round `/<executor> -ar <round>`); and any reserved/irreducible rounds that failed closed and need operator attention. Runners stay producer-blind and unchanged. Do not run git and do not implement anything.

## Guardrails

- This skill only WRITES the vault plan; it does not implement.
- Producer-blind: resolve every output path through `cog plan` verbs; never hardcode `.implementation-plans/`.
- Reserved (`>30`) rounds are never queued — hard split-or-fail (route through `plan-split`).
- The right-sizing queue is a cog-owned state machine (`cog round-rightsize`); never seed rounds or edit its state file — rounds enter only through cog's coverage-checked binary splits.
- Chain `plan-oneshot` / `review-plan-complexity` / `plan-split` through a `claude-delegate` Agent or an inline-chain (read each target's `$HOME/.claude/skills/<name>/SKILL.md` and follow it); never through the `Skill` tool (all three set `disable-model-invocation`).
- Use `cog codex-runner run-exec --state` for the opposite-engine review; never bare `codex exec`.
- Do not run git commands.
