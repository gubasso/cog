# shellcheck shell=bash
: 'desc: Stamp and list round acceptance requirement IDs.'

__cog_round_req_stamp_self_check='(.schema=="cog.round-req.stamp.v1") and (.ok|type=="boolean") and (.path|type=="string") and (.assigned|type=="array") and (.wrote|type=="boolean")'
__cog_round_req_list_self_check='(.schema=="cog.round-req.list.v1") and (.ok|type=="boolean") and (.path|type=="string") and (.criteria|type=="array") and (.stamped|type=="boolean")'

__cog_round_req_usage() {
  cog::fn::ui_data "Usage: cog round-req stamp <round-or-plan-path> [--dry-run] (--json|<out.json>)"
  cog::fn::ui_data "Usage: cog round-req list <round-path> --json"
}

__cog_round_req_emit() {
  local json="$1" check="$2" mode="$3" out="${4:-}"
  if [[ $mode == json || ${COG_UI_JSON:-false} == true ]]; then
    cog::fn::json_emit "$check" "$json"
  else
    cog::fn::json_write_fragment "$out" "$check" "$json"
  fi
}

__cog_round_req_stamp() {
  local path="" dry_run=false mode="" out="" json
  while (($# > 0)); do
    case "$1" in
      --dry-run)
        dry_run=true
        shift
        ;;
      --json)
        [[ -z $mode ]] || cog::fn::error_raise "InvalidInput" "duplicate output mode" "" "" "choose --json or an output path"
        mode=json
        shift
        ;;
      -*) cog::fn::error_raise "InvalidInput" "unknown round-req stamp option" "option: $1" "" "run 'cog round-req --help'" ;;
      *)
        if [[ -z $path ]]; then path="$1"; elif [[ -z $mode ]]; then
          out="$1"
          # shellcheck disable=SC2209
          mode=file
        else cog::fn::error_raise "TooManyArguments" "too many stamp arguments" "argument: $1" "" "run 'cog round-req --help'"; fi
        shift
        ;;
    esac
  done
  [[ -n $path ]] || cog::fn::error_raise "MissingArgument" "missing stamp path" "usage: cog round-req stamp <round-or-plan-path> [--dry-run] (--json|<out.json>)" "" "run 'cog round-req --help'"
  [[ -n $mode || ${COG_UI_JSON:-false} == true ]] || cog::fn::error_raise "MissingArgument" "missing stamp output mode" "usage: cog round-req stamp <round-or-plan-path> [--dry-run] (--json|<out.json>)" "" "run 'cog round-req --help'"
  [[ -n $mode ]] || mode=json
  json="$(cog::fn::round_req::stamp_json "$path" "$dry_run")"
  __cog_round_req_emit "$json" "$__cog_round_req_stamp_self_check" "$mode" "$out"
  jq -e '.ok == true' <<<"$json" >/dev/null || return "$EX_DATAERR"
}

__cog_round_req_list() {
  local path="" json
  while (($# > 0)); do
    case "$1" in
      --json) shift ;;
      -*) cog::fn::error_raise "InvalidInput" "unknown round-req list option" "option: $1" "" "run 'cog round-req --help'" ;;
      *)
        [[ -z $path ]] || cog::fn::error_raise "TooManyArguments" "too many list arguments" "argument: $1" "" "run 'cog round-req --help'"
        path="$1"
        shift
        ;;
    esac
  done
  [[ -n $path ]] || cog::fn::error_raise "MissingArgument" "missing list path" "usage: cog round-req list <round-path> --json" "" "run 'cog round-req --help'"
  json="$(cog::fn::round_req::list_json "$path")"
  cog::fn::json_emit "$__cog_round_req_list_self_check" "$json"
  jq -e '.ok == true' <<<"$json" >/dev/null || return "$EX_DATAERR"
}

cog::cmd::round_req() {
  local mode="${1:-}"
  case "$mode" in
    -h | --help) __cog_round_req_usage ;;
    stamp)
      shift
      __cog_round_req_stamp "$@"
      ;;
    list)
      shift
      __cog_round_req_list "$@"
      ;;
    "") cog::fn::error_raise "MissingArgument" "missing round-req mode" "usage: cog round-req stamp|list" "" "run 'cog round-req --help'" ;;
    *) cog::fn::error_raise "InvalidInput" "unknown round-req mode" "mode: $mode" "" "run 'cog round-req --help'" ;;
  esac
}
