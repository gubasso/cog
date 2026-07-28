# Bash CLI Project — Specs Overview

> Prerequisite: [General CLI principles](../../../cli-design/) for architecture, logging, errors, config, and coding-style rules that apply to every CLI regardless of language. Facing-category consequences follow [General — Facing category & message types](../../../cli-design/00-architecture.md#facing-category--message-types).
>
> For the **machine-facing standard surface** (`help`/usage, `--json`, output-as-prompt, error shape, `doctor`, `init`, completion, man-via-subcommand, exit-code conventions, config precedence, dry-run discipline, skill wrapper, evals), see [Designing for LLM Coding Agents](../../../cli-design/05-designing-for-llm-agents.md). Rules there apply to this stack; they are not duplicated here.

Bash-specific conventions for building a CLI tool: layout, entry point, strict-mode caveats, module organisation, testing, linting, install, and distribution.

---

## Directory Structure

```text
my-cli/
├── bin/
│   └── my-cli                    # thin shim → loader → main "$@"
├── lib/
│   ├── loader.sh                 # source-on-dispatch
│   ├── core.sh                   # main(), global flags, dispatch
│   ├── helpers.sh                # __log_err, __require, etc. (eager)
│   └── render.sh                 # shared libraries only
├── libexec/
│   └── commands/
│       ├── cmd_foo.sh            # defines mycli::cmd::foo
│       └── cmd_bar.sh
├── functions/
│   ├── fn_parse_args.sh          # defines mycli::fn::parse_args
│   └── fn_render_table.sh
├── completions/
│   └── my-cli.bash
├── man/
│   └── my-cli.1.scd              # scdoc source → compiled to .1
├── test/
│   ├── test_helper/
│   │   ├── bats-support/         # submodule
│   │   ├── bats-assert/          # submodule
│   │   ├── bats-file/            # submodule
│   │   └── common-setup.bash
│   └── cmd_foo.bats
├── .shellcheckrc
├── .editorconfig
├── Makefile
├── install.sh
└── uninstall.sh
```

One public function per file; filename encodes the function name. `lib/` holds shared libraries, `libexec/commands/` holds CLI subcommands, and top-level `functions/` holds sourced user-facing functions when the project also exposes a shell framework. Same shape as a well-organised interactive-shell package, applied to a standalone CLI.

---

## Entry Points

Every non-trivial runnable Bash entry point uses an explicit `main` function and ends by calling `main "$@"` or the project-namespaced equivalent. This applies to `bin/<name>` shims, maintenance scripts, installers, and single-file utilities. The only exception is a genuinely trivial one-liner: no parsing, branching, traps, temporary state, helper functions, or multiple commands.

Single-file utility shape:

```bash
#!/usr/bin/env bash
set -euo pipefail
shopt -s inherit_errexit 2>/dev/null || true

main() {
  local name="${1:-world}"
  printf 'hello, %s\n' "$name"
}

main "$@"
```

Multi-file CLI shim shape (`bin/my-cli`):

```bash
#!/usr/bin/env bash
set -euo pipefail
shopt -s inherit_errexit 2>/dev/null || true   # bash 4.4+

# Resolve script path through symlinks (stow, make install, etc.)
src="${BASH_SOURCE[0]}"
while [[ -L "$src" ]]; do
  dir="$(cd -P "$(dirname "$src")" && pwd)"
  src="$(readlink "$src")"
  [[ "$src" != /* ]] && src="$dir/$src"
done
SCRIPT_DIR="$(cd -P "$(dirname "$src")" && pwd)"
readonly SCRIPT_DIR
LIB_DIR="${SCRIPT_DIR}/../lib"
readonly LIB_DIR

# shellcheck source=../lib/helpers.sh
source "${LIB_DIR}/helpers.sh"
# shellcheck source=../lib/loader.sh
source "${LIB_DIR}/loader.sh"
# shellcheck source=../lib/core.sh
source "${LIB_DIR}/core.sh"

mycli::main "$@"
```

- Shims stay thin — no business logic in `bin/`.
- Symlink resolution matters: `stow`, `make install`, and `ln -s` in `~/.local/bin` all break the naive `dirname "${BASH_SOURCE[0]}"` idiom.
- `inherit_errexit` fixes the silent-`set -e`-disables-in-subshells pitfall; guarded for pre-4.4 bash.
- A `BASH_SOURCE[0]` source/execute guard is only for intentional dual-mode scripts. Do not make it the default for ordinary runnable entry points.

Intentional dual-mode script shape:

```bash
main() {
  printf '%s\n' "running"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@"
fi
```

Further reading: [Google Shell Style Guide](https://google.github.io/styleguide/shellguide.html), [Greg's Wiki BashGuide Practices](https://mywiki.wooledge.org/BashGuide/Practices), and [Nick Janetakis on source/execute guards](https://nickjanetakis.com/blog/detect-if-a-shell-script-is-being-executed-or-sourced).

---

## Strict Mode — Default, Not Gospel

```bash
set -euo pipefail
shopt -s inherit_errexit failglob nullglob lastpipe
```

Treat as the default. Known limits:

- `set -e` is disabled inside command substitutions, `if`/`&&`/`||` chains, and `local var=$(...)` (the `local` masks the inner exit). See [ShellCheck SC2310/SC2311](https://www.shellcheck.net/wiki/SC2310).
- `set -o pipefail` can turn a benign SIGPIPE (producer killed by a short-circuiting `grep -q`) into a failure.
- `set -u` overlaps with shellcheck; keep it for defence-in-depth.
- **Do not set global `IFS`.** Changing word-splitting semantics globally breaks sourced code that assumes the shell default. Quote everything (`"$@"`, `"${arr[@]}"`) and use arrays; that solves the real problem without global side effects. (Critique: [Gondža](https://olivergondza.github.io/2019/10/01/bash-strict-mode.html), [BashFAQ/105](https://mywiki.wooledge.org/BashFAQ/105).)

For load-bearing logic, prefer an explicit `|| return` / `trap '...' ERR` over trusting `set -e` implicitly.

---

## Function Scope, Constants, and Builtins

- Use `local` for function variables so helpers do not leak names into callers.
- Use `readonly` for constants after assignment. When the assignment involves command substitution, split assignment from `readonly` so the command status stays visible.
- Split `local`, `export`, and `readonly` command-substitution assignments whenever the command's status matters; declaration builtins can mask the substitution's exit code.
- Prefer Bash builtins and parameter expansion for simple Bash-native transformations such as trimming prefixes, defaults, case conversion, and string replacement. Use external tools when they are clearer or doing real tool work.

```bash
load_config() {
  local config_path
  config_path="$(resolve_config_path "$@")" || return

  readonly DEFAULT_FORMAT="text"

  local name="${1:-}"
  name="${name#prefix-}"
  printf '%s\n' "$name"
}
```

Further reading: [Google Shell Style Guide](https://google.github.io/styleguide/shellguide.html), [ShellCheck SC2155](https://www.shellcheck.net/wiki/SC2155), and [Pure Bash Bible](https://github.com/dylanaraps/pure-bash-bible).

---

## Module Layout: One Function per File

This is the core organisational pattern. Makes the code easy for humans and LLMs to reason about, and keeps startup O(1) via lazy sourcing.

### Naming

| Path                          | Defines                     | Visibility |
| ----------------------------- | --------------------------- | ---------- |
| `libexec/commands/cmd_<n>.sh` | `mycli::cmd::<n>`           | public     |
| `functions/fn_<n>.sh`         | `mycli::fn::<n>`            | public     |
| `lib/helpers.sh`              | `__log_err`, `__require`, … | shared     |
| `lib/<name>.sh`               | shared helpers/libraries    | shared     |
| (any file) `__<n>`            | private helper, same file   | private    |

- **One public function per file.** Filename mirrors the function name so the dispatcher can derive it without a lookup table.
- `__`-prefix marks private helpers (sourced alongside, not exported).
- Every `.sh` under `lib/` starts with `# shellcheck shell=bash` (no shebang — these are sourced, not executed).

### Self-describing files

Each file documents itself on line 2 with a sentinel the help/man generator can harvest:

```bash
# shellcheck shell=bash
: 'desc: Dispatch a message to a roost.'

mycli::cmd::dispatch() {
  local -r to="$1"; shift
  # ...
}
```

The `desc:` line is lazy-loaded — costs nothing at startup, parseable by a trivial `grep`-driven help generator on demand.

### Loader (source on dispatch)

`lib/loader.sh`:

```bash
# shellcheck shell=bash
mycli::loader::dispatch() {
  local sub="$1"; shift
  local path="${LIB_DIR}/../libexec/commands/cmd_${sub}.sh"
  if [[ ! -r "$path" ]]; then
    mycli::helpers::die 2 "unknown command: ${sub}"
  fi
  # shellcheck source=/dev/null
  source "$path"
  "mycli::cmd::${sub}" "$@"
}
```

Startup stays O(1) regardless of command count — commands load only when invoked. This is the same shape as a Bash autoloader: source on first use, cache nothing.

### Host / env overlays

Use XDG paths by role. True configuration belongs under `${XDG_CONFIG_HOME:-$HOME/.config}/my-cli/`; user-authored code or command sources belong under `${XDG_DATA_HOME:-$HOME/.local/share}/my-cli/`. Expose any user command on `PATH` with an explicit symlink in `~/.local/bin` instead of implicitly prepending a whole commands directory. Same idea as per-host overlays in interactive Bash startup files: drop-in config files are sourced in lexical order after built-in defaults, while executable exposure remains intentional.

---

## ShellCheck Discipline

`.shellcheckrc` at repo root:

```text
external-sources=true
source-path=SCRIPTDIR
source-path=SCRIPTDIR/lib
shell=bash
```

Rules:

- Every cross-file `source` gets an explicit `# shellcheck source=<path>` directive (or rely on `source-path=` above). Without it, shellcheck silently skips the file and misses half the real bugs.
- `# shellcheck disable=SC<n>` must carry a one-line justification comment; unexplained disables fail review.
- Reference: [shellcheck directives](https://github.com/koalaman/shellcheck/wiki/Directive).

---

## Errors, Signals, Temp Files

```bash
tmpdir="$(mktemp -d)" || exit 1
trap 'rm -rf "$tmpdir"' EXIT
trap 'rm -rf "$tmpdir"; exit 130' INT
trap 'rm -rf "$tmpdir"; exit 143' TERM
```

- Single-quoted trap bodies (variables expand at trap time, not registration time).
- `mktemp -d` always with `|| exit 1`, always paired with an `EXIT` trap.
- SIGINT exits `130`, SIGTERM `143` (128 + signal number).
- `printf '%s\n'` over `echo` (portable across bash versions).
- stdout is the result only (command data or machine-output); stderr carries progress/prompts (human-facing) and error reports for both categories — prose for human-facing, structured JSON for machine-facing — plus an explicit log mirror; program logs are file-first. The stdout/stderr split is universal; errors and a non-zero exit code never go to stdout.

Exit-code conventions (`0`/`1`/`2` + `sysexits.h` ranges + `128+N`) are documented in [Designing for LLM Coding Agents](../../../cli-design/05-designing-for-llm-agents.md) §2.4 and in [General — Error Messages](../../../cli-design/02-error-messages.md) — the bash side just has to implement them consistently.

---

## Testing (bats-core)

> Prerequisite: [General principles — Testing Strategy](../../../cli-design/08-testing-and-quality/testing-strategy.md) for the pyramid, tier table, isolation rules, and what to mock. This section is the bats-core implementation.

Layout:

```text
test/
├── test_helper/
│   ├── bats-support/        # git submodule
│   ├── bats-assert/         # git submodule
│   ├── bats-file/           # git submodule
│   └── common-setup.bash
└── cmd_foo.bats
```

`test/test_helper/common-setup.bash`:

```bash
_common_setup() {
  load 'bats-support/load'
  load 'bats-assert/load'
  load 'bats-file/load'

  # Hermetic git environment — see "Sanitise the git environment" below.
  local git_env_vars=()
  mapfile -t git_env_vars < <(git rev-parse --local-env-vars 2>/dev/null || :)
  ((${#git_env_vars[@]})) && unset "${git_env_vars[@]}"

  PATH="${BATS_TEST_DIRNAME}/../bin:$PATH"
}
```

`test/cmd_foo.bats`:

```bash
setup() {
  load 'test_helper/common-setup'
  _common_setup
}

@test "foo --bar outputs expected" {
  run my-cli foo --bar
  assert_success
  assert_output "expected"
}
```

### Sanitise the git environment (pre-commit pitfall)

A test that creates a throwaway git repo (`git init` in a tmpdir, then `add`/`commit`/`worktree
add`) passes when you run `bats test/` directly but **fails only when the same suite runs from a git hook** (e.g. pre-commit's local `test` stage). Symptoms: `error: invalid object … for
'<some path from the PARENT repo>'`, `Error building trees`, `fatal: .git/index: index file open
failed`, or a bats `Executed N-1 instead of expected N tests` warning when the crash aborts a test mid-run.

Root cause: git hooks **export the parent repo's local git environment** — `GIT_DIR`, `GIT_INDEX_FILE`, `GIT_WORK_TREE`, `GIT_OBJECT_DIRECTORY`, `GIT_COMMON_DIR`, … — into the hook process and everything it spawns. `bats` inherits them, so a test's `git -C "$tmpdir" …` changes the working directory but still reads the inherited `GIT_INDEX_FILE`, operating on the **parent repo's staged index** instead of the throwaway repo's. `git -C`, `--git-dir`, and friends do **not** override these env vars.

Fix once, at the shared test-harness boundary (`common-setup.bash` above), not per-test and not with shellcheck disables. Clear git's own canonical repo-local variable list:

```bash
unset $(git rev-parse --local-env-vars)        # documented githooks(5) idiom
# array-safe form (preferred under `set -u` / strict mode):
local git_env_vars=()
mapfile -t git_env_vars < <(git rev-parse --local-env-vars 2>/dev/null || :)
((${#git_env_vars[@]})) && unset "${git_env_vars[@]}"
```

`git rev-parse --local-env-vars` _is_ the authoritative list (no hardcoding; auto-tracks new git versions). This is the same sanitisation git's own `t/test-lib.sh` performs globally, the pattern [`githooks(5)`](https://git-scm.com/docs/githooks) documents for hooks that touch a foreign repo, and the exact class of bug pre-commit guards internally in its `no_git_env()` (`GIT_INDEX_FILE` is commented there as _"Causes 'error invalid object …' during commit"_).

Reference: [bats-core tutorial](https://bats-core.readthedocs.io/en/stable/tutorial.html).

---

## Linting / Formatting

All checks run through **pre-commit** (see root CLAUDE (path: `../../../../CLAUDE.md`) § "Linting & Validation" for the repo-wide policy):

- [shellcheck](https://www.shellcheck.net/) — static analysis.
- [shfmt](https://github.com/mvdan/sh) — formatter. Canonical flags: `shfmt -i 2 -ci -bn -s`.
- Do not invoke linters directly; add them to `.pre-commit-config.yaml`.

---

## Install / XDG Paths

`install.sh` honours both `PREFIX` (system) and XDG (user):

| Artifact        | System                                                    | User                                                                |
| --------------- | --------------------------------------------------------- | ------------------------------------------------------------------- |
| binary          | `$PREFIX/bin/`                                            | `$HOME/.local/bin/`                                                 |
| lib tree        | `$PREFIX/lib/my-cli/`                                     | `$HOME/.local/lib/my-cli/`                                          |
| bash completion | `$(pkg-config --variable=completionsdir bash-completion)` | `${XDG_DATA_HOME:-$HOME/.local/share}/bash-completion/completions/` |
| man page        | `$PREFIX/share/man/man1/`                                 | `${XDG_DATA_HOME:-$HOME/.local/share}/man/man1/`                    |
| config          | `/etc/my-cli/config.toml`                                 | `${XDG_CONFIG_HOME:-$HOME/.config}/my-cli/config.toml`              |
| state           | `/var/lib/my-cli/`                                        | `${XDG_STATE_HOME:-$HOME/.local/state}/my-cli/`                     |
| cache           | `/var/cache/my-cli/`                                      | `${XDG_CACHE_HOME:-$HOME/.cache}/my-cli/`                           |

- Detect root vs user install via `[[ $EUID -eq 0 ]]`.
- `uninstall.sh` reads a manifest written by `install.sh` at install time.
- Reference: [XDG Base Directory spec](https://specifications.freedesktop.org/basedir-spec/basedir-spec-latest.html).

`Makefile` wraps `install` / `uninstall` / `test` / `lint` / `man`.

Bash human-UX should gate color, tables, and spinners with `[[ -t 1 ]]` or `[[ -t 2 ]]` as appropriate. Completion scripts and `scdoc`/man artifacts support both human use and agent self-documentation; expose man text through a `man` subcommand when the CLI needs agents to read it without shelling out to `man(1)`.

Config precedence: see [`cli-design/03-config-precedence.md`](../../../cli-design/03-config-precedence.md) for the canonical 5-layer ladder. Secret handling and missing-config error shape: see [`cli-design/05-designing-for-llm-agents.md §2.9`](../../../cli-design/05-designing-for-llm-agents.md#29-config-via-env--file-never-interactive-prompts).

---

## Man Page

Prefer [scdoc](https://git.sr.ht/~sircmpwn/scdoc) over hand-rolled `.1` or pandoc — tiny C dep, markdown-ish source, deterministic output:

```text
man/my-cli.1.scd   →   man/my-cli.1   (built by Makefile)
```

---

## Distribution

| Approach                                                    | Use case                                           |
| ----------------------------------------------------------- | -------------------------------------------------- |
| Multi-file + `install.sh`                                   | Default for this repo's tools; fallback everywhere |
| [bashly](https://github.com/bashly-framework/bashly) bundle | Single-file build for `curl \| sh` installers      |
| Homebrew formula                                            | Users on macOS / linuxbrew                         |
| AUR `PKGBUILD`                                              | Arch users                                         |
| Nix flake                                                   | Reproducible dev shells, pinned toolchain          |
| `.deb` via `dh_make`                                        | Debian/Ubuntu packaging                            |

Avoid `shc` (obfuscating C-wrapper, not a bundler — wrong tool).

---

## CI

Minimum viable GitHub Actions matrix:

```yaml
jobs:
  check:
    strategy:
      matrix:
        bash: ['4.4', '5.0', '5.2']
    steps:
      - uses: actions/checkout@v4
        with: { submodules: recursive }
      - run: shellcheck -x bin/* lib/**/*.sh
      - run: shfmt -d -i 2 -ci -bn -s bin lib
      - run: bats test/
```

---

## Non-Negotiables

1. `set -euo pipefail` + `shopt -s inherit_errexit` (with documented caveats).
2. shellcheck clean; `source=`/`source-path=` directives wired up.
3. shfmt clean (`-i 2 -ci -bn -s`), config checked in.
4. Namespaced functions (`mycli::<ns>::<fn>`), one public function per file.
5. XDG-aware, `PREFIX`-overridable installer; uninstall via manifest.
6. bats-core tests under `test/` with `test_helper/` submodules; `common-setup.bash` clears git's repo-local env (`unset $(git rev-parse --local-env-vars)`) so hook-run suites stay hermetic.
7. `trap ... EXIT INT TERM` cleanup for any script that creates temp state.
8. `printf` over `echo`; program logs default to XDG state file; stdout is data/machine-output; stderr carries terminal UX and only mirrors logs by explicit option.
9. Agent-facing surface per [Designing for LLM Coding Agents](../../../cli-design/05-designing-for-llm-agents.md) (`help`/usage, `--json`, error shape, `doctor`, `init`, completion, man-via-subcommand, dry-run, exit codes).
