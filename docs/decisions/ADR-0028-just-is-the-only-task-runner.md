# ADR-0028: `just` is the only task runner cog knows

## Context and Problem Statement

cog carried two first-class task runners. `taskrunner-detect` returned `make` whenever a `Makefile` existed at the project root, `taskrunner-apply` emitted `.PHONY` blocks with tab indents, `installer-apply --wire-taskrunner make` injected recipes into it, and a parallel `skill-refs/templates/taskrunner/make/` template shipped alongside the `just` one. Every recipe-shaped feature therefore had to be written, tested, and reviewed twice, and the `bootstrap-taskrunner` prose spent a third of its length explaining which runner a project would get.

Nothing in cog or in the projects it bootstraps chose `make` deliberately. A `Makefile` was inherited, and its presence silently diverted the whole domain.

## Considered Options

- Remove `make` entirely; `just` is the only runner cog detects, deploys, or wires.
- Keep `make` detectable as a legacy read-only signal while only ever deploying `just`.
- Keep both runners as equal first-class targets.

## Decision Outcome

Chosen option: `remove make entirely` — a second runner that no one selects on purpose is duplicated surface, not flexibility.

The rule that bounds the removal: cog never chooses, deploys, wires, or recommends `make`. Where cog executes a foreign tree's own hand-written build system, that is not a task-runner choice and is out of scope — so `cog suckless-apply` still runs `make clean && make` to build dwm/st/dmenu, the C pre-commit template keeps its build hook, and the C `.editorconfig` keeps its `[Makefile]` tab rule (make recipe lines must be tab-indented to parse at all).

`test/unit/no_make_task_runner.bats` encodes both the rule and that allowlist, so the boundary is enforced rather than remembered.

## Consequences

- Good: one code path, one template tree, one set of tests, and prose that describes what happens instead of which branch applies.
- Good: a project with an inherited `Makefile` now gets a justfile beside it rather than silently keeping make.
- Bad: `taskrunner-apply --type` and `installer-apply --wire-taskrunner <runner>` changed shape; callers passing a runner argument must drop it.
- Bad: a project that genuinely wants make as its task runner is no longer served by cog and must maintain that file itself.

## Status

Implemented

Enacted in [taskrunner-detect](../../lib/commands/cmd_taskrunner_detect.sh), [taskrunner-apply](../../lib/commands/cmd_taskrunner_apply.sh), [installer-apply](../../lib/commands/cmd_installer_apply.sh), and [bootstrap-taskrunner](../../skills-native/claude/bootstrap-taskrunner/SKILL.md).
