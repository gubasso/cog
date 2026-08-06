# Install cog

This runbook installs, verifies, upgrades, or uninstalls cog. Exact destinations and manifest fields live in [install layout](../reference/install-layout.md).

## Start state

Run from the repository root with `bash`, `jq`, `git`, `find`, `sed`, and `mktemp` available. Queue helpers require `yq`; man-page generation can use `scdoc`.

Choose `PREFIX`, `XDG_DATA_HOME`, and `XDG_STATE_HOME` before installation. Defaults are `$HOME/.local`, `$HOME/.local/share`, and `$HOME/.local/state`.

## Install

1. Inspect the target locations with `printf '%s\n' "${PREFIX:-$HOME/.local}" "${XDG_DATA_HOME:-$HOME/.local/share}" "${XDG_STATE_HOME:-$HOME/.local/state}"`.
2. Run `./install.sh`, optionally with the three location variables set.
3. Verify with `cog --version`, `cog doctor`, and `cog --help`.
4. Inspect `$XDG_STATE_HOME/cog/install-manifest` when confirming ownership.

The installer copies the app, data, skill references, runtime skills, agents, completion, and the available man page. Logs normally go to `$XDG_STATE_HOME/cog/cog.log`.

## Upgrade

Run the same install command. Stop if preflight fails or if the reported prefix differs from the intended location. The installer refreshes owned files and preserves user-authored runtime skill and agent files.

## Uninstall

Uninstall is destructive for manifest-owned files.

1. Inspect first: `sed -n '1,240p' "$XDG_STATE_HOME/cog/install-manifest"`.
2. Confirm every listed path is inside the intended prefix, data, state, or runtime-skill roots.
3. At the confirmation point, run `./uninstall.sh`.
4. Verify that `$PREFIX/bin/cog` and the manifest are absent and that user-authored skill or agent files remain.

Stop before step 3 if the manifest is missing, names an unexpected root, or includes a user-authored path. Reinstall to reconstruct an owned payload; restore user-authored files from their own backup if they were removed outside this workflow.
