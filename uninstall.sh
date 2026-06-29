#!/usr/bin/env bash
set -euo pipefail
shopt -s inherit_errexit 2>/dev/null || true

home="${HOME:?HOME must be set}"
prefix="${PREFIX:-$home/.local}"
xdg_data_home="${XDG_DATA_HOME:-$home/.local/share}"
xdg_state_home="${XDG_STATE_HOME:-$home/.local/state}"
app_root="$prefix/lib/cog"
data_dir="$xdg_data_home/cog"
comp_dir="$xdg_data_home/bash-completion/completions"
man_dir="$xdg_data_home/man/man1"
state_dir="$xdg_state_home/cog"
manifest="$state_dir/install-manifest"
_self_dir="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=install-common.sh
. "$_self_dir/install-common.sh"

if [[ ! -e $manifest ]]; then
  printf '%s\n' "no install manifest found; nothing to uninstall" >&2
  exit 0
fi

skipped=0
while IFS= read -r path; do
  if valid_manifest_path "$path"; then
    rm -f -- "$path"
  else
    printf 'warning: skipping unsafe manifest path: %s\n' "$path" >&2
    skipped=$((skipped + 1))
  fi
done <"$manifest"

# A skipped entry means a manifest path does not fall under any allowed root
# computed from the current PREFIX/XDG environment. This happens when the
# install used a different PREFIX/XDG than this uninstall (the manifest always
# lives at the default $XDG_STATE_HOME/cog/install-manifest). Removing the
# manifest now would orphan those installed files with no authority to clean
# them up later, so fail closed and keep the manifest intact.
if ((skipped > 0)); then
  printf '%s\n' "error: ${skipped} manifest path(s) fall outside the current PREFIX/XDG roots; refusing to remove the manifest. Re-run uninstall with the same PREFIX/XDG_DATA_HOME/XDG_STATE_HOME used at install time." >&2
  exit 1
fi

while IFS= read -r path; do
  valid_manifest_path "$path" || continue
  prune_manifest_skill_dir "$path" "$home/.claude/skills"
  prune_manifest_skill_dir "$path" "$home/.claude/agents"
  prune_manifest_skill_dir "$path" "$home/.agents/skills"
done <"$manifest"

prune_empty_tree "$data_dir/skill-refs"
prune_empty_tree "$data_dir/data"
rmdir_empty "$data_dir"
rmdir_empty "$app_root/lib/commands"
rmdir_empty "$app_root/lib/functions"
rmdir_empty "$app_root/lib"
rmdir_empty "$app_root/bin"
rmdir_empty "$app_root"
rmdir_empty "$man_dir"
rmdir_empty "$comp_dir"

rm -f -- "$manifest"
rmdir_empty "$state_dir"

printf '%s\n' "uninstalled cog"
exit 0
