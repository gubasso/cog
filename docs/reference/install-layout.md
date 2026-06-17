# Install layout

## Defaults

`install.sh` uses these defaults:

| Variable | Default |
| -------- | ------- |
| `PREFIX` | `$HOME/.local` |
| `XDG_DATA_HOME` | `$HOME/.local/share` |
| `XDG_STATE_HOME` | `$HOME/.local/state` |

`HOME` is required.

## App payload

| Path | Purpose |
| ---- | ------- |
| `$PREFIX/lib/cog/bin` | Installed executable shim. |
| `$PREFIX/lib/cog/lib` | Installed command modules and shared functions. |
| `$PREFIX/lib/cog/templates` | Installed templates. |
| `$PREFIX/lib/cog/VERSION` | Installed version file. |
| `$PREFIX/bin/cog` | PATH symlink to `$PREFIX/lib/cog/bin/cog`. |

The app root is cog-owned. Reinstalling clears and recopies its known payload subtrees so stale
command modules do not remain dispatchable.

## Data and state

| Path | Purpose |
| ---- | ------- |
| `$XDG_DATA_HOME/bash-completion/completions/cog` | Bash completion file. |
| `$XDG_DATA_HOME/man/man1/cog.1` | Installed man page when available. |
| `$XDG_STATE_HOME/cog/install-manifest` | Newline-delimited absolute paths owned by the installer. |

## Skill and agent overlays

| Path | Purpose |
| ---- | ------- |
| `$HOME/.claude/skills` | Installed Claude skills copied from `skills/claude`. |
| `$HOME/.claude/agents` | Installed Claude agents copied from `agents/claude`. |
| `$HOME/.agents/skills` | Installed Codex skills copied from `skills/codex`. |

These roots may contain user-authored content. `uninstall.sh` removes only manifest-listed files and
prunes empty directories.
