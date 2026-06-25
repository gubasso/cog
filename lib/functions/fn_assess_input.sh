# shellcheck shell=bash

# Deterministic input-quality signal extraction and verdict persistence for the
# executor input-evaluation gate. Judgment (is this a "good input" plan?) stays
# in the assess-input skill; cog owns the structural facts and the verdict
# schema so the verdict is reliable, validated, and debuggable.

__cog_assess_input_facts_self_check='(.schema=="cog.assess-input.facts.v1") and (.ok==true) and (.files|type=="array") and (.totals|type=="object")'
__cog_assess_input_verdict_self_check='(.schema=="cog.assess-input.v1") and (.ok==true) and (.route=="needs-plan" or .route=="good-input") and (.good_input|type=="boolean") and (.confidence|type=="string")'

# Canonical implementation-plan section labels. A heading line matching one of
# these is a structural signal that the input already carries a plan.
cog::fn::assess_input::canonical_sections() {
  printf '%s\n' \
    goal objective context background \
    'implementation plan' plan approach \
    steps tasks 'phase' phases round rounds \
    'acceptance criteria' verification testing \
    assumptions risks dependencies
}

cog::fn::assess_input::validate_route() {
  case "${1:-}" in
    needs-plan | good-input) return 0 ;;
    *) cog::fn::error_raise "InvalidInput" "invalid assess-input route" "route: ${1:-}" \
      "expected needs-plan or good-input" "" ;;
  esac
}

cog::fn::assess_input::validate_confidence() {
  case "${1:-}" in
    high | medium | low) return 0 ;;
    *) cog::fn::error_raise "InvalidInput" "invalid assess-input confidence" "confidence: ${1:-}" \
      "expected high, medium, or low" "" ;;
  esac
}

cog::fn::assess_input::file_facts_json() {
  local path="${1:-}" exists=false readable=false bytes=0 lines=0 label
  local -a matched=()

  [[ -n $path ]] || cog::fn::error_raise "MissingArgument" \
    "missing assess-input file path" "function: cog::fn::assess_input::file_facts_json" "" \
    "pass a file path"

  [[ -e $path ]] && exists=true
  if [[ -f $path && -r $path ]]; then
    readable=true
    bytes="$(wc -c <"$path" | tr -d '[:space:]')"
    lines="$(wc -l <"$path" | tr -d '[:space:]')"
    while IFS= read -r label; do
      if grep -iE "^#{1,6}[[:space:]]+.*${label}" "$path" >/dev/null 2>&1; then
        matched+=("$label")
      fi
    done < <(cog::fn::assess_input::canonical_sections)
  fi

  local headings_json
  headings_json="$(cog::fn::skill::json_string_array "${matched[@]}")"
  jq -cn \
    --arg path "$path" \
    --argjson exists "$exists" \
    --argjson readable "$readable" \
    --argjson bytes "${bytes:-0}" \
    --argjson lines "${lines:-0}" \
    --argjson plan_headings "$headings_json" \
    '{path: $path, exists: $exists, readable: $readable, bytes: $bytes, lines: $lines,
      plan_headings: $plan_headings, heading_count: ($plan_headings | length)}'
}

cog::fn::assess_input::facts_json() {
  local input_file="${1:-}"
  shift || true
  local input_facts='null' files_json='[]' f file_facts

  if [[ -n $input_file ]]; then
    input_facts="$(cog::fn::assess_input::file_facts_json "$input_file")"
  fi
  for f in "$@"; do
    file_facts="$(cog::fn::assess_input::file_facts_json "$f")"
    files_json="$(jq -c --argjson f "$file_facts" '. + [$f]' <<<"$files_json")"
  done

  jq -cn --argjson input "$input_facts" --argjson files "$files_json" '
    {
      schema: "cog.assess-input.facts.v1",
      ok: true,
      input: $input,
      files: $files,
      totals: {
        plan_files: ($files | length),
        readable_plan_files: ([$files[] | select(.readable)] | length),
        max_heading_count: ([(($input // {}).heading_count // 0)] + [$files[].heading_count] | max),
        total_plan_bytes: ([$files[].bytes] | add // 0)
      }
    }'
}

cog::fn::assess_input::verdict_json() {
  local route="${1:-}" confidence="${2:-}" rationale="${3:-}" signals_json="${4:-{\}}"
  local good_input=false

  cog::fn::assess_input::validate_route "$route"
  cog::fn::assess_input::validate_confidence "$confidence"
  [[ -n $rationale ]] || cog::fn::error_raise "MissingArgument" \
    "missing assess-input rationale" "function: cog::fn::assess_input::verdict_json" "" \
    "pass a one-line rationale"
  [[ $route == good-input ]] && good_input=true

  jq -cn \
    --arg route "$route" \
    --arg confidence "$confidence" \
    --arg rationale "$rationale" \
    --argjson good_input "$good_input" \
    --argjson signals "$signals_json" \
    '{schema: "cog.assess-input.v1", ok: true, route: $route, good_input: $good_input,
      confidence: $confidence, rationale: $rationale, signals: $signals}'
}

cog::fn::assess_input::facts_self_check() {
  printf '%s\n' "$__cog_assess_input_facts_self_check"
}

cog::fn::assess_input::verdict_self_check() {
  printf '%s\n' "$__cog_assess_input_verdict_self_check"
}
