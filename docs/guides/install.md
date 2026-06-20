# Install cog

## Prerequisites

`cog` is a Bash CLI. Runtime checks in the installed command expect these core tools:

- `bash`
- `jq`
- `git`
- `find`
- `sed`
- `mktemp`

Queue helpers also require `yq`. Man-page installation can use `scdoc`; when `scdoc` is missing and
no prebuilt `man/cog.1` exists, the installer skips the man page with a warning.

## Default Install

```bash
./install.sh
```

By default, `PREFIX` is `$HOME/.local`, `XDG_DATA_HOME` is `$HOME/.local/share`, and
`XDG_STATE_HOME` is `$HOME/.local/state`.

## Logging Behavior

`cog` writes logs to XDG state by default, normally `$XDG_STATE_HOME/cog/cog.log` with
`XDG_STATE_HOME` defaulting to `$HOME/.local/state`. Stderr log mirroring is opt-in through CLI
verbosity or logging options. Log levels include at least `info`, `warn`, `error`, and `debug`.

## Custom Prefix

```bash
PREFIX="$HOME/.local" ./install.sh
```

Set `PREFIX`, `XDG_DATA_HOME`, or `XDG_STATE_HOME` before running the installer when you need a
custom app, data, or state location.

## Installed Files

The installer copies the app payload into `$PREFIX/lib/cog`, creates a PATH symlink at
`$PREFIX/bin/cog`, installs Bash completion under `$XDG_DATA_HOME/bash-completion/completions`, and
installs the man page under `$XDG_DATA_HOME/man/man1` when available.

It also copies shipped runtime content into:

- `$XDG_DATA_HOME/cog/skill-refs`
- `$HOME/.claude/skills`
- `$HOME/.claude/agents`
- `$HOME/.agents/skills`

Owned files are recorded in `$XDG_STATE_HOME/cog/install-manifest`.

## Smoke Check

```bash
cog doctor
cog --help
```

`cog doctor` checks required dependencies, XDG paths, the installed command, libraries, and eager
modules.

## Uninstall

```bash
./uninstall.sh
```

Uninstall removes only paths listed in `$XDG_STATE_HOME/cog/install-manifest` and prunes known
cog-owned directories with empty-only `rmdir`. User-authored files under the Claude and Codex
skill/agent roots are preserved.
