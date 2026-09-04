# Install layout

## Defaults

`install.sh` uses these defaults:

| Variable         | Default              |
| ---------------- | -------------------- |
| `PREFIX`         | `$HOME/.local`       |
| `XDG_DATA_HOME`  | `$HOME/.local/share` |
| `XDG_STATE_HOME` | `$HOME/.local/state` |

`HOME` is required.

## App payload

| Path                        | Purpose                                         |
| --------------------------- | ----------------------------------------------- |
| `$PREFIX/lib/cog/bin`       | Installed executable shim.                      |
| `$PREFIX/lib/cog/lib`       | Installed command modules and shared functions. |
| `$PREFIX/lib/cog/templates` | Installed templates.                            |
| `$PREFIX/lib/cog/VERSION`   | Installed version file.                         |
| `$PREFIX/bin/cog`           | PATH symlink to `$PREFIX/lib/cog/bin/cog`.      |

The app root is cog-owned. Reinstalling clears and recopies its known payload subtrees so stale command modules do not remain dispatchable.

## Data and state

| Path                                             | Purpose                                                       |
| ------------------------------------------------ | ------------------------------------------------------------- |
| `$XDG_DATA_HOME/cog/data`                        | Installed CLI-consumed structured reference data.             |
| `$XDG_DATA_HOME/cog/skill-refs`                  | Installed skill-loaded reference corpus and deploy templates. |
| `$XDG_DATA_HOME/bash-completion/completions/cog` | Bash completion file.                                         |
| `$XDG_DATA_HOME/man/man1/cog.1`                  | Installed man page when available.                            |
| `$XDG_STATE_HOME/cog/install-manifest`           | Newline-delimited absolute paths owned by the installer.      |

Read-only data subtrees are refreshed on install. The append-only research shelf index under `$XDG_DATA_HOME/cog/data/research-shelf/index.jsonl` is copied only when absent so installed-mode records survive upgrades.

## Skill and agent overlays

| Path                   | Purpose                                                                                |
| ---------------------- | -------------------------------------------------------------------------------------- |
| `$HOME/.claude/skills` | Portable packages from `skills/`, plus Claude-native ones from `skills-native/claude`. |
| `$HOME/.claude/agents` | Installed Claude agents copied from `agents/claude`.                                   |
| `$HOME/.agents/skills` | Portable packages from `skills/`, plus Codex-native ones from `skills-native/codex`.   |

A portable package is copied per package into both skill roots, and the two copies are the same bytes. A native package reaches only its own root. The installer refuses to run when one name exists in both source classes.

These roots may contain user-authored content. `uninstall.sh` removes only manifest-listed files and prunes empty directories.
