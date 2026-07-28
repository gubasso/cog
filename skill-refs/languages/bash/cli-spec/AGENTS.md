---
digest-of: languages/bash/cli-spec
last-synced: 2026-07-23
source-files:
  - README.md
  - bash-cli-project-specs.md
token-estimate: 650
---

# AGENTS

## Scope

Bash-specific CLI conventions: directory layout, strict mode, module organization, testing, linting, installation, distribution, and Bash idioms for the general facing-category taxonomy.

## Key Points

- **Entry points**: every non-trivial runnable Bash entry point uses explicit `main()` and ends with `main "$@"` or the project-namespaced equivalent. Only truly trivial one-liners are exempt. `bin/<name>` stays a thin shim resolving symlinks, sourcing `lib/helpers.sh`, `lib/loader.sh`, `lib/core.sh`, then calling `mycli::main "$@"`.
- **Strict mode**: `set -euo pipefail` + `shopt -s inherit_errexit`. Know caveats: `local var=$(...)` masks exit, pipefail can fail on SIGPIPE, never set global `IFS`.
- **Function idioms**: use `local` for function variables and `readonly` for constants. Split command-substitution assignments from `local`/`export`/`readonly` when the command status matters. Prefer builtins and parameter expansion for simple Bash-native transformations.
- **Source/execute guard**: `BASH_SOURCE[0] == "$0"` guards are only for intentional dual-mode scripts, not ordinary runnable entry points.
- **Module layout**: One public function per file. `libexec/commands/cmd_<n>.sh` defines `mycli::cmd::<n>`. Top-level `functions/fn_<n>.sh` defines `mycli::fn::<n>` when a sourced framework surface exists. `lib/` is for shared libraries; private helpers are prefixed `__`.
- **Lazy loading**: `lib/loader.sh` sources commands on dispatch, keeping startup O(1).
- **ShellCheck**: `.shellcheckrc` with `external-sources=true`, `source-path=SCRIPTDIR`. Every `source` gets an explicit `# shellcheck source=` directive. Disables require justification comments.
- **Errors/signals**: `mktemp -d || exit 1` + `trap ... EXIT INT TERM`. SIGINT=130, SIGTERM=143. `printf` over `echo`.
- **Output/logging**: stdout is the result (data or machine-output) only. Stderr carries progress and prompts (human-facing) plus error reports for **both** categories — prose for human-facing, structured JSON for machine-facing — and an explicit log mirror. Program logs default to an XDG state file. The stdout/stderr split is universal; errors never go to stdout.
- **Human-UX idioms**: gate color, tables, and spinners with `[[ -t 1 ]]` or `[[ -t 2 ]]`.
- **Testing**: `bats-core` with `bats-support`, `bats-assert`, `bats-file` as submodules. One test file per subcommand.
- **Formatting**: `shfmt -i 2 -ci -bn -s`. All checks via pre-commit.
- **Install/XDG**: `install.sh` honors `PREFIX` (system) and XDG (user). Split config (`${XDG_CONFIG_HOME:-$HOME/.config}`) from data/code (`${XDG_DATA_HOME:-$HOME/.local/share}`); expose user commands through explicit `~/.local/bin` symlinks. Bash completions and man pages are generated via scdoc; expose man text through a subcommand when agents need to read it from the CLI.
- **Non-negotiables**: Namespaced functions, XDG-aware installer, trap cleanup, agent-facing surface (`help`/usage, `--json`, `doctor`, `init`, completion, man-via-subcommand, exit codes).

## Source Map

| Topic                                                         | File                        |
| ------------------------------------------------------------- | --------------------------- |
| Overview and TL;DR                                            | `README.md`                 |
| Full spec: layout, strict mode, modules, testing, install, CI | `bash-cli-project-specs.md` |

## Maintenance Notes

- Facing-category and agent-facing surface rules (output-as-prompt, error shape) are in the general `cli-design/05-designing-for-llm-agents.md`, not duplicated here.
- Regenerate when bash ecosystem tooling changes (bats major version, shellcheck rules).
