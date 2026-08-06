# shellcheck shell=bash
: 'desc: Drive the recursive round right-sizing queue.'

# Deterministic control flow for the ADR-0013 recursive round right-sizing loop
# (refined by ADR-0013). cog owns the queue and every control decision; the
# caller supplies only worker judgment (grade, split verdict) through the verbs.

__cog_round_rightsize_pending_check='(.schema=="cog.round-rightsize.pending.v1") and (.ok|type=="boolean") and (.terminal|type=="boolean") and (.awaiting_grade|type=="array") and (.awaiting_split|type=="array")'
__cog_round_rightsize_grade_check='(.schema=="cog.round-rightsize.record-grade.v1") and (.ok|type=="boolean") and (.round_id|type=="string") and (.status|type=="string")'
__cog_round_rightsize_split_check='(.schema=="cog.round-rightsize.record-split.v1") and (.ok|type=="boolean") and (.round_id|type=="string") and (.enqueued|type=="array")'
__cog_round_rightsize_finalize_check='(.schema=="cog.round-rightsize.finalize.v1") and (.ok|type=="boolean") and (.final_rounds|type=="array")'

__cog_round_rightsize_usage() {
  cog::fn::ui_data "Usage: cog round-rightsize init --state <file> --baseline <stamped-draft.md> [--ceiling <grade>] --json"
  cog::fn::ui_data "Usage: cog round-rightsize pending --state <file> --json"
  cog::fn::ui_data "Usage: cog round-rightsize record-grade --state <file> --round-id <id> --grade <G> --score <n> --splittable true|false --report <path> --json"
  cog::fn::ui_data "Usage: cog round-rightsize record-split --state <file> --round-id <id> --split-performed true|false [--child <a.md> --child <b.md>] --json"
  cog::fn::ui_data "Usage: cog round-rightsize reopen --state <file> --round-id <id> [--reason <text>] --json"
  cog::fn::ui_data "Usage: cog round-rightsize status --state <file> --json"
  cog::fn::ui_data "Usage: cog round-rightsize finalize --state <file> --json"
}

__cog_round_rightsize_require_mode() {
  [[ -n $1 || ${COG_UI_JSON:-false} == true ]] || cog::fn::error_raise "MissingArgument" \
    "missing output mode" "usage: cog round-rightsize $2 ... --json" "" "run 'cog round-rightsize --help'"
}

