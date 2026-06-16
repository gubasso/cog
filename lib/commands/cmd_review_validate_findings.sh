# shellcheck shell=bash
: 'desc: Validate review findings JSON.'

__cog_review_validate_findings_self_check='.ok == true and (.findings_count | type == "number")'

__cog_review_validate_findings_filter='
def nonempty: type == "string" and length > 0;
(.decision | IN("request-changes","comment","approve")) and
(.summary | nonempty) and
(.findings | type == "array") and
(.strengths | type == "array") and
all(.findings[]; (
  (.severity | IN("blocking","important","nit","suggestion","question","praise")) and
  (.file | nonempty) and
  (.line_start | type == "number") and
  (.line_end | type == "number") and
  (.line_end >= .line_start) and
  (.category | IN("security","performance","correctness","maintainability","style","test")) and
  (.headline | nonempty) and
  (.evidence | type == "string") and
  (.reasoning | type == "string") and
  (.suggestion | type == "string") and
  (.confidence | IN("high","medium","low"))
))
'

__cog_review_validate_findings_error_filter='
def nonempty: type == "string" and length > 0;
if (.decision | IN("request-changes","comment","approve") | not) then "decision must be one of request-changes|comment|approve"
elif (.summary | nonempty | not) then "summary must be a non-empty string"
elif (.findings | type != "array") then "findings must be an array"
elif (.strengths | type != "array") then "strengths must be an array"
else (
  first(
    .findings
    | to_entries[]
    | if (.value.severity | IN("blocking","important","nit","suggestion","question","praise") | not) then "findings[" + (.key|tostring) + "].severity is invalid"
      elif (.value.file | nonempty | not) then "findings[" + (.key|tostring) + "].file must be a non-empty string"
      elif (.value.line_start | type != "number") then "findings[" + (.key|tostring) + "].line_start must be a number"
      elif (.value.line_end | type != "number") then "findings[" + (.key|tostring) + "].line_end must be a number"
      elif (.value.line_end < .value.line_start) then "findings[" + (.key|tostring) + "].line_end must be >= line_start"
      elif (.value.category | IN("security","performance","correctness","maintainability","style","test") | not) then "findings[" + (.key|tostring) + "].category is invalid"
      elif (.value.headline | nonempty | not) then "findings[" + (.key|tostring) + "].headline must be a non-empty string"
      elif (.value.evidence | type != "string") then "findings[" + (.key|tostring) + "].evidence must be a string"
      elif (.value.reasoning | type != "string") then "findings[" + (.key|tostring) + "].reasoning must be a string"
      elif (.value.suggestion | type != "string") then "findings[" + (.key|tostring) + "].suggestion must be a string"
      elif (.value.confidence | IN("high","medium","low") | not) then "findings[" + (.key|tostring) + "].confidence is invalid"
      else empty
      end
  ) // "findings JSON failed validation"
) end
'

__cog_review_validate_findings_usage() {
  cog::fn::ui_data "Usage: cog review-validate-findings --findings <file> (<out.json>|--json)"
}

__cog_review_validate_findings_validate() {
  local file="$1"
  local reason
  [[ -r $file ]] || cog::fn::error_raise "InputUnreadable" \
    "findings file is not readable" "path: ${file}" "" "check the file path"
  jq -e . "$file" >/dev/null 2>&1 || cog::fn::error_raise "InvalidJsonInput" \
    "findings file is not valid JSON" "path: ${file}" "" "check the file contents"
  if ! jq -e "$__cog_review_validate_findings_filter" "$file" >/dev/null; then
    reason="$(jq -r "$__cog_review_validate_findings_error_filter" "$file" 2>/dev/null \
      || printf '%s\n' "findings JSON failed validation")"
    cog::fn::error_raise "InvalidJsonInput" \
      "$reason" "path: ${file}" "" "fix the findings JSON and retry"
  fi
}

__cog_review_validate_findings_build_json() {
  local file="$1"
  local count
  __cog_review_validate_findings_validate "$file"
  count="$(jq -r '.findings | length' "$file")"
  jq -n \
    --argjson ok true \
    --argjson findings_count "$count" \
    --arg file "$file" \
    '{ok: $ok, findings_count: $findings_count, file: $file}'
}

cog::cmd::review_validate_findings() {
  local findings_file="" mode="" out="" json

  while (($# > 0)); do
    case "$1" in
      -h | --help)
        __cog_review_validate_findings_usage
        return 0
        ;;
      --findings)
        [[ $# -ge 2 && -n ${2:-} && -z $findings_file ]] || cog::fn::error_raise "MissingArgument" \
          "missing findings file" "option: --findings" "" "run 'cog review-validate-findings --help'"
        findings_file="$2"
        shift 2
        ;;
      --json)
        [[ -z $mode ]] || cog::fn::error_raise "InvalidInput" \
          "duplicate review-validate-findings output mode" "" "" "choose either --json or an output path"
        mode="json"
        shift
        ;;
      -*)
        cog::fn::error_raise "InvalidInput" \
          "unknown review-validate-findings option" "option: $1" "" "run 'cog review-validate-findings --help'"
        ;;
      *)
        [[ -z $mode && -z $out ]] || cog::fn::error_raise "TooManyArguments" \
          "too many review-validate-findings output paths" "argument: $1" "" "run 'cog review-validate-findings --help'"
        out="$1"
        mode="file"
        shift
        ;;
    esac
  done

  [[ -n $mode || ${COG_UI_JSON:-false} != true ]] || mode=json
  [[ -n $findings_file && -n $mode ]] || cog::fn::error_raise "MissingArgument" \
    "missing review-validate-findings argument" "usage: cog review-validate-findings --findings <file> (<out.json>|--json)" "" \
    "run 'cog review-validate-findings --help'"

  json="$(__cog_review_validate_findings_build_json "$findings_file")"
  if [[ $mode == json || ${COG_UI_JSON:-false} == true ]]; then
    cog::fn::json_emit "$__cog_review_validate_findings_self_check" "$json"
  else
    cog::fn::json_write_fragment "$out" "$__cog_review_validate_findings_self_check" "$json"
  fi
}
