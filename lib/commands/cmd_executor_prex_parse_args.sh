# shellcheck shell=bash
: 'desc: Parse executor-prex arguments into run state.'

__cog_executor_prex_parse_args_self_check='(.mode|type=="string") and (.task_file|type=="string")'

__cog_executor_prex_parse_args_usage() {
  cog::fn::ui_data "Usage: cog executor-prex-parse-args [--json] <run-dir> [arguments-string]"
}

__cog_executor_prex_parse_args_parse() {
  local raw="$1" out_mode="$2" out_task="$3"
  local parsed_mode=manual
  set -f
  # shellcheck disable=SC2086
  set -- $raw
  set +f
  while (($# > 0)); do
    case "$1" in
      -a | --auto)
        parsed_mode=auto-approve
        shift
        ;;
      -ar | --auto-review)
        parsed_mode=auto-approve-review-loop
        shift
        ;;
      -*)
        cog::fn::error_raise_with_exit 2 "InvalidInput" \
          "unknown executor-prex flag" "option: $1" "" "expected -a, --auto, -ar, or --auto-review"
        ;;
      *)
        break
        ;;
    esac
  done
  printf -v "$out_mode" '%s' "$parsed_mode"
  printf -v "$out_task" '%s' "$*"
}

__cog_executor_prex_parse_args_build_json() {
  local run_dir="$1" raw="$2" mode task task_file
  [[ -d $run_dir ]] || cog::fn::error_raise "InputNotFound" \
    "executor-prex run directory not found" "path: ${run_dir}" "" "check the run directory"
  __cog_executor_prex_parse_args_parse "$raw" mode task
  printf '%s\n' "$mode" >"${run_dir}/mode" || cog::fn::error_raise "JsonWriteFailed" \
    "could not write executor-prex mode" "path: ${run_dir}/mode" "" "check run directory permissions"
  task_file="${run_dir}/task.txt"
  printf '%s\n' "$task" >"$task_file" || cog::fn::error_raise "JsonWriteFailed" \
    "could not write task text" "path: ${task_file}" "" "check run directory permissions"
  jq -n \
    --arg mode "$mode" \
    --arg task_file "$task_file" \
    '{mode: $mode, task_file: $task_file}'
}

cog::cmd::executor_prex_parse_args() {
  local mode=human run_dir="" raw="" json
  if [[ ${1:-} == --json ]]; then
    mode="json"
    shift
  fi
  case "${1:-}" in
    -h | --help)
      __cog_executor_prex_parse_args_usage
      return 0
      ;;
  esac
  [[ $# -ge 1 && -n ${1:-} ]] || cog::fn::error_raise "MissingArgument" \
    "missing executor-prex run directory" "usage: cog executor-prex-parse-args [--json] <run-dir> [arguments-string]" "" \
    "run 'cog executor-prex-parse-args --help'"
  run_dir="$1"
  raw="${2:-}"
  json="$(__cog_executor_prex_parse_args_build_json "$run_dir" "$raw")"
  if [[ $mode == json || ${COG_UI_JSON:-false} == true ]]; then
    cog::fn::json_emit "$__cog_executor_prex_parse_args_self_check" "$json"
  else
    cog::fn::ui_data "MODE=$(jq -r '.mode' <<<"$json")"
  fi
}
