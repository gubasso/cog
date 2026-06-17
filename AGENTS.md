# Repository Guidelines

## Scope

`cog` is a Bash CLI plus shipped Claude/Codex skills and Claude agents. The CLI owns deterministic
mechanics for agent-oriented workflows; skills and agents call into `cog` instead of reimplementing
those mechanics in prose.

## Command Conventions

- Command modules live at `lib/commands/cmd_<slug_with_underscores>.sh`.
- Command handlers are named `cog::cmd::<slug_with_underscores>`.
- Public shared helpers live under `cog::fn::*` in `lib/functions/`.
- User-facing command names use dashes; the loader maps dashes to underscores.
- Every command module must keep its line-2 `: 'desc: ...'` sentinel. Root help, command reference
  material, man-page command summaries, and completion drift checks depend on it.

## Loader and Namespacing

`bin/cog` resolves its real app root, eagerly sources core functions, parses globals, loads config,
then dispatches through `lib/loader.sh`. The loader derives `cmd_<slug>.sh` and
`cog::cmd::<slug>` from the requested command. Keep command-specific logic in command modules and
shared behavior in namespaced functions.

## Test and Lint Policy

Pre-commit is the source of truth for quality gates.

- `just lint` runs `pre-commit run --all-files`.
- `just test` runs the unit hook and the integration hook.
- `test-live` and `test-e2e` are manual-stage hooks and are exposed by `just test-live`,
  `just test-e2e`, and `just test-manual`.

Run no git commands unless the orchestrator explicitly authorizes them. That includes `git add`,
`git commit`, `git push`, `git status`, `git diff`, `git reset`, and `git checkout`.

## Documentation Maintenance

Documentation follows Diataxis:

- Decisions live in `docs/decisions/`.
- Task runbooks live in `docs/guides/`.
- Lookup facts live in `docs/reference/`.
- Mental models live in `docs/explanation/`.
- `docs/README.md` is an index only.

Accepted ADRs are never deleted. Record changed decisions with a new superseding ADR. Markdown
fenced code blocks must declare a language; use `text` when no specific language applies.
