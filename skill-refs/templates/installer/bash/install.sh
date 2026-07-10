#!/usr/bin/env bash
set -eEuo pipefail
shopt -s inherit_errexit 2>/dev/null || true

# Manifest-driven installer for a Bash CLI project.
#
# It copies a project-owned payload into an XDG/PREFIX destination, links the
# executable onto PATH, records every installed path in a manifest, and
# stale-prunes files a previous install shipped but this one no longer does.
# uninstall.sh reverses it from the same manifest.
#
# Environment:
#   PREFIX            install prefix           (default: $HOME/.local)
#   XDG_DATA_HOME     data root                (default: $HOME/.local/share)
#   XDG_STATE_HOME    state/manifest root      (default: $HOME/.local/state)
#   INSTALLER_QUIET=1 suppress progress output
#   INSTALLER_VERBOSE=1 print per-file detail
#   NO_COLOR          disable color

case "${BASH_SOURCE[0]}" in
  */*) _self_dir="$(cd -P "${BASH_SOURCE[0]%/*}" && pwd)" ;;
  *) _self_dir="$(pwd)" ;;
esac
# shellcheck source=/dev/null
. "$_self_dir/install-common.sh"
installer_ui_init
installer_require_home

# ============================================================================
# PROJECT CONFIGURATION — edit this block for your project.
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

# Source subtree -> destination directory (copied recursively).
copy_trees=(
  "bin|$app_root/bin"
  "lib|$app_root/lib"
)
# Source file -> destination path -> mode (copied individually).
copy_files=(
  "VERSION|$app_root/VERSION|0644"
)
# Executable symlink: link target -> link path.
bin_links=(
  "$app_root/bin/$project_name|$bin_dir/$project_name"
)
# Cog-owned trees cleared before re-copy so a repeat install drops stale files.
owned_clear=(
  "$app_root/bin"
  "$app_root/lib"
  "$app_root/VERSION"
)
# Roots any manifest path must fall under (uninstall safety allowlist).
manifest_roots=(
  "$app_root"
  "$data_dir"
  "$bin_dir"
  "$state_dir"
)
required_tools=(install find sort comm mktemp ln cp rm mv dirname readlink)
optional_tools=()
# ============================================================================
# END PROJECT CONFIGURATION — reusable machinery follows.
# ============================================================================

manifest_tmp=""

valid_manifest_path() {
  local path="$1" root
  [[ -n $path && $path == /* && $path != / ]] || return 1
  for root in "${manifest_roots[@]}"; do
    path_under "$path" "$root" && return 0
  done
  return 1
}

record_path() {
  printf '%s\n' "$1" >>"$manifest_tmp"
  return 0
}

record_tree_files() {
  local src_dir="$1" dest_dir="$2" path rel
  while IFS= read -r path; do
    rel="${path#"$src_dir"/}"
    record_path "$dest_dir/$rel"
  done < <(find "$src_dir" \( -type f -o -type l \) -print)
  return 0
}

copy_tree() {
  local src_dir="$1" dest_dir="$2"
  installer_detail "copy $src_dir -> $dest_dir"
  install -d "$dest_dir"
  cp -a "$src_dir/." "$dest_dir/"
  record_tree_files "$src_dir" "$dest_dir"
  return 0
}

require_source_path() {
  [[ -e $1 ]] || installer_die "missing source path $1; run install.sh from a complete project checkout"
}

# shellcheck disable=SC2329 # Invoked by EXIT/INT/TERM traps after temp state is created.
install_cleanup() { rm -f "${manifest_tmp:-}" "${manifest_tmp:-}.sorted"; }
# shellcheck disable=SC2329 # Invoked by the INT trap after temp state is created.
install_on_int() {
  install_cleanup
  exit 130
}
# shellcheck disable=SC2329 # Invoked by the TERM trap after temp state is created.
install_on_term() {
  install_cleanup
  exit 143
}

if [[ $EUID -eq 0 && -z ${PREFIX:-} ]]; then
  installer_die "refusing to install into root's home; set PREFIX for a system install, for example PREFIX=/usr/local ./install.sh"
fi

trap 'installer_err_trap "$?" "$LINENO" "$BASH_COMMAND"' ERR

installer_set_step "preflight" "Install requires a writable PREFIX/XDG destination and core POSIX tools."
installer_step "Preflight"
for required in "${required_tools[@]}"; do
  installer_require_command "$required" "required" "install shell/coreutils operations"
done
for optional in "${optional_tools[@]}"; do
  installer_require_command "$optional" "optional" "an optional install step is skipped without it"
done

repo_root="$_self_dir"
entry=""
for entry in "${copy_trees[@]}"; do require_source_path "$repo_root/${entry%%|*}"; done
for entry in "${copy_files[@]}"; do require_source_path "$repo_root/${entry%%|*}"; done

installer_require_writable_dir "$state_dir" "state directory"
installer_require_writable_dir "$app_root" "application root"
installer_require_writable_dir "$bin_dir" "binary directory"

installer_detail "project: $project_name"
installer_detail "prefix: $prefix"
installer_detail "app root: $app_root"
installer_detail "manifest: $manifest"
installer_ok "Preflight"

installer_set_step "prepare manifest" "Check write permissions under $state_dir and available disk space."
installer_step "Prepare manifest"
manifest_tmp="$(mktemp "$state_dir/.manifest.XXXXXX")" || exit 1
trap 'install_cleanup' EXIT
trap 'install_on_int' INT
trap 'install_on_term' TERM
installer_ok "Prepare manifest"

installer_set_step "prepare destination" "Check write permissions under $app_root."
installer_step "Prepare destination"
install -d "$app_root"
for path in "${owned_clear[@]}"; do rm -rf -- "${path:?}"; done
installer_ok "Prepare destination"

installer_set_step "copy payload" "Check write permissions under $app_root and $data_dir."
installer_step "Copy payload"
for entry in "${copy_trees[@]}"; do
  copy_tree "$repo_root/${entry%%|*}" "${entry#*|}"
done
for entry in "${copy_files[@]}"; do
  src="${entry%%|*}"
  rest="${entry#*|}"
  dst="${rest%%|*}"
  mode="${rest##*|}"
  installer_detail "install $repo_root/$src -> $dst"
  install -D -m "$mode" "$repo_root/$src" "$dst"
  record_path "$dst"
done
installer_ok "Copy payload"

installer_set_step "link executables" "Check write permissions under $bin_dir."
installer_step "Link executables"
for entry in "${bin_links[@]}"; do
  target="${entry%%|*}"
  link="${entry#*|}"
  installer_require_parent_writable "$link" "binary link"
  ln -sfn "$target" "$link"
  record_path "$link"
  installer_detail "link $link -> $target"
done
installer_ok "Link executables"

installer_set_step "prune stale manifest entries" "Check write permissions under installed paths and verify the existing manifest at $manifest."
installer_step "Prune stale manifest entries"
sort -u "$manifest_tmp" >"$manifest_tmp.sorted"
if [[ -e $manifest ]]; then
  while IFS= read -r stale; do
    valid_manifest_path "$stale" || continue
    rm -f -- "$stale"
  done < <(comm -23 <(sort -u "$manifest") "$manifest_tmp.sorted")
fi
installer_ok "Prune stale manifest entries"

installer_set_step "finalize manifest" "Check write permissions under $state_dir and available disk space."
installer_step "Finalize manifest"
mv -f "$manifest_tmp.sorted" "$manifest"
rm -f "$manifest_tmp"
manifest_tmp=""
trap - EXIT
trap - INT
trap - TERM
installer_ok "Finalize manifest"

# shellcheck disable=SC2154 # installer_quiet is assigned in the sourced install-common.sh
if ((installer_quiet != 1)); then
  installer_note "Installed:"
  installer_note "    app: $app_root"
  installer_note "    manifest: $manifest"
  for entry in "${bin_links[@]}"; do installer_note "    binary: ${entry#*|}"; done
  installer_note "    PATH: ensure $bin_dir is on PATH"
fi

printf 'installed %s to %s\n' "$project_name" "$app_root"
exit 0
