# Round 4: retire plan-reviewer + gates

> Plan: lean-plan-and-review-skills | Round: 4 of 4 | Complexity: L | Generated: 2026-06-19 |
> Repo: /workspaces/cog | Executor: prex (EF 1.5)

## Context

With `review-plan-claude` now authored, execute the `skill-taxonomy-governance` reconciliation: the
legacy `skills/claude/plan-reviewer` (reviews plans → belongs in `review-plan-*`) is superseded by
`review-plan-claude`. Retire it now that its replacement exists (reconciliation via depends_on).

## Previous Rounds

Round 1: shared cog artifact commands. Round 2: `plan-claude`/`plan-codex`. Round 3:
`review-plan-claude`/`review-plan-codex`.

## Scope of This Round

**IN scope:**

- Retire `skills/claude/plan-reviewer`: move any remaining review judgment not already covered into
  `review-plan-claude`, then either remove the directory or mark it `superseded-by: review-plan-claude`
  using the marker the `skill-prefix-taxonomy` lint rule recognizes (per `skill-taxonomy-governance`
  Round 2). Update every reference to `plan-reviewer` (the `prex` Stage 2 delegation is rewired in
  `executor-prex-refactor`; this round handles non-prex references + the inventory).
- Add/confirm `trigger-tests` on the new skills; update the skill-inventory reference.
- Run the full gates.

**OUT of scope:**

- The `prex`/`executor-prex` Stage 2 rewire to `review-plan-claude` (owned by `executor-prex-refactor`).

## Deterministic vs Probabilistic

- Deterministic (cog): `cog skill-lint`, inventory regeneration, surface sync.
- Judgment: what residual judgment to carry from `plan-reviewer`; remove-vs-supersede decision.

## Validation

- `cog skill-lint` passes repo-wide (taxonomy rule clean: no grandfathered `plan-reviewer` failure
  remaining). No dangling references to `plan-reviewer` outside the prex code owned by the
  executor-prex sibling. `just lint` + `just test` green. Marks plan `lean-plan-and-review-skills`
  done in the top-level queue as the final round.

## Execution Discipline

One round per `/prex` session; flip this round `done`, set the plan `done` in the top-level queue, and
stop. Commit with `/gc -a` afterward.
