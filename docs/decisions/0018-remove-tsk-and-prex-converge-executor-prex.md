# ADR-0018: Remove tsk Integration and the prex Alias; Converge on executor-prex

## Context and Problem Statement

The repo carried two legacy surfaces: a `tsk` (riptask) integration (the `tsk-impl`/`tsk-new` skills, the `tsk-*` cog commands, and the executor-prex `-t`/`--tsk-impl` task source) and a `prex` compatibility layer (the `/prex` skill alias, `prex-*` cog command aliases, and the `prex` spelling baked into internal infra: the lock prefix, the Stop hook, and the executor-sizing token). Maintaining both alongside the canonical `executor-prex` added drift and confusion with no remaining consumer.

## Considered Options

- Keep both surfaces as compatibility shims.
- Remove `tsk` only; keep the `prex` alias.
- Remove `tsk` integration entirely and fully rename every `prex` token to `executor-prex`.

## Decision Outcome

Chosen option: **Remove `tsk` and fully converge on `executor-prex`** — one canonical name, no compatibility layer. The `tsk-*` skills and commands and the `-t`/`--tsk-impl` flag are deleted; the `/prex` alias, `prex-*` cog commands, the `prex-active` lock prefix, the `hook-guard prex-stop` subcommand, and the `prex` executor-sizing token all become `executor-prex`. Queue prompts use `/executor-prex -ar`.

## Consequences

- Good: a single executor name end to end; no dead `tsk`/`prex` surface; simpler parser contract (`{mode, task_file}`).
- Bad: a behavior-affecting rename — external Stop-hook wiring (dotfiles) must call `executor-prex-stop`, and any pre-existing queue prompt spelled `/prex` must be rewritten.

## Status

Implemented. Enacted by `lib/functions/fn_rundir.sh` (lock name), `lib/functions/fn_executor.sh` (alias removal + stage_model), `lib/commands/cmd_hook_guard.sh`, `cmd_plan_writer_multi_setup.sh`, `cmd_executor_prex_parse_args.sh`, and the deletion of the `tsk-*`/`prex-*` modules and skills.

Supersedes the `prex` transition notes in ADR-0010 (orchestration-env-first) and ADR-0016 (skill-prefix-taxonomy); those accepted ADRs remain as historical record.
