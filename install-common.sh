path_under() {
  local path="$1"
  local root="$2"

  [[ $path == "$root" || $path == "$root"/* ]]
}

valid_manifest_path() {
  local path="$1"

  if [[ -z $path || $path != /* || $path == / ]]; then
    return 1
  fi

  if path_under "$path" "$app_root" \
    || path_under "$path" "$data_dir/skill-refs" \
    || path_under "$path" "$prefix/bin" \
    || path_under "$path" "$home/.claude/skills" \
    || path_under "$path" "$home/.claude/agents" \
    || path_under "$path" "$home/.agents/skills" \
    || path_under "$path" "$comp_dir" \
    || path_under "$path" "$man_dir" \
    || path_under "$path" "$state_dir"; then
    return 0
  fi

  return 1
}

rmdir_empty() {
  local dir="$1"
  rmdir -- "$dir" 2>/dev/null || true
  return 0
}

prune_empty_tree() {
  local root="$1"
  local dir

  [[ -d $root ]] || return 0
  while IFS= read -r dir; do
    rmdir_empty "$dir"
  done < <(find "$root" -depth -type d -print)

  return 0
}

prune_manifest_skill_dir() {
  local path="$1"
  local root="$2"
  local dir

  path_under "$path" "$root" || return 0
  dir="$(dirname "$path")"
  while [[ $dir != "$root" && $dir == "$root"/* ]]; do
    rmdir_empty "$dir"
    dir="$(dirname "$dir")"
  done

  return 0
}
