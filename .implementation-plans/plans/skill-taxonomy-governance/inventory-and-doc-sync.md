# Round 3: Skill inventory and doc sync

> Plan: skill-taxonomy-governance | Round: 3 of 3 | Complexity: M | Generated: 2026-06-19 |
> Repo: /workspaces/cog | Executor: prex (EF 1.5)

## Context

Close out governance by making the shipped documentation reflect the taxonomy and the planned
renames, and by syncing any command surfaces touched in Round 2.

## Previous Rounds

Round 1 recorded the taxonomy ADR + reference + AGENTS/CLAUDE rule. Round 2 added the
`skill-prefix-taxonomy` lint rule + `superseded-by` grandfathering + bats.

## Scope of This Round

**IN scope:**

- Update the shipped skill-inventory reference material (the doc that enumerates skills, if present;
  otherwise add a short `docs/reference/skill-taxonomy.md` lookup listing each shipped skill under its
  taxonomy class). Record migration notes (not actions): `prex` → `executor-prex`
  (owned by `executor-prex-refactor`); `plan-reviewer` → `review-plan-claude` (owned by
  `lean-plan-and-review-skills`); `runner-queue` stays valid as `runner-*`.
- Sync any command-surface mirrors the Round-2 lint rule touched: `docs/reference/cli-commands.md`,
  `man/cog.1.scd`, shell completions, and the root help snapshots — only if Round 2 changed a
  user-visible surface (a new rule id surfaced in `skill-lint --help`/listing counts as a surface).
- Run the full gates.

**OUT of scope:**

- Any actual skill rename/creation (dependent siblings).

## Deterministic vs Probabilistic

- Deterministic (cog): the surface-mirror regeneration (completion/man/help) via the existing
  generators.
- Judgment: where the inventory doc lives and how migration notes are phrased.

## Validation

- `cog skill-lint` passes repo-wide. Completion drift check, man-page summary, and help snapshots are
  in sync. `just lint` + `just test` green. Marks plan `skill-taxonomy-governance` done in the
  top-level `queue-plans.yaml` as the final round.

## Execution Discipline

One round per `/prex` session; flip this round `done`, set the plan `done` in the top-level queue, and
stop. Commit with `/gc -a` afterward.
