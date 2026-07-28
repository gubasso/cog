# Bash — Review Guide

## When to load

Any `.sh`/`.bash` file, or any file with a `#!/usr/bin/env bash` shebang.

## Top review heuristics

### Strict mode (mandatory)

- Missing `set -euo pipefail` near the top → `[blocking]` "Errors silently propagate otherwise."
- `IFS` not set (`IFS=$'\n\t'`) when the script processes filenames or paths → `[important]`.

### Quoting

- Unquoted `$var` in any non-numeric context → `[blocking]` "Word-splitting + glob expansion bug waiting to happen."
- `"$@"` vs `$*` confusion. `"$@"` preserves argv; `"$*"` joins by IFS — they are not interchangeable.
- `${var}` where `${var?error}`, `${var:-default}`, `${var:=default}` would express intent → `[suggestion]`.

### Command injection

- `eval "$user_input"` → `[blocking]`.
- `bash -c "$cmd"` with composed `$cmd` → `[blocking]`.
- `ssh host "ls $dir"` with `$dir` from user → `[blocking]` "Quotes from local shell consumed; remote shell re-interprets."
- Building command line as a string and passing through `sh -c` → `[blocking]`.

### Process management

- Background job without `wait` or trap-cleanup → `[important]` "Orphans on signal."
- `kill $!` without handling the race where the child already exited → `[important]`.
- `trap 'cleanup' EXIT` missing on scripts that create temp files → `[important]`.

### Test discipline (`[[ ]]` vs `[ ]`)

- `[ ]` (POSIX test) used where `[[ ]]` is available → `[suggestion]` "`[[ ]]` is bash-only but safer (no word splitting on operands, supports `&&`/`||`/`=~`)."
- `=` vs `==` inside `[ ]` (POSIX prefers `=`).
- `-a` / `-o` inside `[ ]` (deprecated) → `[important]` "Use `&&`/`||` between separate `[ ]` invocations."

### Common bugs

- `pipefail` not set, and the script checks `$?` of a pipeline → `[important]` "Only the last command's exit code is captured without `pipefail`."
- `cd $dir` without checking the cd succeeded (`cd $dir || exit`) → `[important]`.
- `for f in $(ls)` → `[blocking]` "Breaks on filenames with spaces; use `for f in *` or `find -print0 | xargs -0`."
- `if [ "$?" -eq 0 ]` instead of `if cmd; then` → `[important]`.
- `read` without `-r` → `[important]` "Backslashes get interpreted."

### POSIX vs bash

- Bashism in a script with `#!/bin/sh` shebang → `[blocking]` "Either change shebang to bash or use POSIX-only constructs."

### Anti-patterns

- Anything `bash` does on Linux but not on macOS (e.g., `readlink -f`, GNU `sed`) without a portability comment → `[important]` "Tag with the target platform."
- `which cmd` instead of `command -v cmd` → `[suggestion]`.
- `grep | wc -l` instead of `grep -c` → `[nit]`.
- `cat file | cmd` instead of `cmd < file` (useless cat) → `[nit]`.

## CLI specifics (when `--cli` is active)

For shared CLI design principles see `$(cog skill-refs path cli-design/AGENTS.md)`; prefer the project's own CLI spec when present. Bash CLI baseline to check:

- Strict mode template, `lib/`+`bin/` layout, shellcheck/bats config.

CLI-specific review flags:

- No `--help` flag → `[important]`.
- Help text not snapshot-tested → `[suggestion]`.
- Exit code is always `1` on error → `[important]` "Use BSD sysexits codes (`64–78`)."
- `log_info`/`log_error` macros printing to stdout → `[important]` "stderr for UX, stdout for results."
- Hard-coded paths to other CLIs (`/usr/local/bin/foo`) instead of `PATH` lookup → `[important]`.
- No `bats` (or other test runner) and the script has non-trivial logic → `[important]` "CLI scripts deserve tests."

## Linters

`shellcheck` (mandatory) + `shfmt` for formatting. If `shellcheck` is missing from the project's pre-commit config, flag `[important]`. Look at the diff for `# shellcheck disable=` directives that lack a justifying comment — flag those `[important]` too.

## See also

- General: [../code-quality-universal.md](../../code-quality-universal.md), [../security-review.md](../../security-review.md) (command injection).
- Upstream guide doesn't cover Bash specifically; canonical reference is `bash-cli-spec/` above.
