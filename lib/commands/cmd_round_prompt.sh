# shellcheck shell=bash
: 'desc: Assemble and validate executor-stamped round prompts.'

__cog_round_prompt_build_self_check='(.schema=="cog.round-prompt.build.v1") and (.ok==true) and (.executor|type=="string") and (.round_path|type=="string") and (.prompt|type=="string")'
__cog_round_prompt_validate_self_check='(.schema=="cog.round-prompt.validate.v1") and (.ok|type=="boolean") and (.executor|type=="string") and (.known|type=="boolean") and (.reserved|type=="boolean") and (.well_formed|type=="boolean")'
__cog_round_prompt_queue_self_check='(.schema=="cog.round-prompt.queue.v1") and (.ok|type=="boolean") and (.queue_path|type=="string") and (.queue_schema|type=="string") and (.invalid|type=="array")'

__cog_round_prompt_usage() {
  cog::fn::ui_data "Usage: cog round-prompt build --executor <name> --round-path <abs> [--args <flags>] (--json | --out <path>)"
  cog::fn::ui_data "Usage: cog round-prompt validate --prompt <string> (--json | --out <path>)"
  cog::fn::ui_data "Usage: cog round-prompt validate-queue --queue <path> --schema <plans|rounds> (--json | --out <path>)"
}

# Shared emit: --json to stdout or --out <path> as a self-checked fragment.
__cog_round_prompt_emit() {
  local self_check="$1" mode="$2" out="$3" json="$4"
  if [[ $mode == json || ${COG_UI_JSON:-false} == true ]]; then
    cog::fn::json_emit "$self_check" "$json"
  else
    cog::fn::json_write_fragment "$out" "$self_check" "$json"
  fi
}

