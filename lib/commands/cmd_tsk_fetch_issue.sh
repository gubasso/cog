# shellcheck shell=bash
: 'desc: Fetch or create a tsk issue.'

__cog_tsk_fetch_issue_self_check='(.mode == "fetch" or .mode == "create") and ((.id|type) == "string" and .id != "") and (((.path|type) == "string") or .path == null) and (((.remote_url|type) == "string") or .remote_url == null) and (((.title|type) == "string") or .title == null) and ((.issue|type) == "string" and .issue != "")'

__cog_tsk_fetch_issue_usage() {
  cog::fn::ui_data "Usage: cog tsk-fetch-issue (--id <id>|--title <title> --body-file <file>) (<out.json>|--json)"
}

__cog_tsk_fetch_issue_nullable_string_arg() {
  if [[ -n $1 ]]; then jq -cn --arg value "$1" '$value'; else jq -cn 'null'; fi
}

__cog_tsk_fetch_issue_fetch_json() {
  local id="$1" issue path
  issue="$(tsk show "$id")"
  path="$(tsk path "$id" 2>/dev/null || true)"
  jq -n --arg mode fetch --arg id "$id" --argjson path "$(__cog_tsk_fetch_issue_nullable_string_arg "$path")" \
    --argjson remote_url null --argjson title null --arg issue "$issue" \
    '{mode: $mode, id: $id, path: $path, remote_url: $remote_url, title: $title, issue: $issue}'
}

__cog_tsk_fetch_issue_create_json() {
  local title="$1" body_file="$2" body new_output id remote_url path issue
  [[ -r $body_file && -f $body_file ]] || cog::fn::error_raise "InputUnreadable" "body file is not readable" "path: ${body_file}" "" "check the path"
  body="$(<"$body_file")"
  new_output="$(tsk new -t "$title" -d "$body")"
  id="$(printf '%s\n' "$new_output" | sed -n '1p')"
  [[ -n $id ]] || cog::fn::error_raise "InvalidInput" "tsk new did not print an issue id" "" "" "inspect tsk output"
  remote_url="$(printf '%s\n' "$new_output" | sed -n '2p')"
  path="$(tsk path "$id" 2>/dev/null || true)"
  issue="$(tsk show "$id")"
  jq -n --arg mode create --arg id "$id" --argjson path "$(__cog_tsk_fetch_issue_nullable_string_arg "$path")" \
    --argjson remote_url "$(__cog_tsk_fetch_issue_nullable_string_arg "$remote_url")" --arg title "$title" --arg issue "$issue" \
    '{mode: $mode, id: $id, path: $path, remote_url: $remote_url, title: $title, issue: $issue}'
}

__cog_tsk_fetch_issue_build_json() {
  local mode="$1" id="$2" title="$3" body_file="$4"
  __have tsk || cog::fn::error_raise "MissingRequirement" "required command not found" "command: tsk" "" "install tsk and retry"
  if [[ $mode == fetch ]]; then
    __cog_tsk_fetch_issue_fetch_json "$id"
  else
    __cog_tsk_fetch_issue_create_json "$title" "$body_file"
  fi
}

cog::cmd::tsk_fetch_issue() {
  local id="" title="" body_file="" op_mode="" out_mode="" out="" json
  while (($# > 0)); do
    case "$1" in
      -h | --help)
        __cog_tsk_fetch_issue_usage
        return 0
        ;;
      --id)
        [[ $# -ge 2 && -z $id && -n ${2:-} ]] || cog::fn::error_raise "MissingArgument" "missing tsk id" "option: --id" "" "run 'cog tsk-fetch-issue --help'"
        id="$2"
        shift 2
        ;;
      --title)
        [[ $# -ge 2 && -z $title && -n ${2:-} ]] || cog::fn::error_raise "MissingArgument" "missing tsk title" "option: --title" "" "run 'cog tsk-fetch-issue --help'"
        title="$2"
        shift 2
        ;;
      --body-file)
        [[ $# -ge 2 && -z $body_file && -n ${2:-} ]] || cog::fn::error_raise "MissingArgument" "missing body file" "option: --body-file" "" "run 'cog tsk-fetch-issue --help'"
        body_file="$2"
        shift 2
        ;;
      --json)
        [[ -z $out_mode ]] || cog::fn::error_raise "InvalidInput" "duplicate tsk-fetch-issue output mode" "" "" "choose either --json or an output path"
        out_mode=json
        shift
        ;;
      -*) cog::fn::error_raise "InvalidInput" "unknown tsk-fetch-issue option" "option: $1" "" "run 'cog tsk-fetch-issue --help'" ;;
      *)
        [[ -z $out_mode && -z $out ]] || cog::fn::error_raise "TooManyArguments" "too many tsk-fetch-issue output paths" "argument: $1" "" "run 'cog tsk-fetch-issue --help'"
        out="$1"
        out_mode="file"
        shift
        ;;
    esac
  done
  [[ -n $out_mode || ${COG_UI_JSON:-false} == true ]] || cog::fn::error_raise "MissingArgument" "missing tsk-fetch-issue output mode" "usage: cog tsk-fetch-issue ... (<out.json>|--json)" "" "run 'cog tsk-fetch-issue --help'"
  [[ -n $out_mode ]] || out_mode=json
  if [[ -n $id && -z $title && -z $body_file ]]; then
    op_mode=fetch
  elif [[ -z $id && -n $title && -n $body_file ]]; then
    op_mode=create
  else
    cog::fn::error_raise "InvalidInput" "choose exactly one tsk-fetch-issue mode" "" "pass --id or --title with --body-file" "run 'cog tsk-fetch-issue --help'"
  fi
  json="$(__cog_tsk_fetch_issue_build_json "$op_mode" "$id" "$title" "$body_file")"
  if [[ $out_mode == json || ${COG_UI_JSON:-false} == true ]]; then cog::fn::json_emit "$__cog_tsk_fetch_issue_self_check" "$json"; else cog::fn::json_write_fragment "$out" "$__cog_tsk_fetch_issue_self_check" "$json"; fi
}
