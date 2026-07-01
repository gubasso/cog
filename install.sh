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

# Make dest_dir an exact mirror of src_dir: anything in dest not shipped by the
# current source tree is deleted. Prefers rsync --delete; falls back to a
# wipe-then-recopy when rsync is unavailable. Both yield an identical mirror.
mirror_tree() {
  local src_dir="$1"
  local dest_dir="$2"

  install -d "$dest_dir"
  if command -v rsync >/dev/null 2>&1; then
    rsync -a --delete "$src_dir/" "$dest_dir/"
  else
    rm -rf -- "${dest_dir:?}"
    install -d "$dest_dir"
    cp -a "$src_dir/." "$dest_dir/"
  fi
  record_tree_files "$src_dir" "$dest_dir"
  return 0
}

# Dispatch the skill/agent roots through a destructive mirror when mirror mode is
# on (COG_INSTALL_MIRROR=1), otherwise the default non-destructive overlay copy.
sync_tree() {
  if [[ $mirror == 1 ]]; then
    mirror_tree "$@"
  else
    copy_tree "$@"
  fi
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
mirror="${COG_INSTALL_MIRROR:-0}"
app_root="$prefix/lib/cog"
bin_link="$prefix/bin/cog"
data_dir="$xdg_data_home/cog"
comp_dir="$xdg_data_home/bash-completion/completions"
man_dir="$xdg_data_home/man/man1"
state_dir="$xdg_state_home/cog"
manifest="$state_dir/install-manifest"
_self_dir="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=install-common.sh
. "$_self_dir/install-common.sh"

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
# is exclusively cog-owned, so removing these known subtrees is safe. By default
# the user-home skill/agent roots are NOT cleared (they hold user-authored
# content) and remain on the overlay + manifest-only path; in mirror mode
# (COG_INSTALL_MIRROR=1) sync_tree mirrors them destructively instead.
install -d "$app_root"
rm -rf -- "${app_root:?}/bin" "${app_root:?}/lib" "${app_root:?}/VERSION"
rm -rf -- "${data_dir:?}/skill-refs"
rm -rf -- "${data_dir:?}/data/power-grade" "${data_dir:?}/data/model-effort" "${data_dir:?}/data/skill-class" "${data_dir:?}/data/maintenance-tracking.yaml"
copy_tree "$repo_root/bin" "$app_root/bin"
copy_tree "$repo_root/lib" "$app_root/lib"
copy_tree "$repo_root/skill-refs" "$data_dir/skill-refs"
copy_tree "$repo_root/data/power-grade" "$data_dir/data/power-grade"
copy_tree "$repo_root/data/model-effort" "$data_dir/data/model-effort"
copy_tree "$repo_root/data/skill-class" "$data_dir/data/skill-class"
install -d "$data_dir/data"
install -m 0644 "$repo_root/data/maintenance-tracking.yaml" "$data_dir/data/maintenance-tracking.yaml"
record_path "$data_dir/data/maintenance-tracking.yaml"
install -d "$data_dir/data/research-shelf"
if [[ ! -e $data_dir/data/research-shelf/index.jsonl ]]; then
  install -m 0644 "$repo_root/data/research-shelf/index.jsonl" "$data_dir/data/research-shelf/index.jsonl"
fi
record_path "$data_dir/data/research-shelf/index.jsonl"
install -m 0644 "$repo_root/VERSION" "$app_root/VERSION"
record_path "$app_root/VERSION"

install -d "$(dirname "$bin_link")"
ln -sfn "$app_root/bin/cog" "$bin_link"
record_path "$bin_link"

sync_tree "$repo_root/skills/claude" "$home/.claude/skills"
sync_tree "$repo_root/agents/claude" "$home/.claude/agents"
sync_tree "$repo_root/skills/codex" "$home/.agents/skills"

install -d "$comp_dir"
install -m 0644 "$repo_root/completions/cog.bash" "$comp_dir/cog"
record_path "$comp_dir/cog"

install_man_page

sort -u "$manifest_tmp" >"$manifest_tmp.sorted"

# Stale-prune: remove cog-owned files the previous install shipped that this
# install no longer ships (e.g. a renamed/removed skill directory). User-authored
# files are never recorded in a manifest, so they are never pruned. First-ever
# install has no prior manifest and prunes nothing. App-payload entries already
# removed by the hard-clear above make their `rm -f` a harmless no-op.
if [[ -e $manifest ]]; then
  while IFS= read -r stale; do
    valid_manifest_path "$stale" || continue
    rm -f -- "$stale"
    prune_manifest_skill_dir "$stale" "$home/.claude/skills"
    prune_manifest_skill_dir "$stale" "$home/.claude/agents"
    prune_manifest_skill_dir "$stale" "$home/.agents/skills"
  done < <(comm -23 <(sort -u "$manifest") "$manifest_tmp.sorted")
fi

mv -f "$manifest_tmp.sorted" "$manifest"
rm -f "$manifest_tmp"
trap - EXIT

printf 'installed cog to %s (PATH: %s)\n' "$app_root" "$bin_link"
exit 0
