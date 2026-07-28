# ADR-0003: Multi-target install

## Context and Problem Statement

`cog` installs more than one kind of artifact: the CLI app root, a PATH symlink, Bash completion, an optional man page, Claude skills, Claude agents, and Codex skills. GNU Stow is a good fit for dotfile packages, but this project needs ownership tracking and uninstall safety across several user targets.

## Considered Options

- Keep using GNU Stow packages.
- Copy files with no manifest and rely on manual cleanup.
- Use `install.sh` plus an install manifest.

## Decision Outcome

Chosen option: **manifest-based installer**. `install.sh` copies the app payload to `$PREFIX/lib/cog`, creates `$PREFIX/bin/cog`, installs completion and man artifacts under `$XDG_DATA_HOME`, copies skills and agents into their runtime trees, and records owned files in `$XDG_STATE_HOME/cog/install-manifest`.

## Consequences

- Good: `uninstall.sh` can remove only manifest-listed files.
- Good: user-authored files under skill and agent roots are preserved.
- Good: repeated installs refresh the cog-owned app payload and avoid stale command modules.
- Bad: installer scripts must maintain manifest coverage for every new installed artifact.
- Bad: users must rerun uninstall with matching `PREFIX` and XDG paths for safe cleanup.

## Status

Implemented.
