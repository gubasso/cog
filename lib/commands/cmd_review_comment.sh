# shellcheck shell=bash
: 'desc: Plan or post PR comments for review findings.'

if ! declare -F __cog_review_validate_findings_validate >/dev/null; then
  # shellcheck source=/dev/null
  source "${LIB_DIR}/commands/cmd_review_validate_findings.sh"
fi

__cog_review_comment_self_check='
(.ok == true) and (.pr | type == "number") and (.dry_run | type == "boolean") and
(.planned_comments | type == "array")
'

__cog_review_comment_usage() {
  cog::fn::ui_data "Usage: cog review-comment --findings <json> --pr <number> [--dry-run] [--json]"
}

__cog_review_comment_body() {
  local key="$1" severity="$2" file="$3" line_start="$4" line_end="$5" headline="$6" reasoning="$7" suggestion="$8"
  jq -rn \
    --arg key "$key" \
    --arg severity "$severity" \
    --arg file "$file" \
    --arg line_start "$line_start" \
    --arg line_end "$line_end" \
    --arg headline "$headline" \
    --arg reasoning "$reasoning" \
    --arg suggestion "$suggestion" \
    '"<!-- cog-review-finding:" + $key + " -->\n" +
    "**" + $severity + "**: " + $headline + "\n\n" +
    $file + ":" + $line_start + "-" + $line_end + "\n\n" +
    $reasoning + "\n\n" +
    "Suggestion: " + $suggestion'
}

__cog_review_comment_planned_json() {
  local findings="$1" finding file line_start line_end headline severity reasoning suggestion key body
  __cog_review_validate_findings_validate "$findings"
  while IFS= read -r finding; do
    [[ -n $finding ]] || continue
    file="$(jq -r '.file' <<<"$finding")"
    line_start="$(jq -r '.line_start' <<<"$finding")"
    line_end="$(jq -r '.line_end' <<<"$finding")"
    headline="$(jq -r '.headline' <<<"$finding")"
    severity="$(jq -r '.severity' <<<"$finding")"
    reasoning="$(jq -r '.reasoning' <<<"$finding")"
    suggestion="$(jq -r '.suggestion' <<<"$finding")"
    key="$(cog::fn::review::finding_key "$file" "$line_start" "$headline")"
    body="$(__cog_review_comment_body "$key" "$severity" "$file" "$line_start" "$line_end" "$headline" "$reasoning" "$suggestion")"
    jq -cn \
      --arg key "$key" \
      --arg file "$file" \
      --argjson line_start "$line_start" \
      --argjson line_end "$line_end" \
      --arg severity "$severity" \
      --arg headline "$headline" \
      --arg body "$body" \
      '{key: $key, file: $file, line_start: $line_start, line_end: $line_end,
        severity: $severity, headline: $headline, body: $body}'
  done < <(jq -c '.findings[] | select(.severity != "praise")' "$findings") | jq -s .
}

__cog_review_comment_existing_keys_json() {
  local pr="$1"
  command -v gh >/dev/null 2>&1 || cog::fn::error_raise "MissingDependency" \
    "gh is required to post review comments" "command: gh" "" "install gh or use --dry-run"
  gh pr view "$pr" --json comments --jq '.comments[].body' \
    | sed -n 's/.*<!-- cog-review-finding:\([0-9a-f][0-9a-f]*\) -->.*/\1/p' \
    | jq -R . | jq -s 'unique'
}

__cog_review_comment_post_comments() {
  local pr="$1" comments_json="$2" comment body
  while IFS= read -r comment; do
    [[ -n $comment ]] || continue
    body="$(jq -r '.body' <<<"$comment")"
    gh pr comment "$pr" --body "$body" >/dev/null || cog::fn::error_raise "CommandFailed" \
      "gh failed to post review comment" "pr: ${pr}" "" "check gh authentication and PR number"
  done < <(jq -c '.[]' <<<"$comments_json")
}

__cog_review_comment_build_json() {
  local findings="$1" pr="$2" dry_run="$3" planned existing to_post skipped
  planned="$(__cog_review_comment_planned_json "$findings")"
  if [[ $dry_run == true ]]; then
    jq -n --argjson pr "$pr" --argjson planned "$planned" \
      '{ok: true, pr: $pr, dry_run: true, planned_comments: $planned}'
    return 0
  fi
  existing="$(__cog_review_comment_existing_keys_json "$pr")"
  to_post="$(jq -cn --argjson planned "$planned" --argjson existing "$existing" \
    '$planned | map(select(.key as $k | ($existing | index($k) | not)))')"
  skipped="$(jq -cn --argjson planned "$planned" --argjson existing "$existing" \
    '$planned | map(select(.key as $k | ($existing | index($k))))')"
  __cog_review_comment_post_comments "$pr" "$to_post"
  jq -n --argjson pr "$pr" --argjson planned "$planned" --argjson posted "$to_post" --argjson skipped "$skipped" \
    '{ok: true, pr: $pr, dry_run: false, planned_comments: $planned,
      posted: $posted, skipped_duplicates: $skipped}'
}

cog::cmd::review_comment() {
  local findings="" pr="" dry_run="${COG_UI_DRY_RUN:-${COG_DRY_RUN:-false}}" json_mode=false json

  while (($# > 0)); do
    case "$1" in
      -h | --help)
        __cog_review_comment_usage
        return 0
        ;;
      --findings)
        [[ $# -ge 2 && -n ${2:-} ]] || cog::fn::error_raise "MissingArgument" \
          "missing findings file" "option: --findings" "" "run 'cog review-comment --help'"
        findings="$2"
        shift 2
        ;;
      --pr)
        [[ $# -ge 2 && ${2:-} =~ ^[0-9]+$ ]] || cog::fn::error_raise "MissingArgument" \
          "missing PR number" "option: --pr" "" "run 'cog review-comment --help'"
        pr="$2"
        shift 2
        ;;
      --dry-run)
        dry_run=true
        shift
        ;;
      --json)
        json_mode=true
        shift
        ;;
      -*)
        cog::fn::error_raise "InvalidInput" \
          "unknown review-comment option" "option: $1" "" "run 'cog review-comment --help'"
        ;;
      *)
        cog::fn::error_raise "TooManyArguments" \
          "too many review-comment arguments" "argument: $1" "" "run 'cog review-comment --help'"
        ;;
    esac
  done

  [[ -n $findings && -n $pr ]] || cog::fn::error_raise "MissingArgument" \
    "missing review-comment argument" \
    "usage: cog review-comment --findings <json> --pr <number> [--dry-run] [--json]" "" \
    "run 'cog review-comment --help'"

  json="$(__cog_review_comment_build_json "$findings" "$pr" "$dry_run")"
  if [[ $json_mode == true || ${COG_UI_JSON:-false} == true ]]; then
    cog::fn::json_emit "$__cog_review_comment_self_check" "$json"
  else
    cog::fn::ui_data "$json"
  fi
}
