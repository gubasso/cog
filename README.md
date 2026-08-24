# cog

`cog` is a deterministic Bash helper CLI for agent-oriented development workflows. It replaces the old dotfiles-local helper script with a standalone command, library, installer, documentation, and test surface.

The CLI installs as a self-contained app root. The payload includes:

- `bin/cog`, `lib/`, `templates/`, and `VERSION`
- Bash completion and an optional man page
- Claude skills under `skills/claude/`
- Claude agents under `agents/claude/`
- Codex skills under `skills/codex/`

## Quick Start

```bash
./install.sh
cog doctor
cog --help
```

By default, `install.sh` uses `PREFIX="$HOME/.local"`, writes the app root under `$PREFIX/lib/cog`, and creates the PATH symlink at `$PREFIX/bin/cog`.

## Development

```bash
just lint
just test
just man
```

Quality gates are owned by pre-commit. `just lint` runs `pre-commit run --all-files`; `just test` runs the unit and integration pre-commit hooks. `just man` builds `man/cog.1` from `man/cog.1.scd` when `scdoc` is available.

## Documentation

- [Documentation index](docs/README.md)
- [Architecture overview](docs/explanation/architecture.md)
- [CLI command reference](docs/reference/cli-commands.md)
- [Write a cog plugin](docs/guides/write-a-plugin.md)
- [Decision records](docs/decisions/)
