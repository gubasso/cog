# shellcheck shell=bash

cog::fn::plan_complexity::valid_grade_filter() {
  jq -n '["Trivial","Low","Moderate","High","Very High","Extreme","Unscorable"]'
}

cog::fn::plan_complexity::rank_for_grade() {
  case "$1" in
    Trivial) printf '1\n' ;;
    Low) printf '2\n' ;;
    Moderate) printf '3\n' ;;
    High) printf '4\n' ;;
    "Very High") printf '5\n' ;;
    Extreme) printf '6\n' ;;
    Unscorable) printf '999\n' ;;
    *)
      cog::fn::error_raise "InvalidInput" \
        "invalid complexity grade" "grade: $1" "" \
        "use one of: Trivial, Low, Moderate, High, Very High, Extreme, Unscorable"
      ;;
  esac
}

cog::fn::plan_complexity::ceiling_grade() {
  local ceiling="${COG_PLAN_COMPLEXITY_CEILING:-Very High}"
  cog::fn::plan_complexity::rank_for_grade "$ceiling" >/dev/null
  printf '%s\n' "$ceiling"
}

cog::fn::plan_complexity::input_kind() {
  local path="$1" base content
  base="$(basename "$path")"
  content="$(sed -n '1,80p' "$path")"
  if [[ $base == README.md ]]; then
    printf 'plan\n'
  elif grep -Eq '^##[[:space:]]+Acceptance Criteria' <<<"$content"; then
    printf 'round\n'
  else
    printf 'fragment\n'
  fi
}

cog::fn::plan_complexity::extract_json() {
  local path="$1" abs input_kind named_count subsystem_count ac_count test_hits contract_hits coupling_hits
  local uncertainty_hits behavioral_hits linked_doc_count slice_quality

  [[ -r $path && -f $path ]] || cog::fn::error_raise "InputUnreadable" \
    "plan-complexity input is not readable" "path: $path" "" "pass a readable file"
  abs="$(cd -P "$(dirname "$path")" && pwd)/$(basename "$path")"
  input_kind="$(cog::fn::plan_complexity::input_kind "$path")"
  named_count="$( (grep -Eo '(^|[[:space:]])([[:alnum:]_.-]+/)+[[:alnum:]_.-]+' "$path" || true) | wc -l | tr -d ' ')"
  subsystem_count="$( (grep -Eio '\b(api|cli|database|schema|config|frontend|backend|worker|queue|auth|test|docs?|skill|command|helper|integration)\b' "$path" || true) | sort -fu | wc -l | tr -d ' ')"
  ac_count="$(awk 'BEGIN{in_ac=0} /^##[[:space:]]+Acceptance Criteria/{in_ac=1;next} /^##[[:space:]]+/{in_ac=0} in_ac && /^- \[[ xX]\]/{n++} END{print n+0}' "$path")"
  test_hits="$( (grep -Eio '\b(test|tests|bats|fixture|assert|verification|lint|pre-commit)\b' "$path" || true) | wc -l | tr -d ' ')"
  contract_hits="$( (grep -Eio '\b(contract|schema|api|interface|format|invariant|compatib|backward)\b' "$path" || true) | wc -l | tr -d ' ')"
  coupling_hits="$( (grep -Eio '\b(coupl|connascence|shared|cross-|dependency|orchestrat|consumer|producer)\b' "$path" || true) | wc -l | tr -d ' ')"
  uncertainty_hits="$( (grep -Eio '\b(unknown|uncertain|risk|maybe|assum|fallback|edge|ambiguous|irreducible)\b' "$path" || true) | wc -l | tr -d ' ')"
  behavioral_hits="$( (grep -Eio '\b(user|workflow|behavior|runtime|dispatch|fail|error|mutate|write|read-only|idempotent)\b' "$path" || true) | wc -l | tr -d ' ')"
  linked_doc_count="$( (grep -Eo '([[:alnum:]_.-]+/)+[[:alnum:]_.-]+\.md(:[0-9]+(-[0-9]+)?)?' "$path" || true) | wc -l | tr -d ' ')"
  if grep -Eiq '\b(single|one|only|narrow|focused|self-contained|isolated)\b' "$path"; then
    slice_quality=true
  else
    slice_quality=false
  fi

  jq -n \
    --arg schema "cog.plan-complexity.extract.v1" \
    --arg path "$abs" \
    --arg input_kind "$input_kind" \
    --argjson named_file_count "$named_count" \
    --argjson subsystem_count "$subsystem_count" \
    --argjson acceptance_criteria_count "$ac_count" \
    --argjson test_hits "$test_hits" \
    --argjson contract_hits "$contract_hits" \
    --argjson coupling_hits "$coupling_hits" \
    --argjson uncertainty_hits "$uncertainty_hits" \
    --argjson behavioral_hits "$behavioral_hits" \
    --argjson linked_doc_count "$linked_doc_count" \
    --argjson slice_quality "$slice_quality" \
    '{
      schema:$schema, ok:true, path:$path, input_kind:$input_kind,
      signals:{
        named_file_count:$named_file_count,
        subsystem_count:$subsystem_count,
        acceptance_criteria_count:$acceptance_criteria_count,
        test_hits:$test_hits,
        contract_hits:$contract_hits,
        coupling_hits:$coupling_hits,
        uncertainty_hits:$uncertainty_hits,
        behavioral_hits:$behavioral_hits,
        linked_doc_count:$linked_doc_count,
        slice_quality:$slice_quality
      },
      judgment_axes:["blast_radius","coupling","behavioral_surface","test_burden","uncertainty","slice_quality","operational_risk"]
    }'
}

cog::fn::plan_complexity::ceiling_json() {
  local ceiling rank valid
  ceiling="$(cog::fn::plan_complexity::ceiling_grade)"
  rank="$(cog::fn::plan_complexity::rank_for_grade "$ceiling")"
  valid="$(cog::fn::plan_complexity::valid_grade_filter)"
  jq -n --arg ceiling "$ceiling" --argjson rank "$rank" --argjson valid "$valid" \
    '{schema:"cog.plan-complexity.ceiling.v1", ok:true, ceiling:$ceiling, rank:$rank, source:(if env.COG_PLAN_COMPLEXITY_CEILING then "env" else "default" end), valid_grades:$valid}'
}

cog::fn::plan_complexity::over_ceiling_json() {
  local grade="$1" ceiling grade_rank ceiling_rank over valid
  ceiling="$(cog::fn::plan_complexity::ceiling_grade)"
  grade_rank="$(cog::fn::plan_complexity::rank_for_grade "$grade")"
  ceiling_rank="$(cog::fn::plan_complexity::rank_for_grade "$ceiling")"
  if ((grade_rank > ceiling_rank)); then over=true; else over=false; fi
  valid="$(cog::fn::plan_complexity::valid_grade_filter)"
  jq -n --arg grade "$grade" --arg ceiling "$ceiling" --argjson grade_rank "$grade_rank" \
    --argjson ceiling_rank "$ceiling_rank" --argjson over "$over" --argjson valid "$valid" \
    '{schema:"cog.plan-complexity.over-ceiling.v1", ok:true, grade:$grade, ceiling:$ceiling, grade_rank:$grade_rank, ceiling_rank:$ceiling_rank, over:$over, valid_grades:$valid}'
}
