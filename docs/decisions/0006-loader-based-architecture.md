# ADR-0006: Loader-based architecture

## Context and Problem Statement

The old helper could have been lifted as one large Bash file, but `cog` needs a growing command
surface with testable modules, stable namespacing, and generated help. A monolith would make
dispatch, command ownership, and documentation harder to keep coherent.

## Considered Options

- Lift the old helper into one script.
- Source every command eagerly on startup.
- Load command modules on dispatch.

## Decision Outcome

Chosen option: **loader-based architecture**. `bin/cog` eagerly sources core functions, parses
global flags, loads config, and calls `cog::loader::dispatch`. The loader maps a dash-form command
to `lib/commands/cmd_<slug>.sh` and invokes `cog::cmd::<slug>`. Shared behavior lives in
`lib/functions/` under `cog::fn::*`.

## Consequences

- Good: command files are small ownership units with predictable names.
- Good: root help can discover commands from `cmd_*.sh` and line-2 `desc:` sentinels.
- Good: command dispatch rejects unsafe names before building paths.
- Bad: command filenames, handler names, and desc sentinels must stay synchronized.
- Bad: static mirrors such as completion and man source need drift tests against command modules.

## Status

Implemented.
