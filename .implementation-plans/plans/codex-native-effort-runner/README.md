# Codex native-effort runner: drop --profile recipes for native --effort

> Complexity: L | Rounds: 3 | Generated: 2026-06-19 | Repo: /workspaces/cog | Executor: prex (EF 1.5)

## Problem Statement

Every Codex call in the repo currently flows through a `codex-session` wrapper `--profile <tier>`
config recipe: `lib/functions/fn_codex.sh` builds `codex-session exec --profile $profile …`,
`cog codex-runner run-exec`/`run-resume` require a `--profile <p>` arg, and skills pass
`--profile medium`/`low`/`deep`. The user's directive (Q3): Codex calls must be **self-contained** —
drop the external profile-recipe dependency and pass native effort directly (e.g.
`-c model_reasoning_effort=<...>` / a native `--effort`), mapped per `docs/reference/model-effort-policy.md`.

The user also directed that codex-session knowledge be fully internalized into `cog` so NO skill reads
`codex-conventions.md` at runtime. That internalization is **already owned** by the queued
`cog-self-contained-skill-refs` plan (which absorbs the orientation/quota blocks into
`cog codex-runner`, rewires ~12 skills off the doc, and keeps the doc only as a maintenance
reference). This plan therefore owns ONLY the remaining, uncovered piece: the `--profile` → native
`--effort` migration, layered on top of `cog-self-contained-skill-refs`.

## Strategy

Bottom-up, foundations first: migrate the builder, then the runner CLI, then sweep the call sites.

1. `fn-codex-native-effort` — replace `--profile` internals in `fn_codex.sh` (the only direct-exec
   layer) with native model/effort, preserving every mode.
2. `codex-runner-cli-migration` — change `cog codex-runner` from required `--profile` to native
   `--effort` (+ `--model` if needed); map tiers per `model-effort-policy.md`; sync surfaces + bats.
3. `skill-callsite-sweep` — mechanically migrate every `--profile` call site to `--effort` across all
   codex-calling skills (purely the effort swap; codex-conventions-read removal stays owned by
   `cog-self-contained-skill-refs`).

## Rounds

1. `fn-codex-native-effort.md` — `lib/functions/fn_codex.sh` native effort, modes preserved.
2. `codex-runner-cli-migration.md` — `cog codex-runner` `--profile`→`--effort`; surfaces + bats.
3. `skill-callsite-sweep.md` — mechanical `--profile`→`--effort` across all codex-calling skills.

## Execution Commands

```bash
/prex -ar @.implementation-plans/plans/codex-native-effort-runner/
# or
/prex -ar .implementation-plans/plans/codex-native-effort-runner/fn-codex-native-effort.md
```

## Execution Discipline

One `/prex` session per round; `/prex` runs the first `todo` round, flips it `done`, and stops. Commit
each round with `/gc -a` afterward.

## Decisions & Constraints

- `Executor: prex (EF 1.5)`.
- Native effort tiers map per `docs/reference/model-effort-policy.md` + the descriptive
  `model-effort-codex.toml` (from `model-effort-policy-and-rename`). `model: sonnet` stays forbidden;
  effort maps to the policy's codex tiers.
- `fn_codex.sh` remains the ONLY layer that builds/runs direct `codex-session exec`. All five modes
  (native, fallback, danger/write, quick-auto, resume) and `--account` pinning, `< /dev/null`,
  `--output-last-message`, stderr capture, thread-id extraction, and status classification are
  preserved.
- Deterministic mechanics stay in `cog`; skills only choose an effort tier and call `cog codex-runner`.
- New cog command surfaces sync `cli-commands.md`, man, completions, help snapshots, and bats.
- Do not run git commands inside round bodies.

## Reconciliation (depends_on, no duplication)

- `depends_on: cog-self-contained-skill-refs` — that plan internalizes `codex-conventions.md` and
  removes the runtime doc reads from skills; THIS plan only swaps `--profile`→`--effort` and relies on
  that internalized orientation surface. Round 3 does NOT re-remove codex-conventions reads.
- `depends_on: model-effort-policy-and-rename` (done) — supplies the effort tier policy + codex TOML.
- The `prex` and `review-loop` call sites are swept here (mechanically); their STRUCTURAL refactors
  live in `executor-prex-refactor` / `review-deep-loop-refactor`, which `depends_on` this plan so they
  build on already-native-effort skills.
