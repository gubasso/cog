# ADR-0034: Extend cog through external executables

## Context and Problem Statement

Separate programs should be reachable as `cog <name>` without cog embedding knowledge of them. Cog sources more than fifty shared function files into one flat global namespace under strict mode, so any in-process extension would make every internal helper a public compatibility surface and let a third-party fault abort cog itself.

## Considered Options

- An external executable convention: `cog <name>` execs `cog-<name>`.
- Loadable Bash command modules from a plugin search path.
- Composed resource roots so plugins contribute skills, skill-refs, and data tables.
- A managed plugin system with a catalog, checksums, and install verbs.

## Decision Outcome

Chosen option: `an external executable convention` — it is the only option that gives a real isolation boundary without cog owning a schema, a catalog, or a third party's lifecycle.

Cog resolves `cog-<name>` from `$COG_PLUGIN_DIR` then `$PATH`, execs it with argv verbatim, and returns its exit status. First-party commands always win, structurally: resolution is reached only when the module check has already failed. Cog inspects plugins through a side-effect-free metadata probe that is never a dispatch gate, and never installs them. Internal Bash files are private; the CLI is the contract.

git, cargo, and kubectl all converged on this shape. Cargo explicitly tells tool authors not to link its library, and mise, AWS, and the asdf ecosystem document the costs of the in-process alternative.

## Consequences

- Good: a plugin fault cannot corrupt or abort cog; internals stay free to change; no schema, catalog, or trust machinery to maintain.
- Good: `cog --help`, completion, and the man page stay first-party and byte-stable.
- Bad: plugins are invisible to default help and must be discovered through `cog plugin list`.
- Bad: cog makes no claim about a plugin's provenance or safety.
- Bad: each process boundary costs a fork, so the seam is unsuitable for anything called in a tight loop.

## Status

Implemented

Enacted by [slice 013](../plan/slices/013-plugin-protocol/README.md), [`loader.sh`](../../lib/loader.sh), [`fn_plugin.sh`](../../lib/functions/fn_plugin.sh), and [`cmd_plugin.sh`](../../lib/commands/cmd_plugin.sh).
