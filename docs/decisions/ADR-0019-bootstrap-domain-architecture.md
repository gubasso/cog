# ADR-0019: Use reconciled bootstrap domains

## Context and Problem Statement

Project bootstrap spans independent domains, language-specific tooling, publishing, identity-bearing fields, and knowledge-base routing. Re-running bootstrap should reconcile reviewed templates rather than assume an empty project.

## Considered Options

- One monolithic scaffold
- Install-only workers
- Domain workers with reconcile-by-default behavior

## Decision Outcome

Chosen option: `Use domain workers with reconcile-by-default behavior` — it keeps each domain independently detectable, reviewable, and refreshable.

## Consequences

- Existing projects can adopt improvements safely.
- Identity and publishing preconditions remain explicit operator concerns.

## Status

Implemented

Enacted by [bootstrap](../explanation/bootstrap.md) and [`cmd_bootstrap_audit.sh`](../../lib/commands/cmd_bootstrap_audit.sh).
