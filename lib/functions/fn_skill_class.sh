# shellcheck shell=bash

# Skill-class contract surface (ADR-0016 / DP11). The data SoT lives at
# data/skill-class/contracts.yaml and declares, per governed class, the required
# and forbidden markers, the plan-mode-gate requirement, and the tier basis. This
# helper composes the existing cog::fn::skill::* facet predicates into one positive
# class-membership assertion; it never duplicates their logic.

cog::fn::skill_class::data_path() {
  local override="${COG_SKILL_CLASS_DATA:-}"
  if [[ -n $override ]]; then
    printf '%s\n' "$override"
    return 0
  fi
  cog::fn::data::path "skill-class"
}

cog::fn::skill_class::data_json() {
  local path="${1:-}"
  [[ -n $path ]] || path="$(cog::fn::skill_class::data_path)"
  [[ -e $path ]] || cog::fn::error_raise "InputNotFound" \
    "skill-class contract data not found" "path: ${path}" "" "check data/skill-class"
  cog::fn::data::load_dir "$path"
}

cog::fn::skill_class::governed_classes() {
  printf '%s\n' plan review review-plan executor runner bootstrap
}

cog::fn::skill_class::is_governed_class() {
  case "${1:-}" in
    plan | review | review-plan | executor | runner | bootstrap) return 0 ;;
    *) return 1 ;;
  esac
}

cog::fn::skill_class::list_json() {
  local data
  data="$(cog::fn::skill_class::data_json)"
  jq -n --argjson classes "$(jq -c '.skill_classes' <<<"$data")" \
    '{schema: "cog.skill-class.list.v1", ok: true,
      classes: ($classes | to_entries | map({class: .key, summary: .value.summary,
        plan_mode_gate: .value.plan_mode_gate, required_markers: .value.required_markers,
        forbidden_markers: .value.forbidden_markers}))}'
}

cog::fn::skill_class::show_json() {
  local class="${1:-}" data contract
  cog::fn::skill_class::is_governed_class "$class" || cog::fn::error_raise "InvalidInput" \
    "unknown skill class" "class: ${class}" "expected plan|review|review-plan|executor|runner|bootstrap" \
    "run 'cog skill-class list'"
  data="$(cog::fn::skill_class::data_json)"
  contract="$(jq -c --arg c "$class" '.skill_classes[$c]' <<<"$data")"
  [[ $contract != null ]] || cog::fn::error_raise "InputNotFound" \
    "skill class has no contract entry" "class: ${class}" "" "add it to data/skill-class/contracts.yaml"
  jq -n --arg class "$class" --argjson contract "$contract" \
    '{schema: "cog.skill-class.show.v1", ok: true, class: $class, contract: $contract}'
}

# True when an HTML-comment marker whose inner token is $2 is present in file $1.
# Internal whitespace in the token is matched flexibly (e.g. "cog-skill: plan-emitter").
cog::fn::skill_class::has_marker() {
  local file="$1" token="$2" re
  re="$(printf '%s' "$token" | sed 's/[[:space:]][[:space:]]*/[[:space:]]*/g')"
  grep -qE "<!--[[:space:]]*${re}[[:space:]]*-->" "$file"
}

# Assert a skill's prefix class carries every required prerequisite and no
# prohibition. Emits cog.skill-class.check.v1 with class, ok, missing[],
# forbidden_present[], and the resolved tier. Claude-only facets (plan-mode gate,
# Claude tier) mirror the facet rules' runtime gating; an `other`-class skill is
# ungoverned and passes.
cog::fn::skill_class::check_json() {
  local file="$1" name runtime class data contract gate_req model effort expected actual
  [[ -r $file && -f $file ]] || cog::fn::error_raise "InputUnreadable" \
    "skill file is not readable" "path: ${file}" "" "pass a readable SKILL.md"
  name="$(cog::fn::skill::frontmatter_name "$file")"
  runtime="$(cog::fn::skill::runtime_for_path "$file")"
  class="$(cog::fn::skill::classify_prefix "$name")"

  local -a missing=() forbidden_present=()
  local tier_expected="exempt" tier_actual="" tier_ok=true

  if cog::fn::skill_class::is_governed_class "$class"; then
    data="$(cog::fn::skill_class::data_json)"
    contract="$(jq -c --arg c "$class" '.skill_classes[$c]' <<<"$data")"
    gate_req="$(jq -r '.plan_mode_gate' <<<"$contract")"

    # Required markers.
    local m
    while IFS= read -r m; do
      [[ -n $m ]] || continue
      cog::fn::skill_class::has_marker "$file" "$m" || missing+=("marker:${m}")
    done < <(jq -r '.required_markers[]?' <<<"$contract")

    # Forbidden markers.
    while IFS= read -r m; do
      [[ -n $m ]] || continue
      cog::fn::skill_class::has_marker "$file" "$m" && forbidden_present+=("marker:${m}")
    done < <(jq -r '.forbidden_markers[]?' <<<"$contract")

    # Plan-mode gate (Claude runtime only; Codex has no Claude plan mode).
    if [[ $runtime == claude ]]; then
      if [[ $gate_req == required ]] && ! cog::fn::skill::has_plan_mode_gate "$file"; then
        missing+=("plan-mode-gate")
      elif [[ $gate_req == forbidden ]] && cog::fn::skill::has_plan_mode_gate "$file"; then
        forbidden_present+=("plan-mode-gate")
      fi

      # Tier (Claude registry/prefix expectation).
      expected="$(cog::fn::skill::expected_tier "$name")"
      tier_expected="$expected"
      if [[ $expected != exempt ]]; then
        model="$(cog::fn::skill::frontmatter_value "$file" model)"
        effort="$(cog::fn::skill::frontmatter_value "$file" effort)"
        actual="$(cog::fn::skill::tier_for_frontmatter "$model" "$effort")"
        tier_actual="$actual"
        [[ $actual == "$expected" ]] || {
          tier_ok=false
          missing+=("tier:${expected}")
        }
      fi
    fi
  fi

  local ok=true
  { ((${#missing[@]} == 0)) && ((${#forbidden_present[@]} == 0)); } || ok=false

  jq -n \
    --arg schema "cog.skill-class.check.v1" \
    --arg file "$file" \
    --arg skill "$name" \
    --arg runtime "$runtime" \
    --arg class "$class" \
    --argjson ok "$ok" \
    --argjson governed "$(cog::fn::skill_class::is_governed_class "$class" && printf true || printf false)" \
    --argjson missing "$(cog::fn::skill::json_string_array "${missing[@]}")" \
    --argjson forbidden_present "$(cog::fn::skill::json_string_array "${forbidden_present[@]}")" \
    --arg tier_expected "$tier_expected" \
    --arg tier_actual "$tier_actual" \
    --argjson tier_ok "$tier_ok" \
    '{schema: $schema, ok: $ok, file: $file, skill: $skill, runtime: $runtime,
      class: $class, governed: $governed, missing: $missing,
      forbidden_present: $forbidden_present,
      tier: {expected: $tier_expected, actual: $tier_actual, ok: $tier_ok}}'
}
