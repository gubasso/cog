# shellcheck shell=bash
: 'desc: Parse a plan-queue-runner commit result.'

__cog_plan_queue_runner_parse_commit_self_check='(.commit_sha|type=="string") and (.line|type=="string")'

__cog_plan_queue_runner_parse_commit_usage() {
  cog::fn::ui_data "Usage: cog plan-queue-runner-parse-commit <gc-out-file> [--json]"
}

__cog_plan_queue_runner_parse_commit_build_json() {
  local file="$1" last sha
  [[ -f $file ]] || cog::fn::error_raise "InputNotFound" \
    "commit output file not found" "path: ${file}" "" "check the output path"
  last="$(awk 'NF{l=$0} END{print l}' "$file")"
  case "$last" in
    "COMMIT_OK "* | "COMMIT_PUSH_OK "*)
      sha="${last#* }"
      sha="${sha%% *}"
      ;;
    "COMMIT_FAILED "* | "COMMIT_PUSH_FAILED "*)
      cog::fn::error_raise "InvalidInput" \
        "gc commit failed" "line: ${last}" "" "inspect the gc output"
      ;;
    *)
      cog::fn::error_raise "InvalidInput" \
        "missing COMMIT_* line" "path: ${file}" "" "check the gc output"
      ;;
  esac
  jq -n --arg commit_sha "$sha" --arg line "$last" '{commit_sha: $commit_sha, line: $line}'
}

cog::cmd::plan_queue_runner_parse_commit() {
  local mode=human file="" json
  while (($# > 0)); do
    case "$1" in
      -h | --help)
        __cog_plan_queue_runner_parse_commit_usage
        return 0
        ;;
      --json)
        mode="json"
        shift
        ;;
      -*)
        cog::fn::error_raise "InvalidInput" \
          "unknown parse-commit option" "option: $1" "" "run 'cog plan-queue-runner-parse-commit --help'"
        ;;
      *)
        [[ -z $file ]] || cog::fn::error_raise "TooManyArguments" \
          "too many parse-commit files" "argument: $1" "" "run 'cog plan-queue-runner-parse-commit --help'"
        file="$1"
        shift
        ;;
    esac
  done
  [[ -n $file ]] || cog::fn::error_raise "MissingArgument" \
    "missing commit output file" "usage: cog plan-queue-runner-parse-commit <gc-out-file> [--json]" "" \
    "run 'cog plan-queue-runner-parse-commit --help'"
  json="$(__cog_plan_queue_runner_parse_commit_build_json "$file")"
  if [[ $mode == json || ${COG_UI_JSON:-false} == true ]]; then
    cog::fn::json_emit "$__cog_plan_queue_runner_parse_commit_self_check" "$json"
  else
    cog::fn::ui_data "COMMIT_SHA=$(jq -r '.commit_sha' <<<"$json")"
  fi
}
