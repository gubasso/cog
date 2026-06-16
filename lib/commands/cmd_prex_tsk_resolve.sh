# shellcheck shell=bash
: 'desc: Resolve a tsk issue for a prex run.'

__cog_prex_tsk_resolve_self_check='(.tsk_id|type=="string") and (.body_file|type=="string")'

__cog_prex_tsk_resolve_usage() {
  cog::fn::ui_data "Usage: cog prex-tsk-resolve --run-dir <dir> [--id <id>] [--json]"
}

__cog_prex_tsk_resolve_resolve_id() {
  local run_dir="$1" id="$2" resolved
  if [[ -z $id && -f ${run_dir}/tsk-impl ]]; then
    IFS=: read -r _ id <"${run_dir}/tsk-impl" || true
  fi
  if [[ -z $id ]]; then
    if resolved="$(tsk id 2>&1)"; then
      id="$resolved"
    else
      printf 'tsk id output:\n%s\n\n' "$resolved" >&2
      cog::fn::error_raise "InvalidInput" \
        "no tsk id is associated with the current branch" "" "" \
        "pass the id explicitly or attach an issue to this branch first"
    fi
  fi
  [[ -n $id ]] || cog::fn::error_raise "InvalidInput" \
    "resolved tsk id is empty" "" "" "pass --id explicitly"
  printf '%s\n' "$id"
}

__cog_prex_tsk_resolve_build_json() {
  local run_dir="$1" id="$2" body_file err_file
  [[ -d $run_dir ]] || cog::fn::error_raise "InputNotFound" \
    "prex run directory not found" "path: ${run_dir}" "" "check the run directory"
  __have tsk || cog::fn::error_raise "MissingRequirement" \
    "required command not found" "command: tsk" "" "install tsk and retry"
  id="$(__cog_prex_tsk_resolve_resolve_id "$run_dir" "$id")"
  body_file="${run_dir}/tsk-issue.md"
  err_file="${run_dir}/tsk-issue.err"
  if ! tsk show "$id" >"$body_file" 2>"$err_file"; then
    cog::fn::error_raise "InvalidInput" \
      "tsk show failed" "id: ${id}" "stderr: ${err_file}" "inspect the tsk error"
  fi
  printf '1:%s\n' "$id" >"${run_dir}/tsk-impl" || cog::fn::error_raise "JsonWriteFailed" \
    "could not write tsk state" "path: ${run_dir}/tsk-impl" "" "check run directory permissions"
  jq -n --arg tsk_id "$id" --arg body_file "$body_file" '{tsk_id: $tsk_id, body_file: $body_file}'
}

cog::cmd::prex_tsk_resolve() {
  local run_dir="" id="" mode=human json
  while (($# > 0)); do
    case "$1" in
      -h | --help)
        __cog_prex_tsk_resolve_usage
        return 0
        ;;
      --run-dir)
        [[ $# -ge 2 && -n ${2:-} ]] || cog::fn::error_raise "MissingArgument" \
          "missing run directory" "option: --run-dir" "" "run 'cog prex-tsk-resolve --help'"
        run_dir="$2"
        shift 2
        ;;
      --id)
        [[ $# -ge 2 && -n ${2:-} ]] || cog::fn::error_raise "MissingArgument" \
          "missing tsk id" "option: --id" "" "run 'cog prex-tsk-resolve --help'"
        id="$2"
        shift 2
        ;;
      --json)
        mode="json"
        shift
        ;;
      *)
        cog::fn::error_raise "InvalidInput" \
          "unknown prex-tsk-resolve argument" "argument: $1" "" "run 'cog prex-tsk-resolve --help'"
        ;;
    esac
  done
  [[ -n $run_dir ]] || cog::fn::error_raise "MissingArgument" \
    "missing run directory" "usage: cog prex-tsk-resolve --run-dir <dir> [--id <id>] [--json]" "" \
    "run 'cog prex-tsk-resolve --help'"
  json="$(__cog_prex_tsk_resolve_build_json "$run_dir" "$id")"
  if [[ $mode == json || ${COG_UI_JSON:-false} == true ]]; then
    cog::fn::json_emit "$__cog_prex_tsk_resolve_self_check" "$json"
  else
    cog::fn::ui_data "TSK_ID=$(jq -r '.tsk_id' <<<"$json")"
    cog::fn::ui_data "TSK_BODY=$(jq -r '.body_file' <<<"$json")"
  fi
}
