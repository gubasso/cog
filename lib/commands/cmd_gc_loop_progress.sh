# shellcheck shell=bash
: 'desc: Compare commit failure reports across round-loop rounds.'

__cog_gc_loop_progress_self_check='
(.new | type == "array") and
(.recurring | type == "array") and
(.resolved | type == "array") and
(.churn_ratio | type == "number") and
(.counts.current | type == "number")
'

__cog_gc_loop_progress_usage() {
  cog::fn::ui_data "Usage: cog gc-loop-progress --current <log> --previous <log> [--json]"
}

cog::cmd::gc_loop_progress() {
  local current="" previous="" json_mode=false json

  while (($# > 0)); do
    case "$1" in
      -h | --help)
        __cog_gc_loop_progress_usage
        return 0
        ;;
      --current)
        [[ $# -ge 2 && -n ${2:-} ]] || cog::fn::error_raise "MissingArgument" \
          "missing current report" "option: --current" "" "run 'cog gc-loop-progress --help'"
        current="$2"
        shift 2
        ;;
      --previous)
        [[ $# -ge 2 && -n ${2:-} ]] || cog::fn::error_raise "MissingArgument" \
          "missing previous report" "option: --previous" "" "run 'cog gc-loop-progress --help'"
        previous="$2"
        shift 2
        ;;
      --json)
        json_mode=true
        shift
        ;;
      -*)
        cog::fn::error_raise "InvalidInput" \
          "unknown gc-loop-progress option" "option: $1" "" "run 'cog gc-loop-progress --help'"
        ;;
      *)
        cog::fn::error_raise "TooManyArguments" \
          "too many gc-loop-progress arguments" "argument: $1" "" "run 'cog gc-loop-progress --help'"
        ;;
    esac
  done

  [[ -n $current && -n $previous ]] || cog::fn::error_raise "MissingArgument" \
    "missing gc-loop-progress argument" \
    "usage: cog gc-loop-progress --current <log> --previous <log> [--json]" "" \
    "run 'cog gc-loop-progress --help'"

  json="$(cog::fn::git_loop_progress "$current" "$previous")"
  if [[ $json_mode == true || ${COG_UI_JSON:-false} == true ]]; then
    cog::fn::json_emit "$__cog_gc_loop_progress_self_check" "$json"
  else
    cog::fn::ui_data "$json"
  fi
}
