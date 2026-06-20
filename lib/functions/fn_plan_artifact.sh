# shellcheck shell=bash

cog::fn::plan_artifact::require_jq() {
  cog::fn::research::require_jq
}

cog::fn::plan_artifact::require_absolute_path() {
  local path="${1:-}"
  local label="${2:-path}"

  [[ -n $path ]] || cog::fn::error_raise "MissingArgument" \
    "missing ${label} path" "field: ${label}" "" "pass an absolute path"
  [[ $path == /* ]] || cog::fn::error_raise "InvalidInput" \
    "${label} path must be absolute" "path: ${path}" "" "pass an absolute path"
}

cog::fn::plan_artifact::runtime_root() {
  cog::fn::rundir_base "cog/plan-artifacts"
}

cog::fn::plan_artifact::run_dir() {
  local family="${1:-}"
  local slug="${2:-}"
  local prefix root run_dir

  [[ -n $family ]] || cog::fn::error_raise "MissingArgument" \
    "missing plan artifact family" "function: cog::fn::plan_artifact::run_dir" "" ""
  prefix="$family"
  [[ -z $slug ]] || prefix="${prefix}-${slug}"
  root="$(cog::fn::plan_artifact::runtime_root)"
  mkdir -p -- "$root" || cog::fn::error_raise "JsonWriteFailed" \
    "could not create plan artifact root" "path: ${root}" "" "check permissions and retry"
  run_dir="${root}/${prefix}-$(date -u +%Y%m%dT%H%M%S)-$$"
  mkdir -p -- "$run_dir" || cog::fn::error_raise "JsonWriteFailed" \
    "could not create plan artifact run directory" "path: ${run_dir}" "" "check permissions and retry"
  printf '%s\n' "$run_dir"
}

cog::fn::plan_artifact::slug_from_text() {
  local text="${1:-}"
  cog::fn::plan_slug::derive "$text"
}

cog::fn::plan_artifact::research_shelf_json() {
  local root_override="${1:-}"
  local root index exists=false

  root="$(cog::fn::research::root "$root_override")"
  index="$(cog::fn::research::index_path "$root")"
  [[ -f $index ]] && exists=true

  jq -n \
    --arg root "$root" \
    --arg index "$index" \
    --argjson exists "$exists" \
    '{root: $root, index: $index, exists: $exists}'
}

cog::fn::plan_artifact::resolve_paths_json() {
  local family="${1:-}"
  local text="${2:-}"
  local output_override="${3:-}"
  local research_root_override="${4:-}"
  local slug run_dir output_path output_overridden=false research_shelf

  [[ -n $family ]] || cog::fn::error_raise "MissingArgument" \
    "missing plan artifact family" "function: cog::fn::plan_artifact::resolve_paths_json" "" ""
  [[ -n $text ]] || cog::fn::error_raise "MissingArgument" \
    "missing plan artifact text" "function: cog::fn::plan_artifact::resolve_paths_json" "" ""
  slug="$(cog::fn::plan_artifact::slug_from_text "$text")"
  [[ -n $slug ]] || cog::fn::error_raise "InvalidInput" \
    "plan artifact slug is empty" "text: ${text}" "" "pass text that contains letters or digits"
  run_dir="$(cog::fn::plan_artifact::run_dir "$family" "$slug")"
  if [[ -n $output_override ]]; then
    cog::fn::plan_artifact::require_absolute_path "$output_override" output
    output_path="$output_override"
    output_overridden=true
  else
    output_path="${run_dir}/${slug}.md"
  fi
  research_shelf="$(cog::fn::plan_artifact::research_shelf_json "$research_root_override")"

  jq -n \
    --argjson ok true \
    --arg family "$family" \
    --arg slug "$slug" \
    --arg run_dir "$run_dir" \
    --arg output_path "$output_path" \
    --argjson output_overridden "$output_overridden" \
    --argjson research_shelf "$research_shelf" \
    '{ok: $ok, family: $family, slug: $slug, run_dir: $run_dir,
      output_path: $output_path, output_overridden: $output_overridden,
      research_shelf: $research_shelf}'
}

cog::fn::plan_artifact::write_file() {
  local output_path="${1:-}"
  local content="${2:-}"
  local parent

  cog::fn::plan_artifact::require_absolute_path "$output_path" output
  parent="$(dirname -- "$output_path")"
  mkdir -p -- "$parent" || cog::fn::error_raise "JsonWriteFailed" \
    "could not create plan artifact parent directory" "path: ${parent}" "" \
    "check permissions and retry"
  printf '%s\n' "$content" >"$output_path" || cog::fn::error_raise "JsonWriteFailed" \
    "could not write plan artifact" "path: ${output_path}" "" "check permissions and retry"
}

cog::fn::plan_artifact::file_nonempty() {
  local path="${1:-}"
  local label="${2:-file}"

  cog::fn::rundir_require_file "$path" "$label"
}
