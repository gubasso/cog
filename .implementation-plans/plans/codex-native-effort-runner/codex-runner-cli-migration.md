# Round 2: cog codex-runner --profile -> --effort

> Plan: codex-native-effort-runner | Round: 2 of 3 | Complexity: L | Generated: 2026-06-19 |
> Repo: /workspaces/cog | Executor: prex (EF 1.5)

## Context

`lib/commands/cmd_codex_runner.sh` exposes `run-exec`/`run-resume` with a REQUIRED `--profile <p>`
arg that it forwards to the `fn_codex.sh` helpers (now native, per Round 1). Change the command-level
contract to native effort.

## Previous Rounds

Round 1 made `fn_codex.sh` build native effort flags internally.

## Scope of This Round

**IN scope:**

- Change `cog codex-runner run-exec` and `run-resume` from required `--profile <p>` to native
  `--effort <tier>` (and an optional `--model` only if the policy needs explicit model pinning). Keep
  `--mode`, `--account`, `--thread-id`, `--prompt`, `--output`, `--events`, `--stderr`, `--thread`,
  `--print-command` intact. Update the usage strings + self-check.
- Map `--effort` tiers per `model-effort-policy.md`. Decide whether to keep a transitional `--profile`
  alias: prefer a hard cut (no alias) since Round 3 sweeps all call sites in the same plan — document
  the choice. The `gate`, `snapshot-pre/post`, `verify-proof`, `extract-thread` subcommands are
  unchanged.
- Sync surfaces: `docs/reference/cli-commands.md`, `man/cog.1.scd`, completions, root help snapshots;
  update `test/integration/cmd_codex_runner.bats`.

**OUT of scope:**

- Skill call sites (Round 3).

## Deterministic vs Probabilistic

- Deterministic (cog): the CLI arg change + surface sync + bats.
- Judgment: alias-vs-hard-cut decision (recommend hard cut; same-plan sweep removes all callers).

## Validation

- `cmd_codex_runner.bats` green; `cog codex-runner run-exec --print-command --effort medium …` emits
  native effort flags. Completion drift, man summary, help snapshots in sync. `just lint` + `just
  test` green.

## Execution Discipline

One round per `/prex` session; flip `done` and stop. Commit with `/gc -a` afterward.
