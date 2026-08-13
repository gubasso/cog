# shellcheck shell=bash
: 'desc: Parse gc commit result lines.'

__cog_gc_commit_parse_self_check='(.ok == true) and (.empty|type=="boolean") and (.commits|type=="array")'

__cog_gc_commit_parse_usage() {
  cog::fn::ui_data "Usage: cog gc-commit-parse <gc-out-file> [--json]"
}

__cog_gc_commit_parse_line_json() {
  local line="$1" rest sha repo=""
  rest="${line#* }"
  sha="${rest%% *}"
  [[ $line == *" repo="* ]] && repo="${line#* repo=}"
  jq -cn --arg repo "$repo" --arg sha "$sha" --arg line "$line" \
    '{repo: $repo, sha: $sha, line: $line}'
}

__cog_gc_commit_parse_build_json() {
  local file="$1" line
  [[ -f $file ]] || cog::fn::error_raise "InputNotFound" \
    "commit output file not found" "path: ${file}" "" "check the output path"
  local -a ok_lines=() failed_lines=() objs=()
  local empty=false
  while IFS= read -r line || [[ -n $line ]]; do
    case "$line" in
      "COMMIT_OK empty") empty=true ;;
      "COMMIT_OK "* | "COMMIT_PUSH_OK "*) ok_lines+=("$line") ;;
      "COMMIT_FAILED "* | "COMMIT_PUSH_FAILED "*) failed_lines+=("$line") ;;
    esac
  done <"$file"

  ((${#ok_lines[@]} + ${#failed_lines[@]} > 0)) || [[ $empty == true ]] || cog::fn::error_raise "InvalidInput" \
    "missing COMMIT_* line" "path: ${file}" "" "check the gc output"
  if ((${#failed_lines[@]} > 0)); then
    cog::fn::error_raise "InvalidInput" \
      "gc commit failed" "line: ${failed_lines[*]}" "" "inspect the gc output"
  fi

  for line in "${ok_lines[@]}"; do
    objs+=("$(__cog_gc_commit_parse_line_json "$line")")
  done
  jq -n --argjson empty "$empty" --argjson commits "$(printf '%s\n' "${objs[@]}" | jq -s .)" \
    '{ok: true, empty: $empty, commits: $commits}'
}

cog::cmd::gc_commit_parse() {
  local mode=human file="" json
  while (($# > 0)); do
    case "$1" in
      -h | --help)
        __cog_gc_commit_parse_usage
        return 0
        ;;
      --json)
        mode="json"
        shift
        ;;
      -*)
        cog::fn::error_raise "InvalidInput" \
          "unknown parse-commit option" "option: $1" "" "run 'cog gc-commit-parse --help'"
        ;;
      *)
        [[ -z $file ]] || cog::fn::error_raise "TooManyArguments" \
          "too many parse-commit files" "argument: $1" "" "run 'cog gc-commit-parse --help'"
        file="$1"
        shift
        ;;
    esac
  done
  [[ -n $file ]] || cog::fn::error_raise "MissingArgument" \
    "missing commit output file" "usage: cog gc-commit-parse <gc-out-file> [--json]" "" \
    "run 'cog gc-commit-parse --help'"
  json="$(__cog_gc_commit_parse_build_json "$file")"
  if [[ $mode == json || ${COG_UI_JSON:-false} == true ]]; then
    cog::fn::json_emit "$__cog_gc_commit_parse_self_check" "$json"
  else
    jq -r '.commits[] | "COMMIT_SHA=" + .sha + (if .repo == "" then "" else " repo=" + .repo end)' <<<"$json"
  fi
}
