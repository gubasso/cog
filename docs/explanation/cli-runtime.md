# CLI runtime

The CLI runtime maps one public command name to one module and one handler. [ADR-0002](../decisions/0002-standalone-loader-based-cli.md) owns the loader choice, and [ADR-0003](../decisions/0003-machine-facing-output-contract.md) owns stream and result behavior.

## Components and boundaries

`bin/cog` loads configuration and shared functions before `lib/loader.sh` derives `cmd_<slug>.sh` and `cog::cmd::<slug>`. Commands validate their own arguments and use shared error, JSON, UI, and environment helpers.

Stdout carries machine results. Stderr carries diagnostics and optional human progress. Exit values follow the documented sysexits mapping in the command reference.

## Current constraints

Command-specific mechanics stay in command modules. Reused parsing, validation, and filesystem behavior move to namespaced functions. The loader supports source and installed roots without a framework dependency.

## Unresolved

- Rich per-command option metadata remains deferred.
