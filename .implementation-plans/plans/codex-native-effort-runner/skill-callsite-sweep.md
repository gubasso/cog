# Round 3: skill call-site sweep (--profile -> --effort)

> Plan: codex-native-effort-runner | Round: 3 of 3 | Complexity: L | Generated: 2026-06-19 |
> Repo: /workspaces/cog | Executor: prex (EF 1.5)

## Context

With `fn_codex.sh` (Round 1) and `cog codex-runner` (Round 2) on native effort, the `--profile`
argument no longer exists. Every skill that passes `--profile` must be swept to `--effort` so nothing
references the removed arg. This is a purely mechanical effort swap.

## Previous Rounds

Round 1: `fn_codex.sh` native effort. Round 2: `cog codex-runner` `--profile`→`--effort`.

## Scope of This Round

**IN scope:**

- Replace every `--profile <tier>` call site with the mapped `--effort <tier>` across all
  codex-calling skills currently using it: `skills/claude/ask`, `skills/codex/ask`,
  `skills/claude/plan-writer-multi`, `skills/codex/plan-writer`, `skills/claude/prex`
  (+ `references/stage-2-through-5-details.md` if still present at run time),
  `skills/claude/review-loop`. Map `medium`/`low`/`deep` per `model-effort-policy.md`.
- Run `cog skill-lint` on every touched `SKILL.md`.

**OUT of scope:**

- Removing runtime `codex-conventions.md` reads — that is owned by `cog-self-contained-skill-refs`
  (this plan `depends_on` it). Do NOT re-do that removal here.
- Any STRUCTURAL rewrite of `prex`/`review-loop` — those are owned by `executor-prex-refactor` /
  `review-deep-loop-refactor`, which `depends_on` this plan and build on the already-swept call sites.
  This round changes ONLY the effort argument, not stage structure or delegation.

## Deterministic vs Probabilistic

- Deterministic (cog): `cog skill-lint` validation. The swap itself is a mechanical text edit applied
  to skill prose.
- Judgment: confirming each call site's correct tier mapping.

## Validation

- `grep -rn -- '--profile' skills/` returns nothing (no call site left). `cog skill-lint` passes on
  every touched skill. `just lint` + `just test` green. Marks plan `codex-native-effort-runner` done
  in the top-level queue as the final round.

## Execution Discipline

One round per `/prex` session; flip this round `done`, set the plan `done` in the top-level queue, and
stop. Commit with `/gc -a` afterward.
