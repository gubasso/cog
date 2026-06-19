# Round 3: Stage 3 implement (native effort, resume preserved)

> Plan: executor-prex-refactor | Round: 3 of 6 | Complexity: XL | Generated: 2026-06-19 |
> Repo: /workspaces/cog | Executor: prex (EF 1.5)

## Context

Stage 3 resumes the planning session to implement the reviewed plan. Its call sites were already swept
to native effort by `codex-native-effort-runner`; this round confirms the structural Stage-3 section
is correct and self-contained after the rename/restructure.

## Previous Rounds

Round 1: rename + token migration. Round 2: per-stage restructure + Stage 1/2 DRY.

## Scope of This Round

**IN scope:**

- Give Stage 3 its own clear section in `executor-prex/SKILL.md`. Update the implementation path to use
  native Codex effort via `cog codex-runner run-resume --effort …` (no `--profile`). Preserve the
  resume-vs-fresh-exec decision table keyed on the runner-emitted `status`/`resume_signal`, the
  `--account`/`--thread-id` pinning, and the snapshot/`verify-proof` discipline. Keep the Resume
  Fallback (fresh `exec` with fully inlined context) intact.
- Confirm no runtime `codex-conventions.md` read remains (already removed by
  `cog-self-contained-skill-refs`); rely on the internalized cog orientation/write-orientation surface.
- Run `cog skill-lint`.

**OUT of scope:**

- Stage 4 (Round 4), Stage 5 (Round 5).

## Deterministic vs Probabilistic

- Deterministic (cog): `cog codex-runner run-resume`/`run-exec`, the status classification, the
  snapshot/verify-proof.
- Judgment: branching on the resume signal per the decision table; how much context to inline on
  fallback.

## Validation

- Stage 3 uses `--effort` (no `--profile`); the resume fallback table is intact; snapshot/verify-proof
  unchanged. `cog skill-lint` green. `just lint` + `just test` green.

## Execution Discipline

One round per session; flip `done` and stop. Commit with `/gc -a` afterward.
