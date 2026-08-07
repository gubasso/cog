# ADR-0002: Use a standalone loader-based CLI

## Context and Problem Statement

The CLI needs to run from source and installed layouts while keeping command logic discoverable. A stable loader boundary must map public dash-form names to Bash modules.

## Considered Options

- One monolithic script
- A framework-dependent command tree
- A standalone Bash loader with command modules

## Decision Outcome

Chosen option: `Use a standalone Bash loader with command modules` — it preserves portability while keeping commands independently testable.

## Consequences

- Commands remain easy to discover and install.
- The loader and line-2 description sentinel are public internal contracts.

## Status

Implemented

Enacted by [architecture](../explanation/architecture.md), [CLI runtime](../explanation/cli-runtime.md), and [`bin/cog`](../../bin/cog).
