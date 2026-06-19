# Round 1: shared lean-plan artifact cog commands

> Plan: lean-plan-and-review-skills | Round: 1 of 4 | Complexity: L | Generated: 2026-06-19 |
> Repo: /workspaces/cog | Executor: prex (EF 1.5)

## Context

All four lean skills share the same deterministic mechanics: resolve a run-dir, resolve an output path
(default cog runtime dir, override to a user path), write ONE artifact (a plan, or an annotated plan
review), and expose an orchestrator-invocation output contract so the executors and prex can call them
non-interactively. Build that once so the skills stay lean and DRY (ADR-0008).

## Previous Rounds

None (first round).

## Scope of This Round

**IN scope:**

- `cog plan-doc` command family (`lib/commands/cmd_plan_doc.sh` + `cog::fn::plan_doc::*`): run-dir +
  output-path resolution (default runtime dir, user-path override), `save` (write the single plan doc,
  print its path), `validate`, and the single-plan-doc template skeleton (deterministic header; prose
  fills judgment).
- `cog plan-review` command family (`lib/commands/cmd_plan_review.sh` + `cog::fn::plan_review::*`):
  same run-dir/output-path/save/validate, plus the annotated-review artifact skeleton
  (APPROVED/MODIFIED/REMOVED/ADDED vocabulary, mirroring the existing `plan-reviewer`) and an
  Orchestrator-Invocation-Contract output contract (input plan/prompt path + output path → written
  artifact) so `executor-prex` Stage 2 can call it with two absolute paths.
- Factor the shared run-dir/output-path/research-shelf-consumption logic into a common `cog::fn::*`
  helper used by both families (no duplication). Reuse `cog plan-slug` for naming; do not reimplement.
- Sync `cli-commands.md`, man, completions, help snapshots; add bats for both command families.

**OUT of scope:**

- The four `SKILL.md` bodies (Rounds 2–3).
- The directory/queue plan format (stays in the `plan-writer` family).

## Deterministic vs Probabilistic

- Deterministic (cog): both command families + shared helper + templates + bats.
- Judgment: command naming + template field sets consistent with repo conventions and the existing
  `plan-reviewer` vocabulary.

## Validation

- `cog plan-doc` / `cog plan-review` bats green; save round-trips to default + user paths. Surfaces in
  sync. `just lint` + `just test` green.

## Execution Discipline

One round per `/prex` session; flip `done` and stop. Commit with `/gc -a` afterward.
