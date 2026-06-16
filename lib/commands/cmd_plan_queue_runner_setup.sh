# shellcheck shell=bash
: 'desc: Parse plan-queue-runner arguments and create run state.'

__cog_plan_queue_runner_setup_self_check='(.run_dir|type=="string") and (.queue_path|type=="string") and (.repo_root|type=="string") and (.dry_run|type=="boolean") and has("max_rounds")'

__cog_plan_queue_runner_setup_usage() {
  cog::fn::ui_data "Usage: cog plan-queue-runner-setup [--json] [arguments-string]"
}

__cog_plan_queue_runner_setup_parse() {
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
      -*)
        cog::fn::error_raise_with_exit 2 "InvalidInput" \
          "unknown plan-queue-runner flag" "option: $1" "" "expected -n, --dry-run, or --max"
        ;;
      *)
        [[ -z $parsed_target ]] || cog::fn::error_raise_with_exit 2 "TooManyArguments" \
          "too many plan queue targets" "argument: $1" "" "pass exactly one plan dir or QUEUE.yaml path"
        parsed_target="$1"
        shift
        ;;
    esac
  done
  [[ -n $parsed_target ]] || cog::fn::error_raise_with_exit 2 "MissingArgument" \
    "missing plan queue target" "usage: cog plan-queue-runner-setup [--json] [arguments-string]" "" ""
  printf -v "$out_dry" '%s' "$parsed_dry"
  printf -v "$out_max" '%s' "$parsed_max"
  printf -v "$out_target" '%s' "$parsed_target"
}

__cog_plan_queue_runner_setup_write_ctx() {
  local ctx="$1" repo_root="$2" queue_path="$3" run_dir="$4" dry_run="$5" max_rounds="$6"
  {
    printf 'REPO_ROOT=%q\n' "$repo_root"
    printf 'QUEUE_PATH=%q\n' "$queue_path"
    printf 'RUN_DIR=%q\n' "$run_dir"
    if [[ $dry_run == true ]]; then
      printf 'DRY_RUN=%q\n' "1"
    else
      printf 'DRY_RUN=%q\n' "0"
    fi
    printf 'MAX_ROUNDS=%q\n' "$max_rounds"
  } >"$ctx" || cog::fn::error_raise "JsonWriteFailed" \
    "could not write queue runner context" "path: ${ctx}" "" "check run directory permissions"
}

__cog_plan_queue_runner_setup_build_json() {
  local raw="$1" dry_run max_rounds target repo_root queue_path run_dir queue_select_json
  __cog_plan_queue_runner_setup_parse "$raw" dry_run max_rounds target
  repo_root="$(cog::fn::git_root)"
  case "$target" in
    */QUEUE.yaml) queue_path="$target" ;;
    *) queue_path="${target}/QUEUE.yaml" ;;
  esac
  [[ $queue_path == /* ]] || queue_path="${repo_root}/${queue_path}"
  [[ -f $queue_path ]] || cog::fn::error_raise "InputNotFound" \
    "QUEUE.yaml not found" "path: ${queue_path}" "" "check the target path"
  run_dir="$(cog::fn::rundir_create plan-queue-runner)"
  __cog_plan_queue_runner_setup_write_ctx "${run_dir}/ctx.env" "$repo_root" "$queue_path" "$run_dir" "$dry_run" "$max_rounds"

  if ! declare -F __cog_queue_select_build_json >/dev/null; then
    # shellcheck source=/dev/null
    source "${LIB_DIR}/commands/cmd_queue_select.sh"
  fi
  queue_select_json="$(__cog_queue_select_build_json "$queue_path" "$repo_root" false)"
  # shellcheck disable=SC2154 # Defined by cmd_queue_select.sh sourced above.
  cog::fn::json_write_fragment "${run_dir}/queue-select.json" "$__cog_queue_select_self_check" "$queue_select_json" >/dev/null

  jq -n \
    --arg run_dir "$run_dir" \
    --arg queue_path "$queue_path" \
    --arg repo_root "$repo_root" \
    --argjson dry_run "$dry_run" \
    --arg max_rounds "$max_rounds" \
    '{run_dir: $run_dir, queue_path: $queue_path, repo_root: $repo_root, dry_run: $dry_run,
      max_rounds: (if $max_rounds == "" then null else $max_rounds end)}'
}

cog::cmd::plan_queue_runner_setup() {
  local mode=human raw="" json
  if [[ ${1:-} == --json ]]; then
    mode="json"
    shift
  fi
  case "${1:-}" in
    -h | --help)
      __cog_plan_queue_runner_setup_usage
      return 0
      ;;
  esac
  raw="${1:-}"
  json="$(__cog_plan_queue_runner_setup_build_json "$raw")"
  if [[ $mode == json || ${COG_UI_JSON:-false} == true ]]; then
    cog::fn::json_emit "$__cog_plan_queue_runner_setup_self_check" "$json"
  else
    cog::fn::ui_data "RUN_DIR=$(jq -r '.run_dir' <<<"$json")"
  fi
}
