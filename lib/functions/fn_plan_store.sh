# shellcheck shell=bash

cog::fn::plan_store_root() {
  # Pure path resolver: never create the global tree as a side effect (ADR-0057
  # D2). Creation + git-init belong to plan_store_init_global and the init-tree
  # paths, so a read-only `cog plan project resolve`/`store path`/`doctor` can
  # never leave a non-git global vault behind. Canonicalize an existing root via
  # cd -P; fall back to realpath -m for a not-yet-created one.
  local dir="${COG_PLAN_HOME:-${XDG_DATA_HOME:-$HOME/.local/share}/cog/plans}"
  if [[ -d $dir ]]; then
    (cd -P "$dir" && pwd)
  else
    realpath -m "$dir"
  fi
}

cog::fn::plan_state_root() {
  local dir="${XDG_STATE_HOME:-$HOME/.local/state}/cog"
  mkdir -p "$dir" || cog::fn::error_raise "TempDirCreateFailed" \
    "could not create plan state root" "path: ${dir}" "" "check permissions"
  (cd -P "$dir" && pwd)
}

cog::fn::plan_trust_db_path() {
  printf '%s\n' "$(cog::fn::plan_state_root)/trust/plans.json"
}

cog::fn::plan_local_dir() {
  local root="${1:-}"
  [[ -n $root ]] || cog::fn::error_raise "MissingArgument" \
    "missing project root" "function: plan_local_dir" "" ""
  printf '%s\n' "${root%/}/${COG_PLAN_LOCAL_DIR:-.cog/plans}"
}

__cog_plan_realpath_or_pwd() {
  local path="${1:-}"
  if [[ -d $path ]]; then
    (cd -P "$path" && pwd)
  else
    realpath -m "$path"
  fi
}

