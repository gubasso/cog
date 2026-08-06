# ADR-0001: Adopt the documentation architecture

<!-- markdownlint-configure-file { "MD043": { "headings": ["# ADR-0001: Adopt the documentation architecture","## Context and Problem Statement","## Considered Options","## Decision Outcome","## Consequences","## Status"] } } -->

## Context and Problem Statement

Documentation had overlapping owners, oversized records, and forward-looking state outside the shipped corpus. Maintainers need one durable placement and lifecycle contract.

## Considered Options

- Keep the existing corpus unchanged
- Adopt the in-repo docs-design shelf and reset the corpus once

## Decision Outcome

Chosen option: `Adopt the in-repo shelf and perform a one-time greenfield reset` — it establishes one owner per fact and makes the reset reviewable.

## Consequences

- The five documentation zones and deterministic lint are now explicit.
- The reset renumbers historical records and requires a permanent migration ledger.

## Status

Implemented

Enacted by [docs-design shelf](../../skill-refs/docs-design/README.md), [documentation mechanics](../explanation/documentation.md), and [migration ledger](../reference/documentation-migration.md).
