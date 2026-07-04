# shellcheck shell=bash
: 'desc: Parse runner-all arguments and create main queue run state.'

__cog_runner_all_setup_self_check='(.run_dir|type=="string") and (.queue_path|type=="string") and (.main_queue_path|type=="string") and (.repo_root|type=="string") and (.dry_run|type=="boolean") and has("max_plans") and (.repos|type=="array") and (.queue_schema=="plans") and (.plan_root|type=="string") and (.store|type=="string") and (.project_key|type=="string")'

__cog_runner_all_setup_usage() {
  cog::fn::ui_data "Usage: cog runner-all-setup [--json] [arguments-string]"
}

__cog_runner_all_setup_json_array() {
  if (($# == 0)); then
    jq -cn '[]'
    return 0
  fi
  printf '%s\n' "$@" | jq -R . | jq -s .
}

__cog_runner_all_setup_parse() {
  local raw="$1" out_dry="$2" out_max="$3" out_target="$4"
  local parsed_dry=false parsed_max="" parsed_target=""
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
          "invalid max plans" "option: --max" "expected a positive integer" ""
        parsed_max="$1"
        shift
        ;;
      --max=*)
        parsed_max="${1#--max=}"
        [[ $parsed_max =~ ^[1-9][0-9]*$ ]] || cog::fn::error_raise_with_exit 2 "InvalidInput" \
          "invalid max plans" "option: --max" "expected a positive integer" ""
        shift
        ;;
      -*)
        cog::fn::error_raise_with_exit 2 "InvalidInput" \
          "unknown runner-all flag" "option: $1" "" "expected -n, --dry-run, or --max"
        ;;
      *)
        [[ -z $parsed_target ]] || cog::fn::error_raise_with_exit 2 "TooManyArguments" \
          "too many main queue targets" "argument: $1" "" "pass exactly one queue-plans.yaml path"
        parsed_target="$1"
        shift
        ;;
    esac
  done
  [[ -n $parsed_target ]] || cog::fn::error_raise_with_exit 2 "MissingArgument" \
    "missing main queue target" "usage: cog runner-all-setup [--json] [arguments-string]" "" ""
  printf -v "$out_dry" '%s' "$parsed_dry"
  printf -v "$out_max" '%s' "$parsed_max"
  printf -v "$out_target" '%s' "$parsed_target"
}

__cog_runner_all_setup_write_ctx() {
  local ctx="$1" repo_root="$2" queue_path="$3" run_dir="$4" dry_run="$5" max_plans="$6" repos_joined="$7"
  local plan_root="$8" store="$9" project_key="${10}"
  {
    printf 'REPO_ROOT=%q\n' "$repo_root"
    printf 'PLAN_ROOT=%q\n' "$plan_root"
    printf 'QUEUE_PATH=%q\n' "$queue_path"
    printf 'QUEUE_SCHEMA=%q\n' "plans"
    printf 'MAIN_QUEUE_PATH=%q\n' "$queue_path"
    printf 'PLAN_STORE=%q\n' "$store"
    printf 'PROJECT_KEY=%q\n' "$project_key"
    printf 'RUN_DIR=%q\n' "$run_dir"
    if [[ $dry_run == true ]]; then
      printf 'DRY_RUN=%q\n' "1"
    else
      printf 'DRY_RUN=%q\n' "0"
    fi
    printf 'MAX_PLANS=%q\n' "$max_plans"
    printf 'REPOS=%q\n' "$repos_joined"
  } >"$ctx" || cog::fn::error_raise "JsonWriteFailed" \
    "could not write runner-all context" "path: ${ctx}" "" "check run directory permissions"
}

