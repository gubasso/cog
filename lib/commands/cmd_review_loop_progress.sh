# shellcheck shell=bash
: 'desc: Compare review findings across loop rounds.'

if ! declare -F __cog_review_validate_findings_validate >/dev/null; then
  # shellcheck source=/dev/null
  source "${LIB_DIR}/commands/cmd_review_validate_findings.sh"
fi

__cog_review_loop_progress_self_check='
(.new | type == "array") and
(.recurring | type == "array") and
(.resolved | type == "array") and
(.churn_ratio | type == "number") and
(.counts.current | type == "number")
'

__cog_review_loop_progress_usage() {
  cog::fn::ui_data "Usage: cog review-loop-progress --current <json> --previous <json> [--json]"
}

__cog_review_loop_progress_keyed_findings_json() {
  local file="$1" finding key finding_file line headline
  __cog_review_validate_findings_validate "$file"
  while IFS= read -r finding; do
    [[ -n $finding ]] || continue
    finding_file="$(jq -r '.file' <<<"$finding")"
    line="$(jq -r '.line_start' <<<"$finding")"
    headline="$(jq -r '.headline' <<<"$finding")"
    key="$(cog::fn::review::finding_key "$finding_file" "$line" "$headline")"
    jq -c --arg key "$key" '. + {key: $key}' <<<"$finding"
  done < <(jq -c '.findings[]' "$file") | jq -s .
}

__cog_review_loop_progress_build_json() {
  local current_file="$1" previous_file="$2" current previous
  current="$(__cog_review_loop_progress_keyed_findings_json "$current_file")"
  previous="$(__cog_review_loop_progress_keyed_findings_json "$previous_file")"
  jq -n --argjson current "$current" --argjson previous "$previous" '
    def keyset($items): $items | map(.key);
    def by_new($items; $other): $items | map(select(.key as $k | (keyset($other) | index($k) | not)));
    def by_recurring($items; $other): $items | map(select(.key as $k | (keyset($other) | index($k))));
    ($current | length) as $current_count |
    ($previous | length) as $previous_count |
    (by_new($current; $previous)) as $new |
    (by_recurring($current; $previous)) as $recurring |
    (by_new($previous; $current)) as $resolved |
    (($current_count + $previous_count) | if . == 0 then 1 else . end) as $denom |
    {
      new: $new,
      recurring: $recurring,
      resolved: $resolved,
      churn_ratio: ((($new | length) + ($resolved | length)) / $denom),
      counts: {
        current: $current_count,
        previous: $previous_count,
        new: ($new | length),
        recurring: ($recurring | length),
        resolved: ($resolved | length)
      }
    }
  '
}

cog::cmd::review_loop_progress() {
  local current="" previous="" json_mode=false json

  while (($# > 0)); do
    case "$1" in
      -h | --help)
        __cog_review_loop_progress_usage
        return 0
        ;;
      --current)
        [[ $# -ge 2 && -n ${2:-} ]] || cog::fn::error_raise "MissingArgument" \
          "missing current findings" "option: --current" "" "run 'cog review-loop-progress --help'"
        current="$2"
        shift 2
        ;;
      --previous)
        [[ $# -ge 2 && -n ${2:-} ]] || cog::fn::error_raise "MissingArgument" \
          "missing previous findings" "option: --previous" "" "run 'cog review-loop-progress --help'"
        previous="$2"
        shift 2
        ;;
      --json)
        json_mode=true
        shift
        ;;
      -*)
        cog::fn::error_raise "InvalidInput" \
          "unknown review-loop-progress option" "option: $1" "" "run 'cog review-loop-progress --help'"
        ;;
      *)
        cog::fn::error_raise "TooManyArguments" \
          "too many review-loop-progress arguments" "argument: $1" "" "run 'cog review-loop-progress --help'"
        ;;
    esac
  done

  [[ -n $current && -n $previous ]] || cog::fn::error_raise "MissingArgument" \
    "missing review-loop-progress argument" \
    "usage: cog review-loop-progress --current <json> --previous <json> [--json]" "" \
    "run 'cog review-loop-progress --help'"

  json="$(__cog_review_loop_progress_build_json "$current" "$previous")"
  if [[ $json_mode == true || ${COG_UI_JSON:-false} == true ]]; then
    cog::fn::json_emit "$__cog_review_loop_progress_self_check" "$json"
  else
    cog::fn::ui_data "$json"
  fi
}
