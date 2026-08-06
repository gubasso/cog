# ADR-0004: Use manifest-owned installation

<!-- markdownlint-configure-file { "MD043": { "headings": ["# ADR-0004: Use manifest-owned installation","## Context and Problem Statement","## Considered Options","## Decision Outcome","## Consequences","## Status"] } } -->

## Context and Problem Statement

The installer writes to several user locations and must remove only paths it owns. Upgrades also need predictable refresh and pruning behavior.

## Considered Options

- Recursive removal of install roots
- Manifest-owned copied files
- Package-manager-only distribution

## Decision Outcome

Chosen option: `Use manifest-owned copied files` — it makes uninstall precise across all targets.

## Consequences

- Install and uninstall can round-trip safely.
- Every installed file must be recorded, including imported skill references.

## Status

Implemented

Enacted by [installation design](../explanation/installation.md) and [`install.sh`](../../install.sh).
