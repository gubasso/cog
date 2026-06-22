# shellcheck shell=bash
: 'desc: Validate, sort, and severity-filter review findings JSON.'

if ! declare -F __cog_review_validate_findings_validate >/dev/null; then
  # shellcheck source=/dev/null
  source "${LIB_DIR}/commands/cmd_review_validate_findings.sh"
fi

if ! declare -F cog::fn::review::severity_rank >/dev/null; then
  # shellcheck source=/dev/null
  source "${LIB_DIR}/functions/fn_review.sh"
fi

__cog_review_normalize_findings_self_check='
(.decision | IN("request-changes","comment","approve")) and
(.summary | type == "string") and
(.findings | type == "array") and
(.strengths | type == "array")
'

__cog_review_normalize_findings_usage() {
  cog::fn::ui_data "Usage: cog review-normalize-findings --findings <file> [--severity blocking|important|nit|suggestion|question|praise] (--out <path>|--json)"
  cog::fn::ui_data "Severity keeps findings with severity_rank >= rank(min); praise is the permissive floor."
}

__cog_review_normalize_findings_rank() {
  # Single source for the severity ladder is cog::fn::review::severity_rank;
  # keep the jq 'def rank' below in lockstep with that helper.
  cog::fn::review::severity_rank "$1" || cog::fn::error_raise "InvalidInput" \
    "invalid severity" "severity: $1" "" "use blocking|important|nit|suggestion|question|praise"
}

__cog_review_normalize_findings_build_json() {
  local file="$1" severity="$2" min_rank
  __cog_review_validate_findings_validate "$file"
  min_rank="$(__cog_review_normalize_findings_rank "$severity")"
  jq --argjson min_rank "$min_rank" '
    def rank:
      if . == "blocking" then 50
      elif . == "important" then 40
      elif . == "nit" then 30
      elif . == "suggestion" then 20
      elif . == "question" then 10
      elif . == "praise" then 0
      else -1 end;
    .findings = (
      .findings
      | map(select((.severity | rank) >= $min_rank))
      | sort_by([-(.severity | rank), .file, .line_start])
    )
  ' "$file"
}

__cog_review_normalize_findings_write() {
  local out="$1" json="$2" tmp
  mkdir -p "$(dirname "$out")"
  tmp="$(mktemp "${out}.tmp.XXXXXX")" || cog::fn::error_raise "TempFileFailed" \
    "could not create temp output" "path: ${out}" "" "check output directory permissions"
  printf '%s\n' "$json" >"$tmp" || {
    rm -f "$tmp"
    cog::fn::error_raise "JsonWriteFailed" "could not write normalized findings" "path: ${tmp}" "" "check permissions"
  }
  jq -e "$__cog_review_normalize_findings_self_check" "$tmp" >/dev/null || {
    rm -f "$tmp"
    cog::fn::error_raise "InvalidJsonOutput" "normalized findings failed validation" "path: ${tmp}" "" "check command implementation"
  }
  mv "$tmp" "$out" || cog::fn::error_raise "JsonWriteFailed" \
    "could not move normalized findings into place" "path: ${out}" "" "check permissions"
  cog::fn::ui_data "RESOLVED ${out}"
}

cog::cmd::review_normalize_findings() {
  local findings="" severity=praise mode="" out="" json

  while (($# > 0)); do
    case "$1" in
      -h | --help)
        __cog_review_normalize_findings_usage
        return 0
        ;;
      --findings)
        [[ $# -ge 2 && -n ${2:-} ]] || cog::fn::error_raise "MissingArgument" \
          "missing findings file" "option: --findings" "" "run 'cog review-normalize-findings --help'"
        findings="$2"
        shift 2
        ;;
      --severity)
        [[ $# -ge 2 && -n ${2:-} ]] || cog::fn::error_raise "MissingArgument" \
          "missing severity" "option: --severity" "" "run 'cog review-normalize-findings --help'"
        severity="$2"
        __cog_review_normalize_findings_rank "$severity" >/dev/null
        shift 2
        ;;
      --out)
        [[ $# -ge 2 && -n ${2:-} ]] || cog::fn::error_raise "MissingArgument" \
          "missing output path" "option: --out" "" "run 'cog review-normalize-findings --help'"
        [[ -z $mode ]] || cog::fn::error_raise "InvalidInput" \
          "duplicate review-normalize-findings output mode" "" "" "choose either --out or --json"
        out="$2"
        mode="file"
        shift 2
        ;;
      --json)
        [[ -z $mode ]] || cog::fn::error_raise "InvalidInput" \
          "duplicate review-normalize-findings output mode" "" "" "choose either --out or --json"
        mode=json
        shift
        ;;
      -*)
        cog::fn::error_raise "InvalidInput" \
          "unknown review-normalize-findings option" "option: $1" "" "run 'cog review-normalize-findings --help'"
        ;;
      *)
        cog::fn::error_raise "TooManyArguments" \
          "too many review-normalize-findings arguments" "argument: $1" "" "run 'cog review-normalize-findings --help'"
        ;;
    esac
  done

  [[ -n $mode || ${COG_UI_JSON:-false} != true ]] || mode=json
  [[ -n $findings && -n $mode ]] || cog::fn::error_raise "MissingArgument" \
    "missing review-normalize-findings argument" \
    "usage: cog review-normalize-findings --findings <file> (--out <path>|--json)" "" \
    "run 'cog review-normalize-findings --help'"

  json="$(__cog_review_normalize_findings_build_json "$findings" "$severity")"
  if [[ $mode == json || ${COG_UI_JSON:-false} == true ]]; then
    cog::fn::json_emit "$__cog_review_normalize_findings_self_check" "$json"
  else
    __cog_review_normalize_findings_write "$out" "$json"
  fi
}
