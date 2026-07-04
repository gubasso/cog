# shellcheck shell=bash
: 'desc: Parse runner-plan arguments and create round queue run state.'

__cog_runner_plan_setup_self_check='(.run_dir|type=="string") and (.plan_dir|type=="string") and (.inner_queue_path|type=="string") and (.repo_root|type=="string") and (.dry_run|type=="boolean") and has("max_rounds") and (.repos|type=="array") and (.queue_schema=="rounds") and (.plan_root|type=="string") and (.main_queue|type=="string") and (.store|type=="string") and (.project_key|type=="string")'

__cog_runner_plan_setup_usage() {
  cog::fn::ui_data "Usage: cog runner-plan-setup [--json] [arguments-string]"
}

__cog_runner_plan_setup_json_array() {
  if (($# == 0)); then
    jq -cn '[]'
    return 0
  fi
  printf '%s\n' "$@" | jq -R . | jq -s .
}

__cog_runner_plan_setup_strip_trailing_slashes() {
  local path="$1"
  while [[ $path != "/" && $path == */ ]]; do
    path="${path%/}"
  done
  printf '%s\n' "$path"
}

__cog_runner_plan_setup_parse() {
  local raw="$1" out_dry="$2" out_max="$3" out_target="$4"
  local parsed_dry=false parsed_max="" parsed_target="" saw_ar=false
  set -f
  # shellcheck disable=SC2086
  set -- $raw
  set +f
  while (($# > 0)); do
    case "$1" in
      -n | --dry-run)
        parsed_dry=true
        shift
        ;;
      --max)
        shift
        [[ $# -gt 0 && $1 =~ ^[1-9][0-9]*$ ]] || cog::fn::error_raise_with_exit 2 "InvalidInput" \
          "invalid max rounds" "option: --max" "expected a positive integer" ""
        parsed_max="$1"
        shift
        ;;
      --max=*)
        parsed_max="${1#--max=}"
        [[ $parsed_max =~ ^[1-9][0-9]*$ ]] || cog::fn::error_raise_with_exit 2 "InvalidInput" \
          "invalid max rounds" "option: --max" "expected a positive integer" ""
        shift
        ;;
      -ar | --auto-review)
        [[ $saw_ar == false && $# -ge 2 && -z $parsed_target ]] || cog::fn::error_raise_with_exit 2 "MissingArgument" \
          "missing runner-plan target" "option: $1" "" "pass -ar @<plan-dir>"
        saw_ar=true
        parsed_target="$2"
        shift 2
        ;;
      -*)
        cog::fn::error_raise_with_exit 2 "InvalidInput" \
          "unknown runner-plan flag" "option: $1" "" "expected -n, --dry-run, --max, or -ar"
        ;;
      *)
        cog::fn::error_raise_with_exit 2 "InvalidInput" \
          "unexpected runner-plan argument" "argument: $1" "" "pass the plan directory via -ar @<plan-dir>"
        ;;
    esac
  done
  [[ $saw_ar == true && -n $parsed_target ]] || cog::fn::error_raise_with_exit 2 "MissingArgument" \
    "missing runner-plan target" "usage: cog runner-plan-setup [--json] [arguments-string]" "" \
    "pass -ar @<plan-dir>"
  printf -v "$out_dry" '%s' "$parsed_dry"
  printf -v "$out_max" '%s' "$parsed_max"
  printf -v "$out_target" '%s' "$parsed_target"
}

__cog_runner_plan_setup_write_ctx() {
  local ctx="$1" repo_root="$2" plan_dir="$3" inner_queue_path="$4" run_dir="$5" dry_run="$6" max_rounds="$7" repos_joined="$8"
  local plan_root="$9" main_queue="${10}" store="${11}" project_key="${12}"
  {
    printf 'REPO_ROOT=%q\n' "$repo_root"
    printf 'PLAN_ROOT=%q\n' "$plan_root"
    printf 'MAIN_QUEUE_PATH=%q\n' "$main_queue"
    printf 'PLAN_DIR=%q\n' "$plan_dir"
    printf 'INNER_QUEUE_PATH=%q\n' "$inner_queue_path"
    printf 'QUEUE_PATH=%q\n' "$inner_queue_path"
    printf 'QUEUE_SCHEMA=%q\n' "rounds"
    printf 'PLAN_STORE=%q\n' "$store"
    printf 'PROJECT_KEY=%q\n' "$project_key"
    printf 'RUN_DIR=%q\n' "$run_dir"
    if [[ $dry_run == true ]]; then
      printf 'DRY_RUN=%q\n' "1"
    else
      printf 'DRY_RUN=%q\n' "0"
    fi
    printf 'MAX_ROUNDS=%q\n' "$max_rounds"
    printf 'REPOS=%q\n' "$repos_joined"
  } >"$ctx" || cog::fn::error_raise "JsonWriteFailed" \
    "could not write runner-plan context" "path: ${ctx}" "" "check run directory permissions"
}

__cog_runner_plan_setup_build_json() {
  local raw="$1" dry_run max_rounds target repo_root target_path plan_dir inner_queue_path run_dir queue_select_json repos_json repos_joined=""
  local resolve_json target_type plan_root main_queue store project_key
  local -a repos_arr=()
  __cog_runner_plan_setup_parse "$raw" dry_run max_rounds target
  repo_root="$(cog::fn::git_root)"
  [[ $target == @* ]] && target="${target#@}"
  target="$(__cog_runner_plan_setup_strip_trailing_slashes "$target")"
  if [[ $target == /* ]]; then
    target_path="$target"
  else
    target_path="${repo_root%/}/${target}"
  fi
  target_path="$(__cog_runner_plan_setup_strip_trailing_slashes "$target_path")"

  [[ -e $target_path ]] || cog::fn::error_raise "InvalidInput" \
    "plan target not found" "path: ${target_path}" "" ""
  [[ -d $target_path ]] || cog::fn::error_raise "InvalidInput" \
    "plan target is not a directory" "path: ${target_path}" "" ""

  repo_root="$(realpath "$repo_root")"
  plan_dir="$(realpath "$target_path")"

  # Resolve the plan vault (local or global store) through the shared resolver,
  # which asserts vault membership, flatness, and the presence + rounds schema of
  # queue-rounds.yaml — fully replacing the old fixed-parent-directory gate.
  resolve_json="$(cog::fn::plan_runner_resolve_json "$repo_root" "$plan_dir")"
  target_type="$(jq -r '.target_type' <<<"$resolve_json")"
  [[ $target_type == "plan-dir" ]] || cog::fn::error_raise "InvalidInput" \
    "runner-plan target must be a plan directory" "target_type: ${target_type}" "" "pass -ar @<plan-dir>"
  repo_root="$(jq -r '.repo_root' <<<"$resolve_json")"
  plan_root="$(jq -r '.plan_root' <<<"$resolve_json")"
  main_queue="$(jq -r '.main_queue' <<<"$resolve_json")"
  plan_dir="$(jq -r '.plan_dir' <<<"$resolve_json")"
  inner_queue_path="$(jq -r '.inner_queue_path' <<<"$resolve_json")"
  store="$(jq -r '.store' <<<"$resolve_json")"
  project_key="$(jq -r '.project_key' <<<"$resolve_json")"

  mapfile -t repos_arr < <(yq e -r '.repos[]?' "$inner_queue_path" 2>/dev/null || true)
  if ((${#repos_arr[@]} > 0)); then
    printf -v repos_joined '%s\n' "${repos_arr[@]}"
    repos_joined="${repos_joined%$'\n'}"
  fi
  run_dir="$(cog::fn::rundir_create runner-plan)"
  __cog_runner_plan_setup_write_ctx "${run_dir}/ctx.env" "$repo_root" "$plan_dir" "$inner_queue_path" "$run_dir" "$dry_run" "$max_rounds" "$repos_joined" "$plan_root" "$main_queue" "$store" "$project_key"

  if ! declare -F __cog_queue_select_build_json >/dev/null; then
    # shellcheck source=/dev/null
    source "${LIB_DIR}/commands/cmd_queue_select.sh"
  fi
  queue_select_json="$(__cog_queue_select_build_json rounds "$inner_queue_path" "$repo_root" false "${repos_arr[@]}")"
  # shellcheck disable=SC2154 # Defined by cmd_queue_select.sh sourced above.
  cog::fn::json_write_fragment "${run_dir}/round-select.json" "$__cog_queue_select_self_check" "$queue_select_json" >/dev/null
  repos_json="$(__cog_runner_plan_setup_json_array "${repos_arr[@]}")"

  jq -n \
    --arg run_dir "$run_dir" \
    --arg plan_dir "$plan_dir" \
    --arg inner_queue_path "$inner_queue_path" \
    --arg repo_root "$repo_root" \
    --arg plan_root "$plan_root" \
    --arg main_queue "$main_queue" \
    --arg store "$store" \
    --arg project_key "$project_key" \
    --argjson dry_run "$dry_run" \
    --arg max_rounds "$max_rounds" \
    --argjson repos "$repos_json" \
    '{run_dir: $run_dir, plan_dir: $plan_dir, inner_queue_path: $inner_queue_path,
      queue_schema: "rounds", repo_root: $repo_root, plan_root: $plan_root,
      main_queue: $main_queue, store: $store, project_key: $project_key, dry_run: $dry_run,
      max_rounds: (if $max_rounds == "" then null else $max_rounds end), repos: $repos}'
}

cog::cmd::runner_plan_setup() {
  local mode=human raw="" json
  if [[ ${1:-} == --json ]]; then
    mode="json"
    shift
  fi
  case "${1:-}" in
    -h | --help)
      __cog_runner_plan_setup_usage
      return 0
      ;;
  esac
  raw="${1:-}"
  json="$(__cog_runner_plan_setup_build_json "$raw")"
  if [[ $mode == json || ${COG_UI_JSON:-false} == true ]]; then
    cog::fn::json_emit "$__cog_runner_plan_setup_self_check" "$json"
  else
    cog::fn::ui_data "RUN_DIR=$(jq -r '.run_dir' <<<"$json")"
  fi
}
