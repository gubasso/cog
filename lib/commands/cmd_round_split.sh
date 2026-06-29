# shellcheck shell=bash
: 'desc: Check split-round requirement coverage.'

__cog_round_split_coverage_self_check='(.schema=="cog.round-split.coverage.v1") and (.ok|type=="boolean") and (.parent|type=="string") and (.children|type=="array") and (.lost|type=="array") and (.coverage_ok|type=="boolean")'

__cog_round_split_usage() {
  cog::fn::ui_data "Usage: cog round-split coverage --parent <round.md> --children <child.md> <child.md> [<child.md>...] (--json | --out <path>)"
}

__cog_round_split_coverage() {
  local parent="" mode="" out="" json
  local -a children=()
  while (($# > 0)); do
    case "$1" in
      --parent)
        [[ $# -ge 2 && -n ${2:-} ]] || cog::fn::error_raise "MissingArgument" "missing parent path" "option: --parent" "" "run 'cog round-split --help'"
        parent="$2"
        shift 2
        ;;
      --children)
        shift
        while (($# > 0)) && [[ $1 != -* ]]; do
          children+=("$1")
          shift
        done
        ;;
      --out)
        [[ $# -ge 2 && -n ${2:-} ]] || cog::fn::error_raise "MissingArgument" "missing output path" "option: --out" "" "run 'cog round-split --help'"
        [[ -z $mode ]] || cog::fn::error_raise "InvalidInput" "duplicate output mode" "" "" "choose --json or --out <path>"
        out="$2"
        # shellcheck disable=SC2209
        mode=file
        shift 2
        ;;
      --json)
        [[ -z $mode ]] || cog::fn::error_raise "InvalidInput" "duplicate output mode" "" "" "choose --json or --out <path>"
        mode=json
        shift
        ;;
      -*) cog::fn::error_raise "InvalidInput" "unknown round-split coverage option" "option: $1" "" "run 'cog round-split --help'" ;;
      *) cog::fn::error_raise "InvalidInput" "unexpected round-split coverage argument" "argument: $1" "" "use --children for inputs and --out <path> for file output" ;;
    esac
  done
  [[ -n $parent && ${#children[@]} -ge 1 ]] || cog::fn::error_raise "MissingArgument" "missing coverage paths" "usage: cog round-split coverage --parent <p> --children <a> <b> [<c>...] (--json | --out <path>)" "" "run 'cog round-split --help'"
  [[ -n $mode || ${COG_UI_JSON:-false} == true ]] || cog::fn::error_raise "MissingArgument" "missing coverage output mode" "usage: cog round-split coverage --parent <p> --children <a> <b> --json" "" "run 'cog round-split --help'"
  [[ -n $mode ]] || mode=json
  json="$(cog::fn::round_split::coverage_json "$parent" "${children[@]}")"
  if [[ $mode == json || ${COG_UI_JSON:-false} == true ]]; then
    cog::fn::json_emit "$__cog_round_split_coverage_self_check" "$json"
  else
    cog::fn::json_write_fragment "$out" "$__cog_round_split_coverage_self_check" "$json"
  fi
  jq -e '.ok == true and .coverage_ok == true' <<<"$json" >/dev/null || return "$EX_DATAERR"
}

cog::cmd::round_split() {
  local mode="${1:-}"
  case "$mode" in
    -h | --help) __cog_round_split_usage ;;
    coverage)
      shift
      __cog_round_split_coverage "$@"
      ;;
    "") cog::fn::error_raise "MissingArgument" "missing round-split mode" "usage: cog round-split coverage" "" "run 'cog round-split --help'" ;;
    *) cog::fn::error_raise "InvalidInput" "unknown round-split mode" "mode: $mode" "" "run 'cog round-split --help'" ;;
  esac
}
