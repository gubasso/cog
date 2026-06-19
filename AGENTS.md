# Repository Guidelines

## Scope

`cog` is a Bash CLI plus shipped Claude/Codex skills and Claude agents. The CLI owns deterministic
mechanics for agent-oriented workflows; skills and agents call into `cog` instead of reimplementing
those mechanics in prose. `cog` is machine-facing: its default contract is machine-output plus
file-first logs; human-UX is optional and opt-in.

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

## Skill and Script Responsibility Boundary

Skills keep sequencing, judgment, and runtime orchestration in prose. Deterministic routines,
repeated shell mechanics, parsing, validation, and filesystem/git/workflow operations belong in
`cog` subcommands or shared `cog::fn::*` helpers. When a skill or command script is created or
edited, validate the change against `docs/reference/skill-contract.md` and run `cog skill-lint` on
touched `SKILL.md` files before finishing.

See `docs/decisions/0008-skill-script-boundary.md`.

Skill `model:`/`effort:` choices follow `docs/reference/model-effort-policy.md`. `model: sonnet` is
forbidden; use `model: opus` + `effort: low`.

Skill names must follow the prefix taxonomy in `docs/decisions/0016-skill-prefix-taxonomy.md` and
`docs/reference/skill-contract.md` ("Prefix taxonomy"). `plan-*` emits plans; `review-*` reviews code
or plans, with `review-plan-*` as the sub-namespace for plan-before-implementation review; `executor-*`
executes one prompt/plan; `runner-*` orchestrates executor-selected queue items. A skill's prefix must
match its behavior.

Skills that output a plan must not run in Claude plan mode (it is read-only and blocks the plan
writes). They carry a Phase 0 plan-mode gate marked with `<!-- cog-skill: plan-emitter -->` and
`<!-- cog-plan-mode-gate -->`, enforced by `cog skill-lint`'s `plan-mode-gate` rule. See
`docs/reference/skill-contract.md` ("Plan-mode gate") and `docs/decisions/0015-plan-skills-not-in-plan-mode.md`.

## Orchestration Guards

- Use env-first no-backgrounding; never rely on `PreToolUse` for runtime backgrounding.
- Never background a Codex or long orchestration call.
- Chain skills inline when same-context is enough.
- Use foreground Agent delegation only at true isolation boundaries.
- Track the fixed 5-level subagent depth budget.
- Verify a durable postcondition at every orchestration boundary.
- Keep deterministic mechanics in `cog`.

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