cog::fn::plan_git_identity() {
  local root="${1:-}" git_remote="" git_common_dir="" common_path=""
  [[ -n $root ]] || cog::fn::error_raise "MissingArgument" \
    "missing project root" "function: plan_git_identity" "" ""

  git_remote="$(git -C "$root" config --get remote.origin.url 2>/dev/null || true)"
  if [[ -n $git_remote ]]; then
    printf '%s\n' "$git_remote"
    return 0
  fi

  git_common_dir="$(git -C "$root" rev-parse --git-common-dir 2>/dev/null || true)"
  if [[ -n $git_common_dir ]]; then
    if [[ $git_common_dir == /* ]]; then
      common_path="$git_common_dir"
    else
      common_path="${root%/}/${git_common_dir}"
    fi
    realpath "$common_path"
    return 0
  fi

  __cog_plan_realpath_or_pwd "$root"
}

# Derive a stable display name from git identity, independent of the working
# checkout path so worktrees of one repo coalesce. Falls back to the project
# basename only for non-git directories.
__cog_plan_identity_name() {
  local git_remote="${1:-}" git_common_dir="${2:-}" project_root="${3:-}" base parent
  if [[ -n $git_remote ]]; then
    base="${git_remote%/}"
    base="${base##*/}"
    base="${base%.git}"
  elif [[ -n $git_common_dir ]]; then
    base="${git_common_dir%/}"
    if [[ ${base##*/} == ".git" ]]; then
      parent="${base%/.git}"
      base="${parent##*/}"
    else
      base="${base##*/}"
      base="${base%.git}"
    fi
  else
    base="$(basename "$project_root")"
  fi
  printf '%s\n' "$base"
}

# Read the persisted git identity from an existing project.sh, if present.
# Empty output means the file is unreadable or predates identity persistence
# (legacy vault entries), which the collision-extend treats as a match so old
# keys keep resolving unchanged.
__cog_plan_project_identity_from_file() {
  local file="${1:-}"
  [[ -r $file ]] || return 0
  sed -n -E "s/^[[:space:]]*COG_PLAN_GIT_IDENTITY[[:space:]]*=[[:space:]]*'([^']*)'[[:space:]]*$/\1/p" "$file" \
    | head -n1
}

cog::fn::plan_project_identity_json() {
  local root="${1:-}" project_root display_name slug git_remote git_common_dir git_identity primary_realpath
  local hash_input_sha256 hash16 project_key
  [[ -n $root ]] || cog::fn::error_raise "MissingArgument" \
    "missing project root" "function: plan_project_identity_json" "" ""
  [[ -d $root ]] || cog::fn::error_raise "InputNotFound" \
    "project root not found" "path: ${root}" "" "check the project root"

  project_root="$(__cog_plan_realpath_or_pwd "$root")"
  git_remote="$(git -C "$project_root" config --get remote.origin.url 2>/dev/null || true)"
  git_common_dir="$(git -C "$project_root" rev-parse --git-common-dir 2>/dev/null || true)"
  if [[ -n $git_common_dir && $git_common_dir != /* ]]; then
    git_common_dir="$(realpath -m "${project_root%/}/${git_common_dir}")"
  fi
  git_identity="$(cog::fn::plan_git_identity "$project_root")"
  primary_realpath="$project_root"
  # Stable name/slug from git identity, not the per-worktree checkout basename.
  display_name="$(__cog_plan_identity_name "$git_remote" "$git_common_dir" "$project_root")"
  slug="$(cog::fn::plan_slug::derive "$display_name")"
  [[ -n $slug ]] || slug="project"
  # Key purely on git identity so worktrees of one repo and a moved repo coalesce
  # to one vault entry; the per-checkout realpath is surfaced only in COG_PLAN_ROOTS.
  hash_input_sha256="$(printf '%s' "$git_identity" | sha256sum | awk '{print $1}')"
  hash16="${hash_input_sha256:0:16}"
  # Collision-extend (ADR-0057 D3): start at the 16-hex prefix and extend two hex
  # at a time (18, 20, ... 64) until the key is unused or already persisted for
  # this exact git identity, so two repos whose SHA-256 prefixes collide get
  # distinct, stable keys. Same identity resolves to the same key idempotently.
  local store_projects key_hash candidate cand_file persisted len
  store_projects="$(cog::fn::plan_store_root)/projects"
  project_key=""
  key_hash="$hash16"
  for ((len = 16; len <= 64; len += 2)); do
    key_hash="${hash_input_sha256:0:len}"
    candidate="${slug}-${key_hash}"
    cand_file="${store_projects}/${candidate}/project.sh"
    if [[ ! -e $cand_file ]]; then
      project_key="$candidate"
      break
    fi
    persisted="$(__cog_plan_project_identity_from_file "$cand_file")"
    if [[ -z $persisted || $persisted == "$git_identity" ]]; then
      project_key="$candidate"
      break
    fi
  done
  [[ -n $project_key ]] || cog::fn::error_raise "InvalidInput" \
    "plan project key collision could not be resolved" "slug: ${slug}" \
    "every SHA-256 prefix up to 64 hex collides with a different git identity" \
    "report this collision and remove the stale vault entry"

  jq -n \
    --arg project_root "$project_root" \
    --arg display_name "$display_name" \
    --arg slug "$slug" \
    --arg git_remote "$git_remote" \
    --arg git_common_dir "$git_common_dir" \
    --arg git_identity "$git_identity" \
    --arg primary_realpath "$primary_realpath" \
    --arg hash_input_sha256 "$hash_input_sha256" \
    --arg hash16 "$hash16" \
    --arg key_hash "$key_hash" \
    --arg project_key "$project_key" \
    '{project_root: $project_root, display_name: $display_name, slug: $slug,
      git_remote: $git_remote, git_common_dir: $git_common_dir,
      git_identity: $git_identity, primary_realpath: $primary_realpath,
      hash_input_sha256: $hash_input_sha256, hash16: $hash16, key_hash: $key_hash,
      project_key: $project_key}'
}

cog::fn::plan_project_dir() {
  local root="${1:-}" identity project_key
  identity="$(cog::fn::plan_project_identity_json "$root")"
  project_key="$(jq -r '.project_key' <<<"$identity")"
  printf '%s\n' "$(cog::fn::plan_store_root)/projects/${project_key}"
}

__cog_plan_quote_literal() {
  local value="${1:-}"
  printf "'%s'" "${value//\'/\'\\\'\'}"
}

__cog_plan_project_roots_from_file() {
  local file="${1:-}"
  [[ -r $file ]] || return 0
  sed -n -E "s/^[[:space:]]*COG_PLAN_ROOTS[[:space:]]*=[[:space:]]*'([^']*)'[[:space:]]*$/\1/p" "$file" \
    | tr ':' '\n'
}

cog::fn::plan_write_project_file() {
  local dir="${1:-}" root="${2:-}" file identity project_key display_name git_remote git_common_dir created_at roots
  local existing_root project_root git_identity key_hash
  [[ -n $dir && -n $root ]] || cog::fn::error_raise "MissingArgument" \
    "missing project file inputs" "function: plan_write_project_file" "" ""
  mkdir -p "$dir" || cog::fn::error_raise "TempDirCreateFailed" \
    "could not create project plan directory" "path: ${dir}" "" "check permissions"

  file="${dir%/}/project.sh"
  identity="$(cog::fn::plan_project_identity_json "$root")"
  project_root="$(jq -r '.project_root' <<<"$identity")"
  project_key="$(jq -r '.project_key' <<<"$identity")"
  display_name="$(jq -r '.display_name' <<<"$identity")"
  git_remote="$(jq -r '.git_remote' <<<"$identity")"
  git_common_dir="$(jq -r '.git_common_dir' <<<"$identity")"
  git_identity="$(jq -r '.git_identity' <<<"$identity")"
  key_hash="$(jq -r '.key_hash' <<<"$identity")"
  created_at="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
  roots="$project_root"

  if [[ -f $file ]]; then
    while IFS= read -r existing_root; do
      [[ -n $existing_root ]] || continue
      if [[ ":${roots}:" != *":${existing_root}:"* ]]; then
        roots="${roots}:${existing_root}"
      fi
    done < <(__cog_plan_project_roots_from_file "$file")
    created_at="$(sed -n -E "s/^[[:space:]]*COG_PLAN_CREATED_AT[[:space:]]*=[[:space:]]*'([^']*)'[[:space:]]*$/\1/p" "$file" | head -n1)"
    [[ -n $created_at ]] || created_at="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
  fi

  {
    printf '%s=%s\n' "COG_PLAN_PROJECT_KEY" "$(__cog_plan_quote_literal "$project_key")"
    printf '%s=%s\n' "COG_PLAN_DISPLAY_NAME" "$(__cog_plan_quote_literal "$display_name")"
    printf '%s=%s\n' "COG_PLAN_GIT_REMOTE" "$(__cog_plan_quote_literal "$git_remote")"
    printf '%s=%s\n' "COG_PLAN_GIT_COMMON_DIR" "$(__cog_plan_quote_literal "$git_common_dir")"
    printf '%s=%s\n' "COG_PLAN_GIT_IDENTITY" "$(__cog_plan_quote_literal "$git_identity")"
    printf '%s=%s\n' "COG_PLAN_KEY_HASH" "$(__cog_plan_quote_literal "$key_hash")"
    printf '%s=%s\n' "COG_PLAN_ROOTS" "$(__cog_plan_quote_literal "$roots")"
    printf '%s=%s\n' "COG_PLAN_CREATED_AT" "$(__cog_plan_quote_literal "$created_at")"
  } >"$file" || cog::fn::error_raise "JsonWriteFailed" \
    "could not write project plan metadata" "path: ${file}" "" "check permissions"
}
