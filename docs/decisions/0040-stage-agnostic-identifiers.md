# ADR-0040: Stage-Agnostic Machine Identifiers

## Context and Problem Statement

`executor-prex` collapsed two planning steps into one vetted-plan step, leaving machine-facing names
tied to old stage numbers. Renumbering then risked churn across run-dir artifacts, skill reference
filenames, JSON handoff fields, CLI flags, and executor ordinal values.

## Considered Options

- Keep stage-numbered identifiers and update them after each workflow renumber.
- Rename only the currently broken `executor-prex` artifacts.
- Make machine identifiers stage-agnostic repo-wide and enforce the rule in lint.

## Decision Outcome

Chosen option: **stage-agnostic machine identifiers repo-wide.** Runtime filenames, skill reference
filenames, cross-skill handoff fields, CLI flags, and executor ordinal values are named for role or
content. Human prose may still say `Stage N` or `stage N`; banned machine forms are described by
patterns such as `stage[0-9]+[-_.]`, `--stage[0-9]+`, and `stage[0-9]+` followed by a closing
identifier delimiter.

This decision records the `executor-prex` renumber and the Stop-gate fix that removed an orphaned
plan artifact check. It refines ADR-0038 and supersedes ADR-0028's stage-numbered ordinal
vocabulary while retaining the executor `ordinal` field as the phase-key contract.
Historical point-in-time implementation plans under `.implementation-plans/` are retained as records,
not live runtime contracts.

## Consequences

- Good: workflow renumbers no longer churn machine contracts or run-dir filenames.
- Good: `cog skill-lint` rejects new stage-numbered skill and reference identifiers.
- Bad: internal executor summary flags and ordinal values changed atomically with shipped callers.

## Status

Implemented. Enforced by `stage-agnostic-identifiers` in `lib/commands/cmd_skill_lint.sh` and by the
contract in `docs/reference/skill-contract.md`.
