#!/usr/bin/env bash
set -euo pipefail
shopt -s inherit_errexit 2>/dev/null || true

resolve_repo_root() {
  local src="${BASH_SOURCE[0]}"
  local dir root

  while [[ -L $src ]]; do
    dir="$(cd -P "$(dirname "$src")" && pwd)"
    src="$(readlink "$src")"
    [[ $src != /* ]] && src="$dir/$src"
  done

  root="$(cd -P "$(dirname "$src")" && pwd)"
  printf '%s\n' "$root"
  return 0
}

record_path() {
  local path="$1"
  printf '%s\n' "$path" >>"$manifest_tmp"
  return 0
}

record_tree_files() {
  local src_dir="$1"
  local dest_dir="$2"
  local path rel

  while IFS= read -r path; do
    rel="${path#"$src_dir"/}"
    record_path "$dest_dir/$rel"
  done < <(find "$src_dir" \( -type f -o -type l \) -print)

  return 0
}

copy_tree() {
  local src_dir="$1"
  local dest_dir="$2"

  install -d "$dest_dir"
  cp -a "$src_dir/." "$dest_dir/"
  record_tree_files "$src_dir" "$dest_dir"
  return 0
}

install_man_page() {
  local src_scd="$repo_root/man/cog.1.scd"
  local src_man="$repo_root/man/cog.1"
  local built_man=""

  # Prefer a prebuilt man/cog.1 if the source tree already has one; otherwise
  # build into a temp file under the state dir. Never write into the source
  # checkout (it may be read-only and the artifact is not manifest-tracked).
  if [[ -e $src_man ]]; then
    built_man="$src_man"
  elif command -v scdoc >/dev/null 2>&1; then
    built_man="$(mktemp "$state_dir/.cog-man.XXXXXX")"
    man_tmp="$built_man"
    scdoc <"$src_scd" >"$built_man"
  else
    printf '%s\n' "warning: scdoc not found; skipping man page build" >&2
  fi

  if [[ -n $built_man ]]; then
    install -d "$man_dir"
    install -m 0644 "$built_man" "$man_dir/cog.1"
    record_path "$man_dir/cog.1"
  fi

  return 0
}

home="${HOME:?HOME must be set}"
prefix="${PREFIX:-$home/.local}"
xdg_data_home="${XDG_DATA_HOME:-$home/.local/share}"
xdg_state_home="${XDG_STATE_HOME:-$home/.local/state}"
repo_root="$(resolve_repo_root)"
app_root="$prefix/lib/cog"
bin_link="$prefix/bin/cog"
comp_dir="$xdg_data_home/bash-completion/completions"
man_dir="$xdg_data_home/man/man1"
state_dir="$xdg_state_home/cog"
manifest="$state_dir/install-manifest"

if [[ $EUID -eq 0 && -z ${PREFIX:-} ]]; then
  printf '%s\n' "refusing to install into root's home; set PREFIX for a system install" >&2
  exit 1
fi

install -d "$state_dir"
manifest_tmp="$(mktemp "$state_dir/.manifest.XXXXXX")"
man_tmp=""
trap 'rm -f "$manifest_tmp" "$manifest_tmp.sorted" "${man_tmp:-}"' EXIT

# Clear the cog-owned app payload before re-copying so a repeat install/upgrade
# does not leave stale files (e.g. a command module deleted upstream) that would
# stay dispatchable and escape the freshly built manifest. $app_root ($prefix/lib/cog)
# is exclusively cog-owned, so removing these known subtrees is safe; the
# user-home skill/agent roots are NOT cleared (they hold user-authored content)
# and remain on the overlay + manifest-only path.
install -d "$app_root"
rm -rf -- "$app_root/bin" "$app_root/lib" "$app_root/templates" "$app_root/VERSION"
copy_tree "$repo_root/bin" "$app_root/bin"
copy_tree "$repo_root/lib" "$app_root/lib"
copy_tree "$repo_root/templates" "$app_root/templates"
install -m 0644 "$repo_root/VERSION" "$app_root/VERSION"
record_path "$app_root/VERSION"

install -d "$(dirname "$bin_link")"
ln -sfn "$app_root/bin/cog" "$bin_link"
record_path "$bin_link"

copy_tree "$repo_root/skills/claude" "$home/.claude/skills"
copy_tree "$repo_root/agents/claude" "$home/.claude/agents"
copy_tree "$repo_root/skills/codex" "$home/.agents/skills"

install -d "$comp_dir"
install -m 0644 "$repo_root/completions/cog.bash" "$comp_dir/cog"
record_path "$comp_dir/cog"

install_man_page

sort -u "$manifest_tmp" >"$manifest_tmp.sorted"
mv -f "$manifest_tmp.sorted" "$manifest"
rm -f "$manifest_tmp"
trap - EXIT

printf 'installed cog to %s (PATH: %s)\n' "$app_root" "$bin_link"
exit 0
