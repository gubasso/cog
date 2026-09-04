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

**Before you add or edit a skill, read three things in this order:** the universal manufacturing standard at [`skill-refs/skill-authoring/universal/standard.md`](./skill-refs/skill-authoring/universal/standard.md), the cog house policy in [skill contract](./docs/reference/skill-contract.md), and the completion checklist at [`skill-refs/skill-authoring/universal/checklist.md`](./skill-refs/skill-authoring/universal/checklist.md). This repository owns those rules through documentation and gates. There is no in-repo skill that authors cog skills for you. The shipped `skill-creator` package is the product cog gives its users, and it is deliberately cog-agnostic, so it does not carry cog house policy.

A skill has one authored owner. Portable is the default: a package at `skills/<name>/` installs the same bytes into every agent root. Choose `skills-native/<runtime>/<name>/` only when a named runtime capability changes the body or the frontmatter, and say which capability in the skill's own prose. One name never lives in both classes.

The repository is self-contained. Load-bearing shared prose lives under `skill-refs/`; CLI-owned structured reference data lives under `data/`, one file per top-level table. External links are further reading only. Current ownership, the `data/` layout rule, and installation behavior are described in [skills and resources](./docs/explanation/skills-and-resources.md).

## Reachability

Cog is operated by agents, driven by skills. Skills are the entry points; every other surface exists to serve them. The one deliberate exception is the operator's out-of-band approval channel: `cog gate approve` is run by the human precisely so an executor cannot relay its own approval, per [approval gate contract](./skill-refs/orchestration/approval-gate-contract.md).

**The principle.** Every command, command-specific flag, function, template, ref, and data table has a live caller — a skill, a pre-commit hook, another cog command, or a shipped script such as the installer, a `justfile` lane, or the shell completion. A thing's own tests are not a caller: they prove it works, never that anything needs it. The global flags every command inherits — `-h`/`--help`, `-V`/`--version`, `--json`, `--dry-run`, `--print-config`, `-v`/`-vv`/`-vvv` — are the CLI's operator surface and are exempt, reachable through whichever command is.

Every skill that calls first-party `cog` directly lives in this repository under `skills-native/claude/` or `skills-native/codex/`. A portable package under `skills/` calls no `cog` command at all, which is what lets it run in a project that never installed cog. An externally owned skill instead calls a command supplied by a cog plugin colocated with that skill's project, so caller and callee are audited together. That project owns and installs its skills through its own channel; cog's plugin protocol contributes only the plugin's command surface, not skills, skill-refs, or data tables. A plugin may call back into cog through `COG_EXECUTABLE`, but that callback never establishes reachability, and it may only reach a first-party command that already has an in-repo caller — a command kept alive for a plugin alone belongs in that plugin's own project. An in-repo sweep that finds no caller is therefore authoritative: both a hidden external direct caller and a first-party command surviving on plugin callbacks alone are policy violations.

A data table is reached when production code reads it or when it is maintained decision provenance: a decision record depends on it and `data/maintenance-tracking.yaml` gives it an active revalidation entry.

**The change-time obligation.** Every cleanup enforces the principle at its own boundary. Removing a skill, a hook, or a call site includes sweeping whatever it was the last caller of, in the same change: the command, its command-specific flags, its shared functions, its tests, its refs, and its rows in the command inventories (`completions/cog.bash`, `man/cog.1.scd`, `docs/reference/cli-commands.md`, `test/integration/help_snapshots.bats`). Not deprecated, not kept because it still works. Git history is the recovery path.

Those four inventories enumerate the command surface; where one of them does invoke a command, it invokes it because the command is enumerated, not because a workflow needs it. A row is never evidence of reachability.

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
