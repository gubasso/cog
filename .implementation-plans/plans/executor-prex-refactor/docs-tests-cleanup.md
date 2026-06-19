# Round 6: docs, tests, cleanup

> Plan: executor-prex-refactor | Round: 6 of 6 | Complexity: XL | Generated: 2026-06-19 |
> Repo: /workspaces/cog | Executor: prex (EF 1.5)

## Context

Final sweep: sync every command/skill surface, run the full gates, and verify no migration residue
(no `--profile`, no runtime `codex-conventions.md` reads, no stale `prex` references, no lumped stage
reference) remains.

## Previous Rounds

Rounds 1–5 renamed `prex` → `executor-prex`, restructured the stages, and DRY-wired Stages 1/2/4/5 to
the new skills + cog commands.

## Scope of This Round

**IN scope:**

- Sync `docs/reference/cli-commands.md`, `man/cog.1.scd`, shell completions, root help snapshots, the
  skill-inventory reference, and queue examples for the rename + new prompt forms.
- Residue checks: `grep -rn -- '--profile' skills/` empty; no runtime `codex-conventions.md` read in
  `executor-prex`; `references/stage-2-through-5-details.md` gone; no stale `/prex`/`prex` references
  except the intended compatibility alias documented in Round 1.
- Run `cog skill-lint` on `executor-prex` and any touched skill; run the full gates.

**OUT of scope:**

- Behavioral changes to any stage (Rounds 1–5).

## Deterministic vs Probabilistic

- Deterministic (cog): surface regeneration, grep residue checks, skill-lint, the gates.
- Judgment: confirming the compatibility alias is the only intentional `prex` reference left.

## Validation

- All surfaces in sync (completion drift, man summary, help snapshots). `cog skill-lint` repo-wide
  green. `just lint` + `just test` green. Marks plan `executor-prex-refactor` done in the top-level
  queue as the final round of the whole effort.

## Execution Discipline

One round per session; flip this round `done`, set the plan `done` in the top-level queue, and stop.
Commit with `/gc -a` afterward.
