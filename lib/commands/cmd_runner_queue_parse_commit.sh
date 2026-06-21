# shellcheck shell=bash
: 'desc: Parse a runner-queue commit result.'

__cog_runner_queue_parse_commit_self_check='(.ok == true) and (.commits|type=="array")'

__cog_runner_queue_parse_commit_usage() {
  cog::fn::ui_data "Usage: cog runner-queue-parse-commit <gc-out-file> [--json]"
}

__cog_runner_queue_parse_commit_line_json() {
  local line="$1" rest sha repo=""
  rest="${line#* }"
  sha="${rest%% *}"
  [[ $line == *" repo="* ]] && repo="${line#* repo=}"
  jq -cn --arg repo "$repo" --arg sha "$sha" --arg line "$line" \
    '{repo: $repo, sha: $sha, line: $line}'
}

__cog_runner_queue_parse_commit_build_json() {
  local file="$1" line
  [[ -f $file ]] || cog::fn::error_raise "InputNotFound" \
    "commit output file not found" "path: ${file}" "" "check the output path"
  local -a ok_lines=() failed_lines=() objs=()
  while IFS= read -r line || [[ -n $line ]]; do
    case "$line" in
      "COMMIT_OK "* | "COMMIT_PUSH_OK "*) ok_lines+=("$line") ;;
      "COMMIT_FAILED "* | "COMMIT_PUSH_FAILED "*) failed_lines+=("$line") ;;
    esac
  done <"$file"

  ((${#ok_lines[@]} + ${#failed_lines[@]} > 0)) || cog::fn::error_raise "InvalidInput" \
    "missing COMMIT_* line" "path: ${file}" "" "check the gc output"
  if ((${#failed_lines[@]} > 0)); then
    cog::fn::error_raise "InvalidInput" \
      "gc commit failed" "line: ${failed_lines[*]}" "" "inspect the gc output"
  fi

  for line in "${ok_lines[@]}"; do
    objs+=("$(__cog_runner_queue_parse_commit_line_json "$line")")
  done
  jq -n --argjson commits "$(printf '%s\n' "${objs[@]}" | jq -s .)" '{ok: true, commits: $commits}'
}

cog::cmd::runner_queue_parse_commit() {
  local mode=human file="" json
  while (($# > 0)); do
    case "$1" in
      -h | --help)
        __cog_runner_queue_parse_commit_usage
        return 0
        ;;
      --json)
        mode="json"
        shift
        ;;
      -*)
        cog::fn::error_raise "InvalidInput" \
          "unknown parse-commit option" "option: $1" "" "run 'cog runner-queue-parse-commit --help'"
        ;;
      *)
        [[ -z $file ]] || cog::fn::error_raise "TooManyArguments" \
          "too many parse-commit files" "argument: $1" "" "run 'cog runner-queue-parse-commit --help'"
        file="$1"
        shift
        ;;
    esac
  done
  [[ -n $file ]] || cog::fn::error_raise "MissingArgument" \
    "missing commit output file" "usage: cog runner-queue-parse-commit <gc-out-file> [--json]" "" \
    "run 'cog runner-queue-parse-commit --help'"
  json="$(__cog_runner_queue_parse_commit_build_json "$file")"
  if [[ $mode == json || ${COG_UI_JSON:-false} == true ]]; then
    cog::fn::json_emit "$__cog_runner_queue_parse_commit_self_check" "$json"
  else
    jq -r '.commits[] | "COMMIT_SHA=" + .sha + (if .repo == "" then "" else " repo=" + .repo end)' <<<"$json"
  fi
}
