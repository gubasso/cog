#!/usr/bin/env bash
set -eEuo pipefail
shopt -s inherit_errexit 2>/dev/null || true

case "${BASH_SOURCE[0]}" in
  */*) _self_dir="$(cd -P "${BASH_SOURCE[0]%/*}" && pwd)" ;;
  *) _self_dir="$(pwd)" ;;
esac
# shellcheck source=install-common.sh
. "$_self_dir/install-common.sh"
cog_install_ui_init
cog_install_require_home

home="$HOME"
prefix="${PREFIX:-$home/.local}"
xdg_data_home="${XDG_DATA_HOME:-$home/.local/share}"
xdg_state_home="${XDG_STATE_HOME:-$home/.local/state}"
app_root="$prefix/lib/cog"
data_dir="$xdg_data_home/cog"
comp_dir="$xdg_data_home/bash-completion/completions"
man_dir="$xdg_data_home/man/man1"
state_dir="$xdg_state_home/cog"
manifest="$state_dir/install-manifest"

trap 'cog_install_err_trap "$?" "$LINENO" "$BASH_COMMAND"' ERR

cog_install_set_step "preflight" "Uninstall requires the install manifest and writable recorded paths."
cog_install_step "Preflight"
for required in rm rmdir find dirname; do
  cog_install_require_command "$required" "required" "uninstall shell/coreutils operations"
done

cog_install_detail "prefix: $prefix"
cog_install_detail "data: $xdg_data_home"
cog_install_detail "state: $xdg_state_home"
cog_install_detail "app root: $app_root"
cog_install_detail "completion dir: $comp_dir"
cog_install_detail "man dir: $man_dir"
cog_install_detail "manifest: $manifest"

if [[ ! -e $manifest ]]; then
  cog_install_warn "nothing to uninstall; no install manifest at $manifest (state dir: $state_dir)"
  exit 0
fi

if [[ ! -r $manifest ]]; then
  cog_install_die "install manifest is not readable at $manifest; fix permissions or run with the same user that installed cog"
fi
cog_install_ok "Preflight"

cog_install_set_step "read manifest" "Check that $manifest is readable and not being modified during uninstall."
cog_install_step "Read manifest"
total_entries=0
while IFS= read -r path; do
  total_entries=$((total_entries + 1))
done <"$manifest"
cog_install_ok "Read manifest"

cog_install_set_step "remove manifest files" "Check permissions on manifest-listed files and rerun with the same PREFIX/XDG roots used at install time."
cog_install_step "Remove manifest files"
skipped=0
removed_existing=0
while IFS= read -r path; do
  if valid_manifest_path "$path"; then
    if [[ -e $path || -L $path ]]; then
      removed_existing=$((removed_existing + 1))
    fi
    rm -f -- "$path"
  else
    cog_install_warn "skipping unsafe manifest path outside the current PREFIX/XDG roots: $path"
    skipped=$((skipped + 1))
  fi
done <"$manifest"
cog_install_ok "Remove manifest files"

cog_install_set_step "verify manifest authority" "Re-run uninstall with the same PREFIX, XDG_DATA_HOME, and XDG_STATE_HOME used at install time."
cog_install_step "Verify manifest authority"
# A skipped entry means a manifest path does not fall under any allowed root
# computed from the current PREFIX/XDG environment. This happens when the
# install used a different PREFIX/XDG than this uninstall (the manifest always
# lives at the default $XDG_STATE_HOME/cog/install-manifest). Removing the
# manifest now would orphan those installed files with no authority to clean
# them up later, so fail closed and keep the manifest intact.
if ((skipped > 0)); then
  cog_install_die "${skipped} manifest path(s) fall outside the current PREFIX/XDG roots; refusing to remove the manifest. Current roots: PREFIX=$prefix XDG_DATA_HOME=$xdg_data_home XDG_STATE_HOME=$xdg_state_home. Re-run uninstall with the same PREFIX, XDG_DATA_HOME, and XDG_STATE_HOME used at install time."
fi
cog_install_ok "Verify manifest authority"

cog_install_set_step "prune empty skill directories" "Check permissions under $home/.claude and $home/.agents."
cog_install_step "Prune empty skill directories"
while IFS= read -r path; do
  valid_manifest_path "$path" || continue
  prune_manifest_skill_dir "$path" "$home/.claude/skills"
  prune_manifest_skill_dir "$path" "$home/.claude/agents"
  prune_manifest_skill_dir "$path" "$home/.agents/skills"
done <"$manifest"
cog_install_ok "Prune empty skill directories"

cog_install_set_step "prune empty cog trees" "Check permissions under $data_dir, $app_root, $comp_dir, and $man_dir."
cog_install_step "Prune empty cog trees"
prune_empty_tree "$data_dir/skill-refs"
prune_empty_tree "$data_dir/data"
# Retired destination, still pruned so uninstalling an installation made before
# the workflow layer was removed leaves no empty tree behind.
prune_empty_tree "$data_dir/workflow"
rmdir_empty "$data_dir"
rmdir_empty "$app_root/lib/commands"
rmdir_empty "$app_root/lib/functions"
rmdir_empty "$app_root/lib"
rmdir_empty "$app_root/bin"
rmdir_empty "$app_root"
rmdir_empty "$man_dir"
rmdir_empty "$comp_dir"
cog_install_ok "Prune empty cog trees"

cog_install_set_step "remove manifest" "Check write permissions under $state_dir."
cog_install_step "Remove manifest"
rm -f -- "$manifest"
rmdir_empty "$state_dir"
cog_install_ok "Remove manifest"

if ((cog_install_quiet != 1)); then
  cog_install_note "Uninstalled:"
  cog_install_note "    manifest entries: $total_entries"
  cog_install_note "    removed existing paths: $removed_existing"
  cog_install_note "    skipped unsafe paths: $skipped"
  cog_install_note "    pruned roots: $home/.claude/skills, $home/.claude/agents, $home/.agents/skills, $data_dir, $app_root"
fi

printf '%s\n' "uninstalled cog"
exit 0