__cog_runner_all_setup_build_json() {
  local raw="$1" dry_run max_plans target repo_root queue_path run_dir queue_select_json repos_json repos_joined=""
  local resolve_json target_type plan_root store project_key
  local -a repos_arr=()
  __cog_runner_all_setup_parse "$raw" dry_run max_plans target
  repo_root="$(cog::fn::git_root)"
  queue_path="$target"
  [[ $queue_path == /* ]] || queue_path="${repo_root}/${queue_path}"

  # Resolve the plan vault (local or global store) through the shared resolver,
  # which validates the plans schema and cross-checks that the target is the
  # <PLAN_ROOT>/queue-plans.yaml main queue — identical to runner-plan's view.
  resolve_json="$(cog::fn::plan_runner_resolve_json "$repo_root" "$queue_path")"
  target_type="$(jq -r '.target_type' <<<"$resolve_json")"
  [[ $target_type == "main-queue" ]] || cog::fn::error_raise "InvalidInput" \
    "runner-all target must be queue-plans.yaml" "target_type: ${target_type}" "" "pass <PLAN_ROOT>/queue-plans.yaml"
  repo_root="$(jq -r '.repo_root' <<<"$resolve_json")"
  queue_path="$(jq -r '.main_queue' <<<"$resolve_json")"
  plan_root="$(jq -r '.plan_root' <<<"$resolve_json")"
  store="$(jq -r '.store' <<<"$resolve_json")"
  project_key="$(jq -r '.project_key' <<<"$resolve_json")"

  mapfile -t repos_arr < <(yq e -r '.repos[]?' "$queue_path" 2>/dev/null || true)
  if ((${#repos_arr[@]} > 0)); then
    printf -v repos_joined '%s\n' "${repos_arr[@]}"
    repos_joined="${repos_joined%$'\n'}"
  fi
  run_dir="$(cog::fn::rundir_create runner-all)"
  __cog_runner_all_setup_write_ctx "${run_dir}/ctx.env" "$repo_root" "$queue_path" "$run_dir" "$dry_run" "$max_plans" "$repos_joined" "$plan_root" "$store" "$project_key"

  if ! declare -F __cog_queue_select_build_json >/dev/null; then
    # shellcheck source=/dev/null
    source "${LIB_DIR}/commands/cmd_queue_select.sh"
  fi
  queue_select_json="$(__cog_queue_select_build_json plans "$queue_path" "$repo_root" false "${repos_arr[@]}")"
  # shellcheck disable=SC2154 # Defined by cmd_queue_select.sh sourced above.
  cog::fn::json_write_fragment "${run_dir}/main-select.json" "$__cog_queue_select_self_check" "$queue_select_json" >/dev/null
  repos_json="$(__cog_runner_all_setup_json_array "${repos_arr[@]}")"

  jq -n \
    --arg run_dir "$run_dir" \
    --arg queue_path "$queue_path" \
    --arg main_queue_path "$queue_path" \
    --arg repo_root "$repo_root" \
    --arg plan_root "$plan_root" \
    --arg store "$store" \
    --arg project_key "$project_key" \
    --argjson dry_run "$dry_run" \
    --arg max_plans "$max_plans" \
    --argjson repos "$repos_json" \
    '{run_dir: $run_dir, queue_path: $queue_path, main_queue_path: $main_queue_path,
      queue_schema: "plans", repo_root: $repo_root, plan_root: $plan_root,
      store: $store, project_key: $project_key, dry_run: $dry_run,
      max_plans: (if $max_plans == "" then null else $max_plans end), repos: $repos}'
}

cog::cmd::runner_all_setup() {
  local mode=human raw="" json
  if [[ ${1:-} == --json ]]; then
    mode="json"
    shift
  fi
  case "${1:-}" in
    -h | --help)
      __cog_runner_all_setup_usage
      return 0
      ;;
  esac
  raw="${1:-}"
  json="$(__cog_runner_all_setup_build_json "$raw")"
  if [[ $mode == json || ${COG_UI_JSON:-false} == true ]]; then
    cog::fn::json_emit "$__cog_runner_all_setup_self_check" "$json"
  else
    cog::fn::ui_data "RUN_DIR=$(jq -r '.run_dir' <<<"$json")"
  fi
}