__cog_round_prompt_build() {
  local executor="" round_path="" args="" mode="" out="" json
  while (($# > 0)); do
    case "$1" in
      --executor)
        [[ $# -ge 2 && -n ${2:-} ]] || cog::fn::error_raise "MissingArgument" "missing executor name" "option: --executor" "" "run 'cog round-prompt --help'"
        executor="$2"
        shift 2
        ;;
      --round-path)
        [[ $# -ge 2 && -n ${2:-} ]] || cog::fn::error_raise "MissingArgument" "missing round path" "option: --round-path" "" "run 'cog round-prompt --help'"
        round_path="$2"
        shift 2
        ;;
      --args)
        [[ $# -ge 2 ]] || cog::fn::error_raise "MissingArgument" "missing args value" "option: --args" "" "run 'cog round-prompt --help'"
        args="$2"
        shift 2
        ;;
      --out)
        [[ $# -ge 2 && -n ${2:-} ]] || cog::fn::error_raise "MissingArgument" "missing output path" "option: --out" "" "run 'cog round-prompt --help'"
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
      -*) cog::fn::error_raise "InvalidInput" "unknown round-prompt build option" "option: $1" "" "run 'cog round-prompt --help'" ;;
      *) cog::fn::error_raise "InvalidInput" "unexpected round-prompt build argument" "argument: $1" "" "run 'cog round-prompt --help'" ;;
    esac
  done
  [[ -n $mode || ${COG_UI_JSON:-false} == true ]] || cog::fn::error_raise "MissingArgument" "missing output mode" "usage: cog round-prompt build --executor <n> --round-path <p> --json" "" "run 'cog round-prompt --help'"
  [[ -n $mode ]] || mode=json
  json="$(cog::fn::round_prompt::build_json "$executor" "$round_path" "$args")"
  __cog_round_prompt_emit "$__cog_round_prompt_build_self_check" "$mode" "$out" "$json"
}

__cog_round_prompt_validate() {
  local prompt="" mode="" out="" json have_prompt=false
  while (($# > 0)); do
    case "$1" in
      --prompt)
        [[ $# -ge 2 ]] || cog::fn::error_raise "MissingArgument" "missing prompt string" "option: --prompt" "" "run 'cog round-prompt --help'"
        prompt="$2"
        have_prompt=true
        shift 2
        ;;
      --out)
        [[ $# -ge 2 && -n ${2:-} ]] || cog::fn::error_raise "MissingArgument" "missing output path" "option: --out" "" "run 'cog round-prompt --help'"
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
      -*) cog::fn::error_raise "InvalidInput" "unknown round-prompt validate option" "option: $1" "" "run 'cog round-prompt --help'" ;;
      *) cog::fn::error_raise "InvalidInput" "unexpected round-prompt validate argument" "argument: $1" "" "run 'cog round-prompt --help'" ;;
    esac
  done
  [[ $have_prompt == true ]] || cog::fn::error_raise "MissingArgument" "missing prompt string" "usage: cog round-prompt validate --prompt <string> --json" "" "run 'cog round-prompt --help'"
  [[ -n $mode || ${COG_UI_JSON:-false} == true ]] || cog::fn::error_raise "MissingArgument" "missing output mode" "usage: cog round-prompt validate --prompt <string> --json" "" "run 'cog round-prompt --help'"
  [[ -n $mode ]] || mode=json
  json="$(cog::fn::round_prompt::validate_json "$prompt")"
  __cog_round_prompt_emit "$__cog_round_prompt_validate_self_check" "$mode" "$out" "$json"
  jq -e '.ok == true' <<<"$json" >/dev/null || return "$EX_DATAERR"
}

__cog_round_prompt_validate_queue() {
  local queue="" schema="" mode="" out="" json
  while (($# > 0)); do
    case "$1" in
      --queue)
        [[ $# -ge 2 && -n ${2:-} ]] || cog::fn::error_raise "MissingArgument" "missing queue path" "option: --queue" "" "run 'cog round-prompt --help'"
        queue="$2"
        shift 2
        ;;
      --schema)
        [[ $# -ge 2 && -n ${2:-} ]] || cog::fn::error_raise "MissingArgument" "missing schema" "option: --schema" "" "run 'cog round-prompt --help'"
        schema="$2"
        shift 2
        ;;
      --out)
        [[ $# -ge 2 && -n ${2:-} ]] || cog::fn::error_raise "MissingArgument" "missing output path" "option: --out" "" "run 'cog round-prompt --help'"
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
      -*) cog::fn::error_raise "InvalidInput" "unknown round-prompt validate-queue option" "option: $1" "" "run 'cog round-prompt --help'" ;;
      *) cog::fn::error_raise "InvalidInput" "unexpected round-prompt validate-queue argument" "argument: $1" "" "run 'cog round-prompt --help'" ;;
    esac
  done
  [[ -n $queue && -n $schema ]] || cog::fn::error_raise "MissingArgument" "missing queue or schema" "usage: cog round-prompt validate-queue --queue <path> --schema <plans|rounds> --json" "" "run 'cog round-prompt --help'"
  [[ -n $mode || ${COG_UI_JSON:-false} == true ]] || cog::fn::error_raise "MissingArgument" "missing output mode" "usage: cog round-prompt validate-queue --queue <path> --schema <plans|rounds> --json" "" "run 'cog round-prompt --help'"
  [[ -n $mode ]] || mode=json
  json="$(cog::fn::round_prompt::validate_queue_json "$queue" "$schema")"
  __cog_round_prompt_emit "$__cog_round_prompt_queue_self_check" "$mode" "$out" "$json"
  jq -e '.ok == true' <<<"$json" >/dev/null || return "$EX_DATAERR"
}

cog::cmd::round_prompt() {
  local mode="${1:-}"
  case "$mode" in
    -h | --help) __cog_round_prompt_usage ;;
    build)
      shift
      __cog_round_prompt_build "$@"
      ;;
    validate)
      shift
      __cog_round_prompt_validate "$@"
      ;;
    validate-queue)
      shift
      __cog_round_prompt_validate_queue "$@"
      ;;
    "") cog::fn::error_raise "MissingArgument" "missing round-prompt mode" "usage: cog round-prompt build|validate|validate-queue" "" "run 'cog round-prompt --help'" ;;
    *) cog::fn::error_raise "InvalidInput" "unknown round-prompt mode" "mode: $mode" "" "run 'cog round-prompt --help'" ;;
  esac
}
