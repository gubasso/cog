# Bash CLI Spec

Bash-specific conventions for building a CLI tool: layout, entry point, strict-mode caveats, module organisation, testing, linting, install, and distribution.

For the language-agnostic principles, see [`tech/cli-design/`](../../../cli-design/). Every Bash-specific rule here applies the general principles to the specifics of Bash.

## Files

| File                                                     | Hook                                                                                                                                                                         |
| -------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| [bash-cli-project-specs.md](./bash-cli-project-specs.md) | Full reference: directory layout, strict mode, modules, loader, ShellCheck discipline, error handling, signals, tempfiles, `bats-core` testing, install + XDG, distribution. |

## TL;DR

- Every non-trivial runnable entry point uses an explicit `main()` and final `main "$@"`.
- `set -euo pipefail` everywhere; know its caveats (`||true`, subshell exit-code propagation).
- Use `local` for function variables, `readonly` for constants, split status-bearing declaration assignments, and prefer builtins/parameter expansion for simple Bash-native transformations.
- One function per file: `libexec/commands/` for CLI subcommands, top-level `functions/` for a sourced framework surface, and `lib/` for shared libraries.
- ShellCheck on every file; treat warnings as errors.
- `bats-core` for tests; one test file per subcommand.
- XDG paths by role: config under `${XDG_CONFIG_HOME:-$HOME/.config}`, user code/data under `${XDG_DATA_HOME:-$HOME/.local/share}`, and explicit `~/.local/bin` symlinks for user commands exposed on `PATH`.
- Logs to `${XDG_STATE_HOME:-$HOME/.local/state}/<app>/<app>.log` — same default as every other language in this spec.

## See also

- [General — Logging & Output](../../../cli-design/01-logging-and-output.md)
- [General — Error Messages](../../../cli-design/02-error-messages.md)
- [General — Config Precedence](../../../cli-design/03-config-precedence.md)
- [General — Designing for LLM Agents](../../../cli-design/05-designing-for-llm-agents.md)
