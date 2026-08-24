# Architecture

Cog is a standalone Bash CLI plus runtime skills, agent definitions, structured policy data, and model-readable references. This page owns the current component map; [ADR-0002](../decisions/ADR-0002-standalone-loader-based-cli.md) records why the loader boundary was chosen.

## Components and boundaries

`bin/cog` resolves the installed or source application root, loads shared functions, then dispatches dash-form commands through `lib/loader.sh`. Command modules own one public operation, shared `cog::fn::*` helpers own reusable mechanics, and skills call those operations while retaining sequencing and judgment.

`data/` owns structured tables computed over by the CLI. `skill-refs/` owns prose and templates that runtime skills read or deploy. Pre-commit is the quality-gate source of truth; the task runner exposes those same lanes.

Plan folding follows the same boundary. Skill prose owns the semantic judgment that turns a base plan plus annotated review into one coherent plan. `cog plan-review` owns deterministic item extraction, manifest coverage, and hashes. `cog plan-doc` owns the structural shape required at every plan handoff.

One command name that no module owns falls through to an external `cog-<name>` executable, which cog `exec`s as a separate process. That seam is the only extension point: first-party commands always win, cog's Bash stays private, and cog inspects plugins without installing or trusting them. See [plugins](./plugins.md).

## Current constraints

Machine output and file-first artifacts are the default. Installation is manifest-owned, repository knowledge is self-contained, and every public command keeps its line-2 description sentinel.

## Unresolved

- Command metadata does not yet expose per-option completion.
