# Repository Guidelines

## Scope

`cog` is a Bash CLI plus shipped Claude/Codex skills and Claude agents. The CLI owns deterministic mechanics for agent-oriented workflows; skills and agents retain sequencing and judgment. Default output is machine-facing and file-first; human UX is opt-in.

## Command conventions

- Command modules live at `lib/commands/cmd_<slug_with_underscores>.sh`.
- Handlers are named `cog::cmd::<slug_with_underscores>`.
- Public shared helpers use `cog::fn::*` under `lib/functions/`.
- User-facing command names use dashes; the loader maps them to underscores.
- Every command module keeps its line-2 `: 'desc: ...'` sentinel because help, completion, man, and snapshot gates derive from it.

Current component boundaries are in [architecture](./docs/explanation/architecture.md), and exact commands are in [CLI reference](./docs/reference/cli-commands.md).

## Skill and resource boundary

Skills own sequencing, judgment, and runtime orchestration. Deterministic parsing, validation, filesystem operations, and repeated shell mechanics belong in cog commands or shared helpers. Validate touched runtime skills and skill references with `bin/cog skill-lint`; the exact contract is [skill contract](./docs/reference/skill-contract.md).

The repository is self-contained. Load-bearing shared prose lives under `skill-refs/`; CLI-owned structured reference data lives under `data/`, one file per top-level table. External links are further reading only. Current ownership, the `data/` layout rule, and installation behavior are described in [skills and resources](./docs/explanation/skills-and-resources.md).

## Orchestration guards

- Use environment-first no-backgrounding.
- Chain same-context work inline and delegate only at true isolation boundaries.
- Keep Codex and long orchestration calls in the foreground or in cog-owned durable jobs.
- Track the fixed five-level fresh-context depth budget.
- Verify a durable postcondition at each boundary.
- Use `cog rundir <prefix>` for scratch and keep every scratch artifact below the returned directory.

See [orchestration](./docs/explanation/orchestration.md) and its [exact contract](./docs/reference/orchestration-contract.md).

## Test and lint policy

Pre-commit is the quality-gate source of truth.

- `just lint` runs all pre-commit hooks.
- `just test` runs unit and integration hooks.
- `just test-live`, `just test-e2e`, and `just test-manual` run manual-stage lanes.
- `just man` regenerates the tracked man page when `scdoc` is available.

Run no git command unless the orchestrator explicitly authorizes it. This includes `git add`, `git commit`, `git push`, `git status`, `git diff`, `git reset`, and `git checkout`.
