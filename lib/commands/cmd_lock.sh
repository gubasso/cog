# shellcheck shell=bash
: 'desc: Acquire or release a workflow run lock.'

__cog_lock_usage() {
  cog::fn::ui_data "Usage: cog lock acquire <run-dir> --owner-pid <pid> [--json]"
  cog::fn::ui_data "Usage: cog lock release <lock-file>"
}

__cog_lock_acquire() {
  local run_dir="" owner_pid="" json="${COG_UI_JSON:-false}"
  local lock_file json_out

  while (($# > 0)); do
    case "$1" in
      --owner-pid)
        [[ $# -ge 2 && -n ${2:-} ]] || cog::fn::error_raise "MissingArgument" \
          "missing owner pid" "option: --owner-pid" "" "run 'cog lock --help'"
        owner_pid="$2"
        shift 2
        ;;
      --json)
        json=true
        shift
        ;;
      -*)
        cog::fn::error_raise "InvalidInput" \
          "unknown lock acquire option" "option: $1" "" "run 'cog lock --help'"
        ;;
      *)
        [[ -z $run_dir ]] || cog::fn::error_raise "TooManyArguments" \
          "too many run directories" "argument: $1" "" "run 'cog lock --help'"
        run_dir="$1"
        shift
        ;;
    esac
  done

  [[ -n $run_dir ]] || cog::fn::error_raise "MissingArgument" \
    "missing run directory" "usage: cog lock acquire <run-dir> --owner-pid <pid>" "" \
    "run 'cog lock --help'"
  [[ -n $owner_pid ]] || cog::fn::error_raise "MissingArgument" \
    "missing owner pid" "usage: cog lock acquire <run-dir> --owner-pid <pid>" "" \
    "run 'cog lock --help'"

  lock_file="$(cog::fn::rundir_lock_acquire "$run_dir" "$owner_pid")"
  if [[ $json == true ]]; then
    json_out="$(jq -cn --arg lock_file "$lock_file" '{lock_file: $lock_file}')"
    cog::fn::json_emit '(.lock_file | type == "string")' "$json_out"
  else
    cog::fn::ui_data "LOCK_FILE=${lock_file}"
  fi
}

__cog_lock_release() {
  [[ $# -eq 1 && -n ${1:-} ]] || cog::fn::error_raise "MissingArgument" \
    "missing lock file" "usage: cog lock release <lock-file>" "" "run 'cog lock --help'"
  cog::fn::rundir_lock_release "$1"
}

cog::cmd::lock() {
  local mode="${1:-}"

  case "$mode" in
    -h | --help)
      __cog_lock_usage
      ;;
    acquire)
      shift
      __cog_lock_acquire "$@"
      ;;
    release)
      shift
      __cog_lock_release "$@"
      ;;
    "")
      cog::fn::error_raise "MissingArgument" \
        "missing lock mode" "usage: cog lock acquire|release" "" "run 'cog lock --help'"
      ;;
    *)
      cog::fn::error_raise "InvalidInput" \
        "unknown lock mode" "mode: ${mode}" "" "run 'cog lock --help'"
      ;;
  esac
}
