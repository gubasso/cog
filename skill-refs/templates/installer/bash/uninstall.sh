#!/usr/bin/env bash
set -eEuo pipefail
shopt -s inherit_errexit 2>/dev/null || true

# Manifest-driven uninstaller. Removes exactly the paths install.sh recorded,
# refusing to touch anything outside the project's install roots. Run it with
# the same PREFIX / XDG environment used at install time.

case "${BASH_SOURCE[0]}" in
  */*) _self_dir="$(cd -P "${BASH_SOURCE[0]%/*}" && pwd)" ;;
  *) _self_dir="$(pwd)" ;;
esac
# shellcheck source=/dev/null
. "$_self_dir/install-common.sh"
installer_ui_init
installer_require_home

# ============================================================================
# PROJECT CONFIGURATION — keep in sync with install.sh.
# ============================================================================
project_name="myproject"

home="$HOME"
prefix="${PREFIX:-$home/.local}"
xdg_data_home="${XDG_DATA_HOME:-$home/.local/share}"
xdg_state_home="${XDG_STATE_HOME:-$home/.local/state}"

app_root="$prefix/lib/$project_name"
bin_dir="$prefix/bin"
data_dir="$xdg_data_home/$project_name"
state_dir="$xdg_state_home/$project_name"
manifest="$state_dir/install-manifest"

manifest_roots=(
  "$app_root"
  "$data_dir"
  "$bin_dir"
  "$state_dir"
)
# Trees pruned of empty directories after files are removed.
prune_roots=(
  "$app_root"
  "$data_dir"
)
required_tools=(rm rmdir find dirname sort)
# ============================================================================
# END PROJECT CONFIGURATION — reusable machinery follows.
# ============================================================================

valid_manifest_path() {
  local path="$1" root
  [[ -n $path && $path == /* && $path != / ]] || return 1
  for root in "${manifest_roots[@]}"; do
    path_under "$path" "$root" && return 0
  done
  return 1
}

trap 'installer_err_trap "$?" "$LINENO" "$BASH_COMMAND"' ERR

installer_set_step "preflight" "Uninstall requires the install manifest and writable recorded paths."
installer_step "Preflight"
for required in "${required_tools[@]}"; do
  installer_require_command "$required" "required" "uninstall shell/coreutils operations"
done
installer_detail "project: $project_name"
installer_detail "manifest: $manifest"

if [[ ! -e $manifest ]]; then
  installer_warn "nothing to uninstall; no install manifest at $manifest (state dir: $state_dir)"
  exit 0
fi
if [[ ! -r $manifest ]]; then
  installer_die "install manifest is not readable at $manifest; fix permissions or run as the user that installed $project_name"
fi
installer_ok "Preflight"

installer_set_step "remove manifest files" "Check permissions on manifest-listed files and rerun with the same PREFIX/XDG roots used at install time."
installer_step "Remove manifest files"
skipped=0
removed_existing=0
total_entries=0
while IFS= read -r path; do
  total_entries=$((total_entries + 1))
  if valid_manifest_path "$path"; then
    if [[ -e $path || -L $path ]]; then
      removed_existing=$((removed_existing + 1))
    fi
    rm -f -- "$path"
  else
    installer_warn "skipping unsafe manifest path outside the current PREFIX/XDG roots: $path"
    skipped=$((skipped + 1))
  fi
done <"$manifest"
installer_ok "Remove manifest files"

installer_set_step "verify manifest authority" "Re-run uninstall with the same PREFIX, XDG_DATA_HOME, and XDG_STATE_HOME used at install time."
installer_step "Verify manifest authority"
# A skipped entry means a manifest path falls under no allowed root computed from
# the current PREFIX/XDG environment — the install used a different PREFIX/XDG.
# Removing the manifest now would orphan those files, so fail closed and keep it.
if ((skipped > 0)); then
  installer_die "${skipped} manifest path(s) fall outside the current install roots; refusing to remove the manifest. Current roots: PREFIX=$prefix XDG_DATA_HOME=$xdg_data_home XDG_STATE_HOME=$xdg_state_home. Re-run uninstall with the same environment used at install time."
fi
installer_ok "Verify manifest authority"

installer_set_step "prune empty directories" "Check permissions under the project install roots."
installer_step "Prune empty directories"
for root in "${prune_roots[@]}"; do prune_empty_tree "$root"; done
rmdir_empty "$app_root"
rmdir_empty "$data_dir"
installer_ok "Prune empty directories"

installer_set_step "remove manifest" "Check write permissions under $state_dir."
installer_step "Remove manifest"
rm -f -- "$manifest"
rmdir_empty "$state_dir"
installer_ok "Remove manifest"

# shellcheck disable=SC2154 # installer_quiet is assigned in the sourced install-common.sh
if ((installer_quiet != 1)); then
  installer_note "Uninstalled:"
  installer_note "    manifest entries: $total_entries"
  installer_note "    removed existing paths: $removed_existing"
  installer_note "    skipped unsafe paths: $skipped"
fi

printf 'uninstalled %s\n' "$project_name"
exit 0
