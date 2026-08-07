# Architecture

Cog is a standalone Bash CLI plus runtime skills, agent definitions, structured policy data, and model-readable references. This page owns the current component map; [ADR-0002](../decisions/ADR-0002-standalone-loader-based-cli.md) records why the loader boundary was chosen.

## Components and boundaries

`bin/cog` resolves the installed or source application root, loads shared functions, then dispatches dash-form commands through `lib/loader.sh`. Command modules own one public operation, shared `cog::fn::*` helpers own reusable mechanics, and skills call those operations while retaining sequencing and judgment.

`data/` owns structured tables computed over by the CLI. `skill-refs/` owns prose and templates that runtime skills read or deploy. Pre-commit is the quality-gate source of truth; the task runner exposes those same lanes.

## Current constraints

Machine output and file-first artifacts are the default. Installation is manifest-owned, repository knowledge is self-contained, and every public command keeps its line-2 description sentinel.

## Unresolved

- Command metadata does not yet expose per-option completion.
