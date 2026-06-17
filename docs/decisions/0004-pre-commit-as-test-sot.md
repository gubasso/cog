# ADR-0004: Pre-commit as test source of truth

## Context and Problem Statement

`cog` has Bash formatting, ShellCheck, unit tests, integration tests, live tests, e2e tests, and a
Codex wrapper invariant. These gates need one source of truth so local runs, hooks, and documented
commands do not drift.

## Considered Options

- Put canonical commands only in `justfile`.
- Maintain separate pre-commit and Just recipes.
- Make pre-commit canonical and have Just delegate to it.

## Decision Outcome

Chosen option: **pre-commit is the test source of truth**. `.pre-commit-config.yaml` defines
formatting, linting, unit, integration, live, e2e, and `lint-codex-wrapper` hooks. `just lint` runs
`pre-commit run --all-files`; `just test` runs the unit hook and the integration hook.

## Consequences

- Good: the same hook definitions back local validation and documented development commands.
- Good: manual tiers (`test-live`, `test-e2e`) are explicit without slowing the default test path.
- Good: skills can point to `just` commands while hook details remain centralized.
- Bad: contributors need pre-commit installed to use the documented quality gates.
- Bad: formatting hooks may rewrite files, so validation may require a second run.

## Status

Implemented.
