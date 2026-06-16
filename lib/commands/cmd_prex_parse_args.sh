# shellcheck shell=bash
: 'desc: Parse prex arguments into run state.'

__cog_prex_parse_args_self_check='(.mode|type=="string") and (.tsk_impl|type=="number") and (.tsk_id|type=="string") and (.task_file|type=="string")'

__cog_prex_parse_args_usage() {
  cog::fn::ui_data "Usage: cog prex-parse-args [--json] <run-dir> [arguments-string]"
}

__cog_prex_parse_args_parse() {
  local raw="$1" out_mode="$2" out_impl="$3" out_id="$4" out_task="$5"
  local parsed_mode=manual parsed_impl=0 parsed_id=""
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
      -t | --tsk-impl)
        parsed_impl=1
        shift
        if [[ $# -gt 0 && ${1#-} == "$1" && -n $1 ]]; then
          parsed_id="$1"
          shift
        fi
        ;;
      -*)
        cog::fn::error_raise_with_exit 2 "InvalidInput" \
          "unknown prex flag" "option: $1" "" "expected -a, --auto, -ar, --auto-review, -t, or --tsk-impl"
        ;;
      *)
        break
        ;;
    esac
  done
  printf -v "$out_mode" '%s' "$parsed_mode"
  printf -v "$out_impl" '%s' "$parsed_impl"
  printf -v "$out_id" '%s' "$parsed_id"
  printf -v "$out_task" '%s' "$*"
}

__cog_prex_parse_args_build_json() {
  local run_dir="$1" raw="$2" mode tsk_impl tsk_id task task_file
  [[ -d $run_dir ]] || cog::fn::error_raise "InputNotFound" \
    "prex run directory not found" "path: ${run_dir}" "" "check the run directory"
  __cog_prex_parse_args_parse "$raw" mode tsk_impl tsk_id task
  printf '%s\n' "$mode" >"${run_dir}/mode" || cog::fn::error_raise "JsonWriteFailed" \
    "could not write prex mode" "path: ${run_dir}/mode" "" "check run directory permissions"
  printf '%d:%s\n' "$tsk_impl" "$tsk_id" >"${run_dir}/tsk-impl" || cog::fn::error_raise "JsonWriteFailed" \
    "could not write tsk state" "path: ${run_dir}/tsk-impl" "" "check run directory permissions"
  task_file="${run_dir}/task.txt"
  printf '%s\n' "$task" >"$task_file" || cog::fn::error_raise "JsonWriteFailed" \
    "could not write task text" "path: ${task_file}" "" "check run directory permissions"
  jq -n \
    --arg mode "$mode" \
    --argjson tsk_impl "$tsk_impl" \
    --arg tsk_id "$tsk_id" \
    --arg task_file "$task_file" \
    '{mode: $mode, tsk_impl: $tsk_impl, tsk_id: $tsk_id, task_file: $task_file}'
}

cog::cmd::prex_parse_args() {
  local mode=human run_dir="" raw="" json
  if [[ ${1:-} == --json ]]; then
    mode="json"
    shift
  fi
  case "${1:-}" in
    -h | --help)
      __cog_prex_parse_args_usage
      return 0
      ;;
  esac
  [[ $# -ge 1 && -n ${1:-} ]] || cog::fn::error_raise "MissingArgument" \
    "missing prex run directory" "usage: cog prex-parse-args [--json] <run-dir> [arguments-string]" "" \
    "run 'cog prex-parse-args --help'"
  run_dir="$1"
  raw="${2:-}"
  json="$(__cog_prex_parse_args_build_json "$run_dir" "$raw")"
  if [[ $mode == json || ${COG_UI_JSON:-false} == true ]]; then
    cog::fn::json_emit "$__cog_prex_parse_args_self_check" "$json"
  else
    cog::fn::ui_data "MODE=$(jq -r '.mode' <<<"$json")"
    cog::fn::ui_data "TSK_IMPL=$(jq -r '.tsk_impl' <<<"$json")"
    cog::fn::ui_data "TSK_ID=$(jq -r '.tsk_id' <<<"$json")"
  fi
}
