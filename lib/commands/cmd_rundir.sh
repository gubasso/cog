# shellcheck shell=bash
: 'desc: Create a workflow run directory and optionally acquire its lock.'

__cog_rundir_usage() {
  cog::fn::ui_data "Usage: cog rundir <prefix> [--lock --owner-pid <pid>] [--json]"
  cog::fn::ui_data "Usage: cog rundir --base [--json]"
}

__cog_rundir_emit_json() {
  local run_dir="$1"
  local lock_file="$2"
  local json

  json="$(jq -cn \
    --arg run_dir "$run_dir" \
    --arg lock_file "$lock_file" \
    '{run_dir: $run_dir, lock_file: (if $lock_file == "" then null else $lock_file end)}')"
  cog::fn::json_emit '(.run_dir | type == "string") and has("lock_file")' "$json"
}

cog::cmd::rundir() {
  local prefix="" lock=false owner_pid="" base=false json="${COG_UI_JSON:-false}"
  local run_dir lock_file="" base_dir

  while (($# > 0)); do
    case "$1" in
      -h | --help)
        __cog_rundir_usage
        return 0
        ;;
      --base)
        base=true
        shift
        ;;
      --lock)
        lock=true
        shift
        ;;
      --owner-pid)
        [[ $# -ge 2 && -n ${2:-} ]] || cog::fn::error_raise "MissingArgument" \
          "missing owner pid" "option: --owner-pid" "" "run 'cog rundir --help'"
        owner_pid="$2"
        shift 2
        ;;
      --json)
        json=true
        shift
        ;;
      -*)
        cog::fn::error_raise "InvalidInput" \
          "unknown rundir option" "option: $1" "" "run 'cog rundir --help'"
        ;;
      *)
        [[ -z $prefix ]] || cog::fn::error_raise "TooManyArguments" \
          "too many rundir prefixes" "argument: $1" "" "run 'cog rundir --help'"
        prefix="$1"
        shift
        ;;
    esac
  done

  if [[ $base == true ]]; then
    [[ $lock == false && -z $owner_pid && -z $prefix ]] || cog::fn::error_raise "InvalidInput" \
      "rundir --base takes no prefix, --lock, or --owner-pid" "" "" "run 'cog rundir --help'"
    base_dir="$(cog::fn::rundir_base)"
    if [[ $json == true ]]; then
      cog::fn::json_emit '(.base | type == "string")' \
        "$(jq -cn --arg base "$base_dir" '{base: $base}')"
    else
      cog::fn::ui_data "$base_dir"
    fi
    return 0
  fi

  [[ -n $prefix ]] || cog::fn::error_raise "MissingArgument" \
    "missing run directory prefix" "usage: cog rundir <prefix>" "" "run 'cog rundir --help'"

  run_dir="$(cog::fn::rundir_create "$prefix")"
  if [[ $lock == true ]]; then
    [[ -n $owner_pid ]] || cog::fn::error_raise "MissingArgument" \
      "--lock requires --owner-pid" "usage: cog rundir <prefix> --lock --owner-pid <pid>" "" \
      "pass the owning session pid"
    lock_file="$(cog::fn::rundir_lock_acquire "$run_dir" "$owner_pid")"
  fi

  if [[ $json == true ]]; then
    __cog_rundir_emit_json "$run_dir" "$lock_file"
  else
    cog::fn::ui_data "RUN_DIR=${run_dir}"
    [[ -z $lock_file ]] || cog::fn::ui_data "LOCK_FILE=${lock_file}"
  fi
}
