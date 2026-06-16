# shellcheck shell=bash
: 'desc: Classify commit or push failure logs.'

__cog_gc_classify_failure_self_check='(.class | IN("setup-missing","auto-fixer","content-fix","commit-message","push-hook","push-setup-missing","push-non-hook","stuck","unknown")) and (.reason | type == "string") and (.log | type == "string") and (.matched | type == "array") and (.retryable | type == "boolean") and (.requires_judgment | type == "boolean")'

__cog_gc_classify_failure_usage() {
  cog::fn::ui_data "Usage: cog gc-classify-failure --log <file> (<out.json>|--json)"
}

cog::cmd::gc_classify_failure() {
  local log_file="" mode="" out="" json

  while (($# > 0)); do
    case "$1" in
      -h | --help)
        __cog_gc_classify_failure_usage
        return 0
        ;;
      --log)
        [[ $# -ge 2 && -n ${2:-} && -z $log_file ]] || cog::fn::error_raise "MissingArgument" \
          "missing failure log" "option: --log" "" "run 'cog gc-classify-failure --help'"
        log_file="$2"
        shift 2
        ;;
      --json)
        [[ -z $mode ]] || cog::fn::error_raise "InvalidInput" \
          "duplicate gc-classify-failure output mode" "" "" "choose either --json or an output path"
        mode="json"
        shift
        ;;
      -*)
        cog::fn::error_raise "InvalidInput" \
          "unknown gc-classify-failure option" "option: $1" "" "run 'cog gc-classify-failure --help'"
        ;;
      *)
        [[ -z $mode && -z $out ]] || cog::fn::error_raise "TooManyArguments" \
          "too many gc-classify-failure output paths" "argument: $1" "" "run 'cog gc-classify-failure --help'"
        out="$1"
        mode="file"
        shift
        ;;
    esac
  done

  [[ -n $mode || ${COG_UI_JSON:-false} != true ]] || mode=json
  [[ -n $log_file && -n $mode ]] || cog::fn::error_raise "MissingArgument" \
    "missing gc-classify-failure argument" "usage: cog gc-classify-failure --log <file> (<out.json>|--json)" "" \
    "run 'cog gc-classify-failure --help'"

  json="$(cog::fn::git_classify_failure_log "$log_file")"
  if [[ $mode == json || ${COG_UI_JSON:-false} == true ]]; then
    cog::fn::json_emit "$__cog_gc_classify_failure_self_check" "$json"
  else
    cog::fn::json_write_fragment "$out" "$__cog_gc_classify_failure_self_check" "$json"
  fi
}
