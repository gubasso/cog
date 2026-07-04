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

Build one fully-vetted, complexity-right-sized, executor-routed multi-round plan and land it in the
**cog plan vault** as executor-stamped queue items. This is an **inline coordinator**: the interview
and generation run in the live session; only the opposite-engine Codex review crosses a fresh-context
boundary. It writes vault artifacts, so run it in a **write-capable session** — native plan mode is
read-only and would block its writes; if plan mode is active, exit it before invoking.

<!-- cog-context-brief-gate -->

**Context-brief gate.** Before `/plan-builder-to-queue` dispatches to any fresh-context worker — an Agent subagent
or a `cog codex-runner` Codex job — build its input as a validated context brief from your whole
accumulated raw context: attach the raw request as-is, author an oriented objective, carry the full
substance and load-bearing artifacts, and omit your own verdict. Build the brief with `cog
context-brief build` and confirm it with `cog context-brief validate` before dispatch.

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
Shell state does not persist; substitute literal paths into later calls. Stay producer-blind: locate
output only through these resolved paths (and `cog plan new` / `cog plan path`), never a hardcoded
`.implementation-plans/`. If a `--store local` resolve fails closed as untrusted, surface the
`cog plan trust` instruction it prints and stop.

## Phase 1 — Interview, then generate one full-blown plan (inline)

Interview the operator with `AskUserQuestion` to settle open decisions (2–3 concrete questions only
when the orientation leaves them open; record skill-chosen defaults for anything deferred). Then chain
`plan-oneshot` as a fresh full run — a `claude-delegate` Agent, or an inline-chain (read
`$HOME/.claude/skills/plan-oneshot/SKILL.md` and follow it in this context) — never through the `Skill`
tool (`plan-oneshot` sets `disable-model-invocation`), with the orientation and the decisions settled
above, capturing its lean plan-doc to `DRAFT_PATH`:

- Run `plan-oneshot` in this same context so its own `AskUserQuestion` interview reaches the operator.
- Pass `--output "$DRAFT_PATH"` and the orientation; let it research the repo as needed.

The draft is the maximally-complete **parent round** the rest of the pipeline right-sizes.

## Phase 2 — Stamp requirement IDs

Stamp plan-scoped `R<n>` IDs onto the draft's acceptance criteria **before any split**, so downstream
coverage can anchor:

```bash
cog round-req stamp "$DRAFT_PATH" --json
```

## Phase 3 — Cross-engine adversarial review (opposite engine)

Build the reviewer's brief, then run the **opposite-engine** reviewer (this builder runs on Claude →
review on Codex):

```bash
cog context-brief template --out "$BRIEF_BODY"
# Fill BRIEF_BODY: oriented objective, output format (an annotated plan review), scope/boundaries,
# the full substance + the stamped draft as an artifact pointer; omit your own verdict.
cog context-brief build --request "$REQUEST_PATH" --body "$BRIEF_BODY" --out "$BRIEF_FILE"
cog context-brief validate "$BRIEF_FILE"
```

Dispatch the Codex `review-plan-oneshot` over `DRAFT_PATH` + the validated brief through
`cog codex-runner`. Write a Codex prompt that opens with `$(cog codex-runner orientation write)`,
names `$review-plan-oneshot`, inlines `BRIEF_FILE`, points at `DRAFT_PATH`, and writes the annotated
review to `REVIEW_PATH`:

```bash
cog codex-runner run-exec --mode danger --access write --effort high \
  --prompt "$RUN_DIR/review-prompt.txt" --output "$RUN_DIR/review-last.txt" \
  --events "$RUN_DIR/review-events.jsonl" --stderr "$RUN_DIR/review-stderr.log" \
  --state "$RUN_DIR/review.longrun.json"
cog codex-runner finalize --state "$RUN_DIR/review.longrun.json" --max-wall 300   # re-run while exit 75
```

Apply the review annotations (`APPROVED/MODIFIED/REMOVED/ADDED`) in this context to finalize the full
plan, then take one convergence `AskUserQuestion` confirmation before proceeding. **Fail closed** if
the Codex review cannot run — do not silently fall back to a Claude-only review.

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
- Chain `plan-oneshot` / `review-plan-complexity` / `plan-split` through a `claude-delegate` Agent or an
  inline-chain (read each target's `$HOME/.claude/skills/<name>/SKILL.md` and follow it); never through
  the `Skill` tool (all three set `disable-model-invocation`).
- Use `cog codex-runner run-exec --state` for the opposite-engine review; never bare `codex exec`.
- Do not run git commands.
