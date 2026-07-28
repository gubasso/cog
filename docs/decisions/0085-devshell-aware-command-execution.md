# ADR-0085: devShell-aware command execution for hook-triggering cog commands

## Context and Problem Statement

Every bootstrapped project carries a per-project Nix devShell (`flake.nix` + `.envrc` via direnv/nix-direnv) whose pre-commit hook tools — `nixfmt`, `statix`, `deadnix` (ADR-0084) — run as `language: system` and resolve off `PATH`. That `PATH` is populated interactively by direnv's prompt hook, which fires only in prompt-drawing shells. A non-prompt shell — a CI step, `bash -c`, or a coding-agent / parallel commit worker — never fires the hook, so the devShell is absent and every `language: system` hook reports "Executable not found".

This surfaced concretely: running `gc` fanned out parallel commit workers, each invoking `cog gc-commit` in a fresh non-prompt shell. `git commit` triggered the pre-commit hooks with the devShell off `PATH`, and every worker failed closed — a clean environment blocker, not a content problem.

`cog` already solves this for **cargo** (`cog::fn::cargo::exec` wraps invocations with `direnv exec` / `nix develop --command`, per `skill-refs/nix/non-interactive-direnv.md`). But the commands that actually trigger pre-commit / pre-push hooks — and `make` — still ran on bare `PATH`: `cog gc-commit` (`git commit`), `cog gc-push` (`git push`, incl. the `nix flake check` pre-push hook), `cog precommit-run` (`pre-commit install`/`run`), and `cog suckless-apply` (`make`).

## Considered Options

- Reuse `cog::fn::cargo::runner` for these call sites.
- A dedicated **devShell-first** env-runner (`cog::fn::env::*`) that every hook-triggering command routes through.
- Push the fix into skill prose (tell workers to run inside `nix develop`).
- Eagerly load direnv once at `cog` startup (`eval "$(direnv export bash)"`).

## Decision Outcome

Chosen: **a dedicated devShell-first env-runner in `lib/functions/fn_env.sh`**, routed through by every hook-triggering `cog` command.

- `cog::fn::env::runner <root>` resolves how to enter a project's devShell, preferring an **allowed** direnv `.envrc` (fast, cached with nix-direnv), then `flake.nix` via `nix develop --command`, else `bare`. `cog::fn::env::exec <root> <runner> -- <cmd…>` is a pure environment wrapper (no `cd`): direnv and nix take the root as an explicit argument, so the devShell resolves from the root regardless of cwd. A `git -C <root>` command needs no directory change; a command that must run _in_ the root (`pre-commit`, `make`) keeps its own `cd`.
- The runner is **devShell-first**, not bare-first like `cog::fn::cargo::runner`. cargo is the _driver_ tool, so "cargo already on `PATH`" is the right signal. Here the driver (`git`, `pre-commit`, `make`) is always on `PATH` but the hook _payload_ tools are not — a bare-first check would still fail. Reusing the cargo runner was therefore rejected.
- `cog::fn::env::_direnv_allowed` gates the direnv path and **fails safe to "not allowed"**: any uncertainty (un-allowed `.envrc`, unknown `direnv status` shape, absent direnv) falls through to `nix develop` (always correct) rather than a silent `direnv exec` that would run the command _without_ the environment.
- `COG_ENV_RUNNER` (`bare|direnv|nix-develop|auto`, default `auto`) is a hard override for CI and tests.
- The fix lives entirely in `cog` mechanics, so the skills that call these commands — `gc`/`gc-repo`, `precommit-fix`, `suckless-patcher` — are fixed transparently with no prose change, consistent with the skill/script boundary (ADR-0008). Skill-prose and startup-eager-load options were rejected for that reason: prose duplicates a deterministic mechanic, and an eager global load cannot serve `gc`'s multi-repo case where each worker targets a different root.

## Consequences

- Good: one shared, devShell-first execution primitive; `gc`, `precommit-fix`, and `suckless-patcher` work in non-prompt shells without bypassing hooks. Non-nix repos are unaffected (`runner` resolves `bare`, identical to the prior invocation).
- Good: the direnv-allow gate keeps headless/agent contexts correct instead of silently running hooks off the devShell.
- Bad: a second env-runner convention alongside `cog::fn::cargo::*` (different, intentional policy); the `nix develop --command` fallback re-evaluates the flake per invocation when direnv is unavailable or un-allowed.
- Out of scope (follow-up): `cog codex-runner` / `executor-*` in-session tool calls run inside a Codex/Claude session whose cwd carries its own environment; wrapping a session's arbitrary internal commands is not a per-invocation `cog` mechanic.

## Status

Implemented — `lib/functions/fn_env.sh`, `bin/cog`, `lib/commands/cmd_gc_commit.sh`, `cmd_gc_push.sh`, `cmd_precommit_run.sh`, `cmd_suckless_apply.sh`, and `test/unit/fn_env.bats`. Builds on ADR-0065 (bootstrap language workers / cargo runner precedent), ADR-0084 (Nix pre-commit layer), and ADR-0008 (skill/script boundary); cites `skill-refs/nix/non-interactive-direnv.md`.
