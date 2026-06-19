# Round 5: Stage 5 -> refactored review-loop + cog review-loop-input

> Plan: executor-prex-refactor | Round: 5 of 6 | Complexity: XL | Generated: 2026-06-19 |
> Repo: /workspaces/cog | Executor: prex (EF 1.5)

## Context

Stage 5 hands off to `review-loop`. The user flagged the inline `review_loop_input.json` JSON literal
(and the `find … -name 'review-loop-*'` + `comm` child-run discovery) as deterministic output written
in a probabilistic skill body. `review-deep-loop-refactor` moved both into `cog`; this round rewires
Stage 5 to use them.

## Previous Rounds

Rounds 1–4: rename + token migration; restructure + Stage 1/2 DRY; Stage 3 implement; Stage 4 →
review-code-deep.

## Scope of This Round

**IN scope:**

- Replace the inline `review_loop_input.json` body instructions with a `cog review-loop-input` call
  (the schema owner from `review-deep-loop-refactor`) that assembles
  `{task, reviewed_plan, stage4_review, plan_thread_id, impl_thread_id}` from the run-dir files.
- Replace the child review-loop run-dir discovery prose (`find`/`comm`/`diff`/snapshot) with the
  `cog` child-locate command. Keep the lock-release-before-handoff + `verify-proof` on the child's
  `summary.md`.
- Wire Stage 5 to the leaned `review-loop` skill (from `review-deep-loop-refactor`) via the Agent tool,
  preserving the forced/auto/user-decides trigger logic and the NEEDS_DISCUSSION-resolved precondition.
- Run `cog skill-lint` (premise rule should now pass — no deterministic JSON/`find` prose remains).

**OUT of scope:**

- Final docs/tests sweep (Round 6).

## Deterministic vs Probabilistic

- Deterministic (cog): JSON assembly + child discovery via the new commands; lock + verify-proof.
- Judgment: when to run Stage 5; incorporating the child summary into the final output.

## Validation

- No `review_loop_input.json` JSON literal or `find … review-loop-*` prose remains in the skill; Stage
  5 calls `cog review-loop-input` + child-locate. `cog skill-lint` premise rule clean. `just lint` +
  `just test` green.

## Execution Discipline

One round per session; flip `done` and stop. Commit with `/gc -a` afterward.
