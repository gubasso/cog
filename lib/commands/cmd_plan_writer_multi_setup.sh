# shellcheck shell=bash
: 'desc: Parse plan-writer-multi arguments and create run state.'

__cog_plan_writer_multi_setup_self_check='(.run_dir|type=="string") and (.executor|type=="string") and (.ef|type=="string") and (.solo|type=="boolean") and (.repo_root|type=="string") and (.orientation_file|type=="string")'

__cog_plan_writer_multi_setup_usage() {
  cog::fn::ui_data "Usage: cog plan-writer-multi-setup [--json] [arguments-string]"
}

__cog_plan_writer_multi_setup_ef() {
  case "$1" in
    prex) printf '%s\n' "1.5" ;;
    single-pass) printf '%s\n' "1.0" ;;
    limited) printf '%s\n' "0.8" ;;
    *) return 1 ;;
  esac
}

__cog_plan_writer_multi_setup_parse() {
  local raw="$1"
  local out_executor="$2" out_solo="$3" out_orientation="$4"
  local parsed_executor=prex parsed_solo=false
  set -f
  # shellcheck disable=SC2086
  set -- $raw
  set +f
  while (($# > 0)); do
    case "$1" in
      --executor)
        shift
        [[ $# -gt 0 ]] || cog::fn::error_raise_with_exit 2 "MissingArgument" \
          "missing executor" "option: --executor" "" "run 'cog plan-writer-multi-setup --help'"
        parsed_executor="$1"
        shift
        ;;
      --executor=*)
        parsed_executor="${1#--executor=}"
        shift
        ;;
      --solo)
        parsed_solo=true
        shift
        ;;
      --)
        shift
        break
        ;;
      -*)
        cog::fn::error_raise_with_exit 2 "InvalidInput" \
          "unknown plan-writer-multi flag" "option: $1" "" "expected --executor or --solo"
        ;;
      *)
        break
        ;;
    esac
  done
  [[ $parsed_executor != executor-prex ]] || parsed_executor=prex
  __cog_plan_writer_multi_setup_ef "$parsed_executor" >/dev/null || cog::fn::error_raise_with_exit 2 "InvalidInput" \
    "invalid executor" "executor: ${parsed_executor}" "expected prex, executor-prex, single-pass, or limited" ""
  [[ -n ${*:-} ]] || cog::fn::error_raise_with_exit 2 "MissingArgument" \
    "orientation is required" "usage: cog plan-writer-multi-setup [--json] [arguments-string]" "" ""
  printf -v "$out_executor" '%s' "$parsed_executor"
  printf -v "$out_solo" '%s' "$parsed_solo"
  printf -v "$out_orientation" '%s' "$*"
}

__cog_plan_writer_multi_setup_build_json() {
  local raw="$1" executor solo orientation ef run_dir repo_root orientation_file
  __cog_plan_writer_multi_setup_parse "$raw" executor solo orientation
  ef="$(__cog_plan_writer_multi_setup_ef "$executor")"
  run_dir="$(cog::fn::rundir_create plan-writer-multi)"
  repo_root="$(cog::fn::git_root)"
  orientation_file="${run_dir}/orientation.txt"
  printf '%s\n' "$orientation" >"$orientation_file" || cog::fn::error_raise "JsonWriteFailed" \
    "could not write orientation" "path: ${orientation_file}" "" "check run directory permissions"

  jq -n \
    --arg run_dir "$run_dir" \
    --arg executor "$executor" \
    --arg ef "$ef" \
    --argjson solo "$solo" \
    --arg repo_root "$repo_root" \
    --arg orientation_file "$orientation_file" \
    '{run_dir: $run_dir, executor: $executor, ef: $ef, solo: $solo,
      repo_root: $repo_root, orientation_file: $orientation_file}'
}

cog::cmd::plan_writer_multi_setup() {
  local mode=human raw="" json
  if [[ ${1:-} == --json ]]; then
    mode="json"
    shift
  fi
  case "${1:-}" in
    -h | --help)
      __cog_plan_writer_multi_setup_usage
      return 0
      ;;
  esac
  raw="${1:-}"
  json="$(__cog_plan_writer_multi_setup_build_json "$raw")"
  if [[ $mode == json || ${COG_UI_JSON:-false} == true ]]; then
    cog::fn::json_emit "$__cog_plan_writer_multi_setup_self_check" "$json"
  else
    cog::fn::ui_data "RUN_DIR=$(jq -r '.run_dir' <<<"$json")"
    cog::fn::ui_data "EXECUTOR=$(jq -r '.executor' <<<"$json")"
    cog::fn::ui_data "EF=$(jq -r '.ef' <<<"$json")"
    cog::fn::ui_data "SOLO=$(jq -r 'if .solo then 1 else 0 end' <<<"$json")"
    cog::fn::ui_data "REPO_ROOT=$(jq -r '.repo_root' <<<"$json")"
    cog::fn::ui_data "ORIENTATION_FILE=$(jq -r '.orientation_file' <<<"$json")"
  fi
}
