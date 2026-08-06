# ADR-0005: Use pre-commit as the quality-gate source of truth

<!-- markdownlint-configure-file { "MD043": { "headings": ["# ADR-0005: Use pre-commit as the quality-gate source of truth","## Context and Problem Statement","## Considered Options","## Decision Outcome","## Consequences","## Status"] } } -->

## Context and Problem Statement

Lint and test entry points drift when each task runner invents its own command set. The repository needs one configured inventory of automated gates.

## Considered Options

- Independent task-runner commands
- Pre-commit hooks with task-runner aliases
- CI-only validation

## Decision Outcome

Chosen option: `Use pre-commit hooks with task-runner aliases` — it keeps local and automated validation aligned.

## Consequences

- One hook configuration owns gate behavior.
- Manual-stage live and end-to-end lanes remain explicit.

## Status

Implemented

Enacted by [architecture](../explanation/architecture.md) and [pre-commit configuration](../../.pre-commit-config.yaml).
