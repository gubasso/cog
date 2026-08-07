# shellcheck shell=bash

# Layer resolution, workspace loading, and engine-registry lookup for the cog
# workflow engine (docs/reference/workflow-contract.md).
#
# The unit of resolution is the FILE, not the root. One resolver walks project,
# then user, then installed, and returns the first file that exists, taken
# whole. Nothing is merged, so a project-layer workflow replaces the installed
# one entirely rather than inheriting its steps. Resolving per file is what
# lets a user-authored workflow reference a shipped step.
#
# Note for manual testing: cog::fn::workflow::installed_root mirrors
# cog::fn::data_root and prefers the installed XDG root whenever it exists, so
# a checkout's workflow/ is invisible to an installed cog until `just install`.
# Prefix manual checks with XDG_DATA_HOME="$(mktemp -d)" to read the checkout.

cog::fn::workflow::project_root() {
  printf '%s\n' "${COG_WORKFLOW_PROJECT_ROOT:-${PWD}/workflow}"
}

cog::fn::workflow::user_root() {
  printf '%s\n' "${XDG_CONFIG_HOME:-${HOME}/.config}/cog/workflow"
}

cog::fn::workflow::installed_root() {
  local xdg_candidate repo_candidate normalized
  xdg_candidate="${XDG_DATA_HOME:-${HOME}/.local/share}/cog/workflow"
  repo_candidate="${LIB_DIR}/../workflow"

  if [[ -d $xdg_candidate ]]; then
    normalized="$(cd -P "$xdg_candidate" && pwd)" || return 1
    printf '%s\n' "$normalized"
    return 0
  fi
  if [[ -d $repo_candidate ]]; then
    normalized="$(cd -P "$repo_candidate" && pwd)" || return 1
    printf '%s\n' "$normalized"
    return 0
  fi
  return 1
}

# Print "<layer> <root>" per line, in resolution order.
cog::fn::workflow::layers() {
  local root

  root="$(cog::fn::workflow::project_root)" || root=""
  [[ -z $root ]] || printf 'project %s\n' "$root"
  root="$(cog::fn::workflow::user_root)" || root=""
  [[ -z $root ]] || printf 'user %s\n' "$root"
  if root="$(cog::fn::workflow::installed_root)"; then
    printf 'installed %s\n' "$root"
  fi
}

# Reject empty, absolute, and traversing relative paths, exactly as
# cog::fn::data::path does.
cog::fn::workflow::__safe_rel() {
  local rel="${1:-}"

  [[ -n $rel ]] || return 1
  [[ $rel != /* ]] || return 1
  [[ $rel != *..* ]] || return 1
  return 0
}

cog::fn::workflow::valid_key() {
  local key="${1:-}"
  [[ $key =~ ^[a-z0-9][a-z0-9-]*$ ]]
}

# An instance name becomes a directory under the run directory, so it must be
# one safe path segment. The validator rule safe-instance-name and the resolve
# guard share this predicate.
cog::fn::workflow::valid_instance() {
  local name="${1:-}"
  [[ $name =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]]
}

# Print the absolute path of the first layer that carries <relpath>.
cog::fn::workflow::resolve_file() {
  local rel="${1:-}"
  local layer root candidate

  cog::fn::workflow::__safe_rel "$rel" || return 1
  while read -r layer root; do
    [[ -n $layer ]] || continue
    candidate="${root}/${rel}"
    if [[ -f $candidate ]]; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done < <(cog::fn::workflow::layers)
  return 1
}

# Print the layer name (project|user|installed) that carries <relpath>.
cog::fn::workflow::resolve_source() {
  local rel="${1:-}"
  local layer root

  cog::fn::workflow::__safe_rel "$rel" || return 1
  while read -r layer root; do
    [[ -n $layer ]] || continue
    if [[ -f "${root}/${rel}" ]]; then
      printf '%s\n' "$layer"
      return 0
    fi
  done < <(cog::fn::workflow::layers)
  return 1
}

cog::fn::workflow::workflow_rel() {
  printf 'workflows/%s.yaml\n' "$1"
}

cog::fn::workflow::step_rel() {
  printf 'steps/%s.yaml\n' "$1"
}

cog::fn::workflow::skill_rel() {
  printf 'skills/%s.md\n' "$1"
}

# The resolved meta.yaml as JSON, with the three closed defaults filled in when
# no layer carries the file.
cog::fn::workflow::load_meta() {
  local path

  if path="$(cog::fn::workflow::resolve_file meta.yaml)"; then
    yq e -o=json '.' "$path" 2>/dev/null && return 0
  fi
  printf '%s\n' '{"context":"fresh","max_rounds":5,"max_workflow_depth":3}'
}

# Parse a resolved YAML file to JSON, or fail.
cog::fn::workflow::load_yaml() {
  local path="${1:-}"

  [[ -f $path ]] || return 1
  yq e -o=json '.' "$path" 2>/dev/null
}

# Unique definition keys under <subdir> across every layer, sorted.
cog::fn::workflow::list_keys() {
  local subdir="${1:-}"
  local layer root file base

  [[ -n $subdir ]] || return 1
  while read -r layer root; do
    [[ -n $layer ]] || continue
    [[ -d "${root}/${subdir}" ]] || continue
    while IFS= read -r file; do
      base="$(basename "$file")"
      printf '%s\n' "${base%.yaml}"
    done < <(find "${root}/${subdir}" -maxdepth 1 -type f -name '*.yaml' -print 2>/dev/null)
  done < <(cog::fn::workflow::layers) | sort -u
}

# --- Engine registry -------------------------------------------------------
#
# The registry is CLI-owned reference data under data/, not layer-resolvable
# workspace content: membership in the registry is the permission, so a project
# layer must not be able to grant itself an engine.

cog::fn::workflow::registry_json() {
  local path

  path="$(cog::fn::data::path workflow-engines)" || cog::fn::error_raise_with_exit 1 \
    "InternalStateFailure" "workflow engine registry not found" \
    "table: workflow-engines" \
    "data/workflow-engines is missing from the resolved data root" \
    "run 'just install', or set XDG_DATA_HOME to an empty dir to use the repo checkout"
  cog::fn::data::load_dir "$path"
}

cog::fn::workflow::engine_record() {
  local id="${1:-}"
  local registry="${2:-}"

  [[ -n $registry ]] || registry="$(cog::fn::workflow::registry_json)"
  jq -c --arg id "$id" '(.["workflow-engines"] // []) | map(select(.id == $id)) | first // empty' <<<"$registry"
}

cog::fn::workflow::engine_exists() {
  local record
  record="$(cog::fn::workflow::engine_record "$@")"
  [[ -n $record ]]
}

cog::fn::workflow::provider_record() {
  local provider="${1:-}"
  local registry="${2:-}"

  [[ -n $registry ]] || registry="$(cog::fn::workflow::registry_json)"
  jq -c --arg p "$provider" '(.["workflow-engine-providers"] // {})[$p] // empty' <<<"$registry"
}
