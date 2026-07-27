#!/usr/bin/env bash
set -eEuo pipefail
shopt -s inherit_errexit 2>/dev/null || true

resolve_repo_root() {
  local src="${BASH_SOURCE[0]}"
  local dir root

  while [[ -L $src ]]; do
    dir="$(cd -P "${src%/*}" && pwd)"
    src="$(readlink "$src")"
    [[ $src != /* ]] && src="$dir/$src"
  done

  root="$(cd -P "${src%/*}" && pwd)"
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

  cog_install_detail "copy $src_dir -> $dest_dir"
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

  cog_install_detail "mirror $src_dir -> $dest_dir"
  install -d "$dest_dir"
  if command -v rsync >/dev/null 2>&1; then
    rsync -a --delete "$src_dir/" "$dest_dir/"
  else
    cog_install_warn "rsync not found; mirror mode is using wipe-then-copy fallback for $dest_dir"
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
    cog_install_detail "use prebuilt man page $src_man"
    built_man="$src_man"
  elif command -v scdoc >/dev/null 2>&1; then
    cog_install_detail "build man page from $src_scd"
    built_man="$(mktemp "$state_dir/.cog-man.XXXXXX")"
    man_tmp="$built_man"
    scdoc <"$src_scd" >"$built_man"
  else
    cog_install_warn "scdoc not found and no prebuilt man/cog.1 exists; skipping man page build"
  fi

  if [[ -n $built_man ]]; then
    cog_install_detail "install man page -> $man_dir/cog.1"
    install -d "$man_dir"
    install -m 0644 "$built_man" "$man_dir/cog.1"
    record_path "$man_dir/cog.1"
    man_page_status="$man_dir/cog.1"
  else
    man_page_status="skipped"
  fi

  return 0
}

# shellcheck disable=SC2329 # Invoked by EXIT/INT/TERM traps after temp state is created.
install_cleanup() {
  rm -f "${manifest_tmp:-}" "${manifest_tmp:-}.sorted" "${man_tmp:-}"
}

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

require_source_path() {
  local path="$1"

  if [[ ! -e $path ]]; then
    cog_install_die "missing source path $path; run from a complete cog checkout"
  fi
}

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
mirror="${COG_INSTALL_MIRROR:-0}"
app_root="$prefix/lib/cog"
bin_link="$prefix/bin/cog"
data_dir="$xdg_data_home/cog"
comp_dir="$xdg_data_home/bash-completion/completions"
man_dir="$xdg_data_home/man/man1"
state_dir="$xdg_state_home/cog"
manifest="$state_dir/install-manifest"
manifest_tmp=""
man_tmp=""
man_page_status="skipped"

if [[ $EUID -eq 0 && -z ${PREFIX:-} ]]; then
  cog_install_die "refusing to install into root's home; set PREFIX for a system install, for example PREFIX=/usr/local ./install.sh"
fi

if [[ $mirror == 1 && ${COG_INSTALL_CONFIRM:-0} == 1 ]]; then
  cog_install_confirm_mirror
fi

trap 'cog_install_err_trap "$?" "$LINENO" "$BASH_COMMAND"' ERR

cog_install_set_step "preflight" "Install requires a writable PREFIX/XDG destination and core POSIX tools."
cog_install_step "Preflight"
for required in install find sort comm mktemp ln cp rm mv dirname readlink; do
  cog_install_require_command "$required" "required" "install shell/coreutils operations"
done
cog_install_require_command "rsync" "optional" "mirror mode will fall back to wipe-then-copy"
cog_install_require_command "scdoc" "optional" "the man page is skipped unless a prebuilt man/cog.1 exists"
if command -v scdoc >/dev/null 2>&1; then
  scdoc_available=1
else
  scdoc_available=0
fi

repo_root="$(resolve_repo_root)"
require_source_path "$repo_root/bin"
require_source_path "$repo_root/lib"
require_source_path "$repo_root/skill-refs"
require_source_path "$repo_root/data/ask-flags"
require_source_path "$repo_root/data/power-grade"
require_source_path "$repo_root/data/model-effort"
require_source_path "$repo_root/data/skill-class"
require_source_path "$repo_root/data/maintenance-tracking.yaml"
require_source_path "$repo_root/data/research-shelf/index.jsonl"
require_source_path "$repo_root/VERSION"
require_source_path "$repo_root/completions/cog.bash"
if [[ ! -e $repo_root/man/cog.1 && ! -e $repo_root/man/cog.1.scd && $scdoc_available -eq 1 ]]; then
  cog_install_die "missing source path $repo_root/man/cog.1.scd; run from a complete cog checkout"
fi
if [[ ! -e $repo_root/man/cog.1 && $scdoc_available -eq 0 ]]; then
  cog_install_warn "scdoc not found and no prebuilt man/cog.1 exists; man page install will be skipped"
fi

cog_install_require_writable_dir "$state_dir" "state directory"
cog_install_require_writable_dir "$app_root" "application root"
cog_install_require_writable_dir "$data_dir" "data directory"
cog_install_require_writable_dir "$data_dir/data" "data table directory"
cog_install_require_writable_dir "$prefix/bin" "binary directory"
cog_install_require_writable_dir "$comp_dir" "completion directory"
if [[ -e $repo_root/man/cog.1 || (-e $repo_root/man/cog.1.scd && $scdoc_available -eq 1) ]]; then
  cog_install_require_writable_dir "$man_dir" "man page directory"
fi
cog_install_require_writable_dir "$home/.claude/skills" "Claude skills directory"
cog_install_require_writable_dir "$home/.claude/agents" "Claude agents directory"
cog_install_require_writable_dir "$home/.agents/skills" "Codex skills directory"

cog_install_detail "prefix: $prefix"
cog_install_detail "data: $xdg_data_home"
cog_install_detail "state: $xdg_state_home"
cog_install_detail "app root: $app_root"
cog_install_detail "binary link: $bin_link"
cog_install_detail "completion dir: $comp_dir"
cog_install_detail "man dir: $man_dir"
cog_install_detail "mirror mode: $mirror"
cog_install_detail "manifest: $manifest"
cog_install_ok "Preflight"

cog_install_set_step "prepare manifest" "Check write permissions under $state_dir and available disk space."
cog_install_step "Prepare manifest"
manifest_tmp="$(mktemp "$state_dir/.manifest.XXXXXX")" || exit 1
trap 'install_cleanup' EXIT
trap 'install_on_int' INT
trap 'install_on_term' TERM
cog_install_ok "Prepare manifest"

cog_install_set_step "prepare destination" "Check write permissions under $app_root and $data_dir."
cog_install_step "Prepare destination"
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
rm -rf -- "${data_dir:?}/data/ask-flags" "${data_dir:?}/data/power-grade" "${data_dir:?}/data/model-effort" "${data_dir:?}/data/skill-class" "${data_dir:?}/data/maintenance-tracking.yaml"
cog_install_ok "Prepare destination"

cog_install_set_step "copy application payload" "Check write permissions under $app_root and $data_dir."
cog_install_step "Copy application payload"
copy_tree "$repo_root/bin" "$app_root/bin"
copy_tree "$repo_root/lib" "$app_root/lib"
copy_tree "$repo_root/skill-refs" "$data_dir/skill-refs"
copy_tree "$repo_root/data/ask-flags" "$data_dir/data/ask-flags"
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
cog_install_ok "Copy application payload"

cog_install_set_step "link executable" "Check write permissions under $(dirname "$bin_link")."
cog_install_step "Link executable"
cog_install_require_parent_writable "$bin_link" "binary link"
ln -sfn "$app_root/bin/cog" "$bin_link"
record_path "$bin_link"
cog_install_ok "Link executable"

cog_install_set_step "sync Claude and Codex skills" "Check write permissions under $home/.claude and $home/.agents; if COG_INSTALL_MIRROR=1, verify the target roots are safe to mirror."
cog_install_step "Sync Claude and Codex skills"
sync_tree "$repo_root/skills/claude" "$home/.claude/skills"
sync_tree "$repo_root/agents/claude" "$home/.claude/agents"
sync_tree "$repo_root/skills/codex" "$home/.agents/skills"
cog_install_ok "Sync Claude and Codex skills"

cog_install_set_step "install shell integration" "Check write permissions under $comp_dir."
cog_install_step "Install shell integration"
install -d "$comp_dir"
install -m 0644 "$repo_root/completions/cog.bash" "$comp_dir/cog"
record_path "$comp_dir/cog"
cog_install_ok "Install shell integration"

cog_install_set_step "install man page" "Install scdoc or ensure $repo_root/man/cog.1 exists; check write permissions under $man_dir."
cog_install_step "Install man page"
install_man_page
cog_install_ok "Install man page"

cog_install_set_step "prune stale manifest entries" "Check write permissions under installed cog-owned paths and verify the existing manifest at $manifest."
cog_install_step "Prune stale manifest entries"
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
cog_install_ok "Prune stale manifest entries"

cog_install_set_step "finalize manifest" "Check write permissions under $state_dir and available disk space."
cog_install_step "Finalize manifest"
mv -f "$manifest_tmp.sorted" "$manifest"
rm -f "$manifest_tmp"
manifest_tmp=""
trap - EXIT
trap - INT
trap - TERM
cog_install_ok "Finalize manifest"

if ((cog_install_quiet != 1)); then
  cog_install_note "Installed:"
  cog_install_note "    app: $app_root"
  cog_install_note "    binary: $bin_link"
  cog_install_note "    manifest: $manifest"
  cog_install_note "    Claude skills: $home/.claude/skills"
  cog_install_note "    Claude agents: $home/.claude/agents"
  cog_install_note "    Codex skills: $home/.agents/skills"
  cog_install_note "    completion: $comp_dir/cog"
  cog_install_note "    man page: $man_page_status"
  cog_install_note "    PATH: ensure $(dirname "$bin_link") is on PATH"
fi

printf 'installed cog to %s (PATH: %s)\n' "$app_root" "$bin_link"
exit 0
