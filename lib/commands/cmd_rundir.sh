# shellcheck shell=bash
: 'desc: Create a workflow run directory and optionally acquire its lock.'

__cog_rundir_usage() {
  cog::fn::ui_data "Usage: cog rundir <prefix> [--lock --owner-pid <pid>] [--json]"
  cog::fn::ui_data "Usage: cog rundir snapshot-children --prefix <prefix> --out <path> [--json]"
  cog::fn::ui_data "Usage: cog rundir locate-child --pre <pre.snap> --post <post.snap> [--proof <path>] [--json]"
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

__cog_rundir_cmd_snapshot_children() {
  local prefix="" out="" json="${COG_UI_JSON:-false}" effective_base result

  while (($# > 0)); do
    case "$1" in
      -h | --help)
        __cog_rundir_usage
        return 0
        ;;
      --prefix)
        [[ $# -ge 2 && -n ${2:-} && -z $prefix ]] || cog::fn::error_raise "MissingArgument" \
          "missing child snapshot prefix" "option: --prefix" "" "run 'cog rundir --help'"
        prefix="$2"
        shift 2
        ;;
      --out)
        [[ $# -ge 2 && -n ${2:-} && -z $out ]] || cog::fn::error_raise "MissingArgument" \
          "missing child snapshot output path" "option: --out" "" "run 'cog rundir --help'"
        out="$2"
        shift 2
        ;;
      --json)
        json=true
        shift
        ;;
      -*)
        cog::fn::error_raise "InvalidInput" \
          "unknown rundir snapshot-children option" "option: $1" "" "run 'cog rundir --help'"
        ;;
      *)
        cog::fn::error_raise "TooManyArguments" \
          "too many rundir snapshot-children arguments" "argument: $1" "" "run 'cog rundir --help'"
        ;;
    esac
  done

  [[ -n $prefix && -n $out ]] || cog::fn::error_raise "MissingArgument" \
    "missing rundir snapshot-children argument" \
    "usage: cog rundir snapshot-children --prefix <prefix> --out <path> [--json]" "" \
    "run 'cog rundir --help'"

  effective_base="$(cog::fn::rundir_base)"
  cog::fn::rundir_snapshot_children "$prefix" "$out" "$effective_base"

  if [[ $json == true ]]; then
    result="$(jq -cn --arg snapshot "$out" --arg base "$effective_base" --arg prefix "$prefix" \
      '{snapshot: $snapshot, base: $base, prefix: $prefix}')"
    cog::fn::json_emit \
      '(.snapshot | type == "string") and (.base | type == "string") and (.prefix | type == "string")' \
      "$result"
  else
    cog::fn::ui_data "RESOLVED ${out}"
  fi
}

__cog_rundir_cmd_locate_child() {
  local pre="" post="" proof="" json="${COG_UI_JSON:-false}"
  local child result

  while (($# > 0)); do
    case "$1" in
      -h | --help)
        __cog_rundir_usage
        return 0
        ;;
      --pre)
        [[ $# -ge 2 && -n ${2:-} && -z $pre ]] || cog::fn::error_raise "MissingArgument" \
          "missing pre snapshot" "option: --pre" "" "run 'cog rundir --help'"
        pre="$2"
        shift 2
        ;;
      --post)
        [[ $# -ge 2 && -n ${2:-} && -z $post ]] || cog::fn::error_raise "MissingArgument" \
          "missing post snapshot" "option: --post" "" "run 'cog rundir --help'"
        post="$2"
        shift 2
        ;;
      --proof)
        [[ $# -ge 2 && -n ${2:-} && -z $proof ]] || cog::fn::error_raise "MissingArgument" \
          "missing proof path" "option: --proof" "" "run 'cog rundir --help'"
        proof="$2"
        shift 2
        ;;
      --json)
        json=true
        shift
        ;;
      -*)
        cog::fn::error_raise "InvalidInput" \
          "unknown rundir locate-child option" "option: $1" "" "run 'cog rundir --help'"
        ;;
      *)
        cog::fn::error_raise "TooManyArguments" \
          "too many rundir locate-child arguments" "argument: $1" "" "run 'cog rundir --help'"
        ;;
    esac
  done

  [[ -n $pre && -n $post ]] || cog::fn::error_raise "MissingArgument" \
    "missing rundir locate-child argument" \
    "usage: cog rundir locate-child --pre <pre.snap> --post <post.snap> [--proof <path>] [--json]" "" \
    "run 'cog rundir --help'"

  if [[ -n $proof ]]; then
    cog::fn::rundir_snapshot_diff "$pre" "$post" "$proof"
  fi
  child="$(cog::fn::rundir_locate_child "$pre" "$post")"

  if [[ $json == true ]]; then
    result="$(jq -cn \
      --arg child_run_dir "$child" \
      --arg pre_snapshot "$pre" \
      --arg post_snapshot "$post" \
      --arg proof "$proof" \
      '{
        child_run_dir: $child_run_dir,
        pre_snapshot: $pre_snapshot,
        post_snapshot: $post_snapshot,
        proof: (if $proof == "" then null else $proof end)
      }')"
    cog::fn::json_emit \
      '(.child_run_dir | type == "string") and (.pre_snapshot | type == "string") and (.post_snapshot | type == "string") and has("proof")' \
      "$result"
  else
    cog::fn::ui_data "CHILD_RUN_DIR=${child}"
  fi
}

cog::cmd::rundir() {
  local prefix="" lock=false owner_pid="" json="${COG_UI_JSON:-false}"
  local run_dir lock_file=""

  case "${1:-}" in
    snapshot-children)
      shift
      __cog_rundir_cmd_snapshot_children "$@"
      return 0
      ;;
    locate-child)
      shift
      __cog_rundir_cmd_locate_child "$@"
      return 0
      ;;
  esac

  while (($# > 0)); do
    case "$1" in
      -h | --help)
        __cog_rundir_usage
        return 0
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
