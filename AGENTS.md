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

## Documentation maintenance

Use the in-repo [docs-design routing digest](./skill-refs/docs-design/AGENTS.md) to find the canonical chapter for any general rule.

Cog uses these zones:

- Decisions and rationale: `docs/decisions/`.
- Task runbooks: `docs/guides/`.
- Exact lookup facts: `docs/reference/`.
- Living subsystem design: `docs/explanation/`.
- Reviewed roadmap, appetites, questions, and slice status: `docs/plan/`.

The precedence ladder is local and strict: ADRs beat explanation pages for why a decision was made; subsystem pages beat ADRs for what the design is now; a non-owner links to the owner instead of restating it.

Local exceptions:

- Tracking uses `cadence_days`, `revalidate_how`, and `references`.
- Heading shapes live in `.markdownlint/`, one `MD043` array per shape, each applied by its own `md-*` entry in `.pre-commit-config.yaml`. Never name `MD043` in a `.markdownlint-cli2.jsonc`, which merges over the shape and would switch it off silently. `test/unit/markdownlint_shapes.bats` enforces both halves.
- [ADR-0001](./docs/decisions/ADR-0001-adopt-documentation-architecture.md) records the one-time reset; the never-delete lifecycle resumes from `Proposed` onward.
- `.draft/` is the gitignored workspace and is not linted. `.draft/safe-to-delete/` is only the manual-deletion hand-off buffer.
- Known external-system cases will live under `docs/reference/known-issues/` when the first real case exists.

Until the active slice in docs/plan/milestones.md is implemented, do not add a subsystem page and do not open an ADR outside that slice. A question that arises goes to docs/plan/open-questions.md.

Verify documentation changes with `bin/cog docs-lint`, `bin/cog skill-lint`, `bin/cog digest-check skill-refs/docs-design`, `just lint`, `just test`, and `just test-e2e`.
