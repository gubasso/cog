# Round 1: fn_codex.sh native effort

> Plan: codex-native-effort-runner | Round: 1 of 3 | Complexity: L | Generated: 2026-06-19 |
> Repo: /workspaces/cog | Executor: prex (EF 1.5)

## Context

`lib/functions/fn_codex.sh` is the only layer that builds or runs direct `codex-session exec`. Today
its `cog::fn::codex_exec_command`/`_run` and `cog::fn::codex_resume_command`/`_run` interpolate
`--profile $profile` into every form (native `--sandbox read-only --json`, danger/write, and
`--account … resume`). One quick path already uses `-c model_reasoning_effort=low` directly — that is
the native pattern to generalize.

## Previous Rounds

None (first round).

## Scope of This Round

**IN scope:**

- Replace the `--profile`-based command construction in `fn_codex.sh` with native effort: accept an
  effort tier and emit `-c model_reasoning_effort=<mapped>` (and a native `--model`/`-m` only if the
  policy requires pinning a model). Map tiers per `docs/reference/model-effort-policy.md` +
  `model-effort-codex.toml`. Keep the helper signatures coherent (swap the `profile` parameter for an
  `effort` parameter throughout the four builder/runner helpers).
- Preserve every mode and behavior: native (`--sandbox read-only --json`), fallback
  (`-c sandbox_permissions=["disk-full-read-access"]`), danger/write, quick-auto, resume
  (`--account "$account" … resume "$thread_id"`), `< /dev/null`, `--output-last-message`, direct
  stderr capture, `timeout`, and thread-id/account extraction.
- Keep command construction centralized here; no skill or other lib builds codex commands.

**OUT of scope:**

- The `cog codex-runner` CLI arg change (Round 2) — this round changes the helper internals; Round 2
  changes the command-level `--profile`→`--effort` arg that calls these helpers.
- Skill call sites (Round 3).

## Deterministic vs Probabilistic

- Deterministic (cog): all of it.
- Judgment: the exact tier→`model_reasoning_effort` mapping when the policy leaves a choice (document
  inline, citing `model-effort-policy.md`).

## Validation

- Any `fn_codex` unit bats green; `cog::fn::codex_exec_command` print-command output shows native
  effort flags and no `--profile`. `just lint` + `just test` green.

## Execution Discipline

One round per `/prex` session; flip `done` and stop. Commit with `/gc -a` afterward.