__cog_round_rightsize_init() {
  local state="" baseline="" ceiling="" mode="" json
  while (($# > 0)); do
    case "$1" in
      --state)
        [[ $# -ge 2 && -n ${2:-} ]] || cog::fn::error_raise "MissingArgument" "missing state path" "option: --state" "" "run 'cog round-rightsize --help'"
        state="$2"
        shift 2
        ;;
      --baseline)
        [[ $# -ge 2 && -n ${2:-} ]] || cog::fn::error_raise "MissingArgument" "missing baseline path" "option: --baseline" "" "run 'cog round-rightsize --help'"
        baseline="$2"
        shift 2
        ;;
      --ceiling)
        [[ $# -ge 2 && -n ${2:-} ]] || cog::fn::error_raise "MissingArgument" "missing ceiling grade" "option: --ceiling" "" "run 'cog round-rightsize --help'"
        ceiling="$2"
        shift 2
        ;;
      --json)
        mode=json
        shift
        ;;
      -*) cog::fn::error_raise "InvalidInput" "unknown round-rightsize init option" "option: $1" "" "run 'cog round-rightsize --help'" ;;
      *) cog::fn::error_raise "TooManyArguments" "unexpected init argument" "argument: $1" "" "run 'cog round-rightsize --help'" ;;
    esac
  done
  __cog_round_rightsize_require_mode "$mode" init
  json="$(cog::fn::round_rightsize::init "$state" "$baseline" "$ceiling")"
  cog::fn::json_emit "$(cog::fn::round_rightsize::state_self_check)" "$json"
}

__cog_round_rightsize_pending() {
  local state="" mode="" json
  while (($# > 0)); do
    case "$1" in
      --state)
        [[ $# -ge 2 && -n ${2:-} ]] || cog::fn::error_raise "MissingArgument" "missing state path" "option: --state" "" "run 'cog round-rightsize --help'"
        state="$2"
        shift 2
        ;;
      --json)
        mode=json
        shift
        ;;
      -*) cog::fn::error_raise "InvalidInput" "unknown round-rightsize pending option" "option: $1" "" "run 'cog round-rightsize --help'" ;;
      *) cog::fn::error_raise "TooManyArguments" "unexpected pending argument" "argument: $1" "" "run 'cog round-rightsize --help'" ;;
    esac
  done
  __cog_round_rightsize_require_mode "$mode" pending
  json="$(cog::fn::round_rightsize::pending_json "$state")"
  cog::fn::json_emit "$__cog_round_rightsize_pending_check" "$json"
}

__cog_round_rightsize_record_grade() {
  local state="" id="" grade="" score="" splittable="" report="" mode="" json
  while (($# > 0)); do
    case "$1" in
      --state)
        [[ $# -ge 2 && -n ${2:-} ]] || cog::fn::error_raise "MissingArgument" "missing state path" "option: --state" "" "run 'cog round-rightsize --help'"
        state="$2"
        shift 2
        ;;
      --round-id)
        [[ $# -ge 2 && -n ${2:-} ]] || cog::fn::error_raise "MissingArgument" "missing round id" "option: --round-id" "" "run 'cog round-rightsize --help'"
        id="$2"
        shift 2
        ;;
      --grade)
        [[ $# -ge 2 && -n ${2:-} ]] || cog::fn::error_raise "MissingArgument" "missing grade" "option: --grade" "" "run 'cog round-rightsize --help'"
        grade="$2"
        shift 2
        ;;
      --score)
        [[ $# -ge 2 && -n ${2:-} ]] || cog::fn::error_raise "MissingArgument" "missing score" "option: --score" "" "run 'cog round-rightsize --help'"
        score="$2"
        shift 2
        ;;
      --splittable)
        [[ $# -ge 2 && -n ${2:-} ]] || cog::fn::error_raise "MissingArgument" "missing splittable" "option: --splittable" "" "run 'cog round-rightsize --help'"
        splittable="$2"
        shift 2
        ;;
      --report)
        [[ $# -ge 2 && -n ${2:-} ]] || cog::fn::error_raise "MissingArgument" "missing report path" "option: --report" "" "run 'cog round-rightsize --help'"
        report="$2"
        shift 2
        ;;
      --json)
        mode=json
        shift
        ;;
      -*) cog::fn::error_raise "InvalidInput" "unknown round-rightsize record-grade option" "option: $1" "" "run 'cog round-rightsize --help'" ;;
      *) cog::fn::error_raise "TooManyArguments" "unexpected record-grade argument" "argument: $1" "" "run 'cog round-rightsize --help'" ;;
    esac
  done
  [[ -n $id ]] || cog::fn::error_raise "MissingArgument" "missing round id" "option: --round-id" "" "run 'cog round-rightsize --help'"
  [[ -n $grade ]] || cog::fn::error_raise "MissingArgument" "missing grade" "option: --grade" "" "run 'cog round-rightsize --help'"
  [[ -n $score ]] || cog::fn::error_raise "MissingArgument" "missing score" "option: --score" "" "run 'cog round-rightsize --help'"
  [[ -n $splittable ]] || cog::fn::error_raise "MissingArgument" "missing splittable" "option: --splittable" "" "run 'cog round-rightsize --help'"
  [[ -n $report ]] || cog::fn::error_raise "MissingArgument" "missing report" "option: --report" "" "run 'cog round-rightsize --help'"
  __cog_round_rightsize_require_mode "$mode" record-grade
  json="$(cog::fn::round_rightsize::record_grade "$state" "$id" "$grade" "$score" "$splittable" "$report")"
  cog::fn::json_emit "$__cog_round_rightsize_grade_check" "$json"
}

__cog_round_rightsize_record_split() {
  local state="" id="" split_performed="" mode="" json
  local -a children=()
  while (($# > 0)); do
    case "$1" in
      --state)
        [[ $# -ge 2 && -n ${2:-} ]] || cog::fn::error_raise "MissingArgument" "missing state path" "option: --state" "" "run 'cog round-rightsize --help'"
        state="$2"
        shift 2
        ;;
      --round-id)
        [[ $# -ge 2 && -n ${2:-} ]] || cog::fn::error_raise "MissingArgument" "missing round id" "option: --round-id" "" "run 'cog round-rightsize --help'"
        id="$2"
        shift 2
        ;;
      --split-performed)
        [[ $# -ge 2 && -n ${2:-} ]] || cog::fn::error_raise "MissingArgument" "missing split-performed" "option: --split-performed" "" "run 'cog round-rightsize --help'"
        split_performed="$2"
        shift 2
        ;;
      --child)
        [[ $# -ge 2 && -n ${2:-} ]] || cog::fn::error_raise "MissingArgument" "missing child path" "option: --child" "" "run 'cog round-rightsize --help'"
        children+=("$2")
        shift 2
        ;;
      --json)
        mode=json
        shift
        ;;
      -*) cog::fn::error_raise "InvalidInput" "unknown round-rightsize record-split option" "option: $1" "" "run 'cog round-rightsize --help'" ;;
      *) cog::fn::error_raise "TooManyArguments" "unexpected record-split argument" "argument: $1" "" "run 'cog round-rightsize --help'" ;;
    esac
  done
  [[ -n $id ]] || cog::fn::error_raise "MissingArgument" "missing round id" "option: --round-id" "" "run 'cog round-rightsize --help'"
  [[ -n $split_performed ]] || cog::fn::error_raise "MissingArgument" "missing split-performed" "option: --split-performed" "" "run 'cog round-rightsize --help'"
  [[ ${#children[@]} -le 2 ]] || cog::fn::error_raise "InvalidInput" "a split takes exactly two children" "children: ${#children[@]}" "" "pass --child <a.md> --child <b.md>"
  __cog_round_rightsize_require_mode "$mode" record-split
  json="$(cog::fn::round_rightsize::record_split "$state" "$id" "$split_performed" "${children[0]:-}" "${children[1]:-}")"
  cog::fn::json_emit "$__cog_round_rightsize_split_check" "$json"
  jq -e '.ok == true' <<<"$json" >/dev/null || return "$EX_DATAERR"
}

__cog_round_rightsize_reopen() {
  local state="" id="" reason="" mode="" json
  while (($# > 0)); do
    case "$1" in
      --state)
        [[ $# -ge 2 && -n ${2:-} ]] || cog::fn::error_raise "MissingArgument" "missing state path" "option: --state" "" "run 'cog round-rightsize --help'"
        state="$2"
        shift 2
        ;;
      --round-id)
        [[ $# -ge 2 && -n ${2:-} ]] || cog::fn::error_raise "MissingArgument" "missing round id" "option: --round-id" "" "run 'cog round-rightsize --help'"
        id="$2"
        shift 2
        ;;
      --reason)
        [[ $# -ge 2 && -n ${2:-} ]] || cog::fn::error_raise "MissingArgument" "missing reason" "option: --reason" "" "run 'cog round-rightsize --help'"
        reason="$2"
        shift 2
        ;;
      --json)
        mode=json
        shift
        ;;
      -*) cog::fn::error_raise "InvalidInput" "unknown round-rightsize reopen option" "option: $1" "" "run 'cog round-rightsize --help'" ;;
      *) cog::fn::error_raise "TooManyArguments" "unexpected reopen argument" "argument: $1" "" "run 'cog round-rightsize --help'" ;;
    esac
  done
  [[ -n $id ]] || cog::fn::error_raise "MissingArgument" "missing round id" "option: --round-id" "" "run 'cog round-rightsize --help'"
  __cog_round_rightsize_require_mode "$mode" reopen
  json="$(cog::fn::round_rightsize::reopen "$state" "$id" "${reason:-executor-reserved}")"
  cog::fn::json_emit "$(cog::fn::round_rightsize::state_self_check)" "$json"
}

__cog_round_rightsize_status() {
  local state="" mode="" json
  while (($# > 0)); do
    case "$1" in
      --state)
        [[ $# -ge 2 && -n ${2:-} ]] || cog::fn::error_raise "MissingArgument" "missing state path" "option: --state" "" "run 'cog round-rightsize --help'"
        state="$2"
        shift 2
        ;;
      --json)
        mode=json
        shift
        ;;
      -*) cog::fn::error_raise "InvalidInput" "unknown round-rightsize status option" "option: $1" "" "run 'cog round-rightsize --help'" ;;
      *) cog::fn::error_raise "TooManyArguments" "unexpected status argument" "argument: $1" "" "run 'cog round-rightsize --help'" ;;
    esac
  done
  __cog_round_rightsize_require_mode "$mode" status
  json="$(cog::fn::round_rightsize::status_json "$state")"
  cog::fn::json_emit "$(cog::fn::round_rightsize::state_self_check)" "$json"
}

__cog_round_rightsize_finalize() {
  local state="" mode="" json
  while (($# > 0)); do
    case "$1" in
      --state)
        [[ $# -ge 2 && -n ${2:-} ]] || cog::fn::error_raise "MissingArgument" "missing state path" "option: --state" "" "run 'cog round-rightsize --help'"
        state="$2"
        shift 2
        ;;
      --json)
        mode=json
        shift
        ;;
      -*) cog::fn::error_raise "InvalidInput" "unknown round-rightsize finalize option" "option: $1" "" "run 'cog round-rightsize --help'" ;;
      *) cog::fn::error_raise "TooManyArguments" "unexpected finalize argument" "argument: $1" "" "run 'cog round-rightsize --help'" ;;
    esac
  done
  __cog_round_rightsize_require_mode "$mode" finalize
  json="$(cog::fn::round_rightsize::finalize_json "$state")"
  cog::fn::json_emit "$__cog_round_rightsize_finalize_check" "$json"
  jq -e '.ok == true' <<<"$json" >/dev/null || return "$EX_DATAERR"
}

cog::cmd::round_rightsize() {
  local mode="${1:-}"
  case "$mode" in
    -h | --help) __cog_round_rightsize_usage ;;
    init)
      shift
      __cog_round_rightsize_init "$@"
      ;;
    pending)
      shift
      __cog_round_rightsize_pending "$@"
      ;;
    record-grade)
      shift
      __cog_round_rightsize_record_grade "$@"
      ;;
    record-split)
      shift
      __cog_round_rightsize_record_split "$@"
      ;;
    reopen)
      shift
      __cog_round_rightsize_reopen "$@"
      ;;
    status)
      shift
      __cog_round_rightsize_status "$@"
      ;;
    finalize)
      shift
      __cog_round_rightsize_finalize "$@"
      ;;
    "") cog::fn::error_raise "MissingArgument" "missing round-rightsize mode" "usage: cog round-rightsize init|pending|record-grade|record-split|reopen|status|finalize" "" "run 'cog round-rightsize --help'" ;;
    *) cog::fn::error_raise "InvalidInput" "unknown round-rightsize mode" "mode: $mode" "" "run 'cog round-rightsize --help'" ;;
  esac
}
