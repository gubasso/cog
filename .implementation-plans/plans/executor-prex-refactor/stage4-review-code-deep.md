# Round 4: Stage 4 -> refactored review-code-deep

> Plan: executor-prex-refactor | Round: 4 of 6 | Complexity: XL | Generated: 2026-06-19 |
> Repo: /workspaces/cog | Executor: prex (EF 1.5)

## Context

Stage 4 reviews the implementation. The user wants it to delegate to the refactored `review-code-deep`
stage-4 skill (DRY) rather than duplicate review logic in prose, while keeping the load-bearing
`stage4-review.md` artifact and triage vocabulary.

## Previous Rounds

Rounds 1–3: rename + token migration; per-stage restructure + Stage 1/2 DRY; Stage 3 implement.

## Scope of This Round

**IN scope:**

- Wire Stage 4 to the refactored `review-code-deep` (from `review-deep-loop-refactor`) via the Agent
  tool / its Orchestrator Invocation Contract (two abs paths → JSON findings), preserving the
  `stage4-context.md` build, the snapshot-pre/post + `verify-proof --require-json 'has("findings")'`
  proof, and the triage that maps findings → the prex status vocabulary
  (FIXED/NEEDS_DISCUSSION/ACKNOWLEDGED/QUESTION/DISMISSED) written to `stage4-review.md` (name
  load-bearing for the Stop gate — unchanged).
- Move the plan-conformance check into `review-code-deep` (per `review-deep-loop-refactor` Round 1) so
  the orchestrator no longer re-implements it in prose; keep only the triage judgment in the skill.
- Run `cog skill-lint`.

**OUT of scope:**

- Stage 5 (Round 5).

## Deterministic vs Probabilistic

- Deterministic (cog): snapshot/verify-proof, findings validation, `stage4-review.md` contract.
- Judgment: triage of each finding into the status vocabulary; applying minor FIXED edits.

## Validation

- Stage 4 delegates to `review-code-deep` (no duplicated review prose); `stage4-review.md` still
  produced in the format the Stop gate reads; plan-conformance owned by `review-code-deep`. `cog
  skill-lint` green. `just lint` + `just test` green.

## Execution Discipline

One round per session; flip `done` and stop. Commit with `/gc -a` afterward.
