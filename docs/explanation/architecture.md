# Architecture overview

`cog` is a Bash command with a small eager core and a load-on-dispatch command surface.

The executable shim, `bin/cog`, resolves its real path through symlinks. That lets an installed `$PREFIX/bin/cog` symlink find the self-contained app root under `$PREFIX/lib/cog`. Once it knows `LIB_DIR`, the shim sources core helpers, shared functions, and `lib/core.sh`.

`cog::main` handles process-wide setup before any command module runs. It reads `VERSION`, parses global flags, loads config, initializes UI/log behavior, and handles global operations such as `--version`, root `--help`, and `--print-config`.

Command dispatch is intentionally mechanical. `lib/loader.sh` accepts a command slug, rejects unsafe names, maps dashes to underscores, sources `lib/commands/cmd_<slug>.sh`, and calls `cog::cmd::<slug>`. A request for `cog print-config` therefore loads `cmd_print_config.sh` and calls `cog::cmd::print_config`.

Command modules own command behavior. Shared mechanics live under `lib/functions/` as `cog::fn::*`, so queue parsing, JSON writing, run-directory creation, Codex invocation, review helpers, and related behavior have one implementation.

`cog` is machine-facing. Commands emit structured stdout or JSON fragments that skills can validate and compose, return BSD sysexits-compatible codes, and write file-first log-messages under XDG state paths. Claude and Codex skills use `cog` as their mechanics layer, while the skill bodies keep sequencing, judgment, and runtime-specific orchestration.

Installation follows the same separation. The app payload is copied into `$PREFIX/lib/cog`, while skills and agents are copied into the runtime overlay trees under the user's home directory. The installer records owned files in an XDG state manifest so uninstall can remove cog-owned files without deleting user-authored skill or agent content.
