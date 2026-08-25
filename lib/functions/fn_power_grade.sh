# shellcheck shell=bash

cog::fn::power_grade::matrix_path() {
  local override="${COG_POWER_GRADE_MATRIX:-}"
  if [[ -n $override ]]; then
    printf '%s\n' "$override"
    return 0
  fi
  cog::fn::data::path "power-grade/matrix"
}

cog::fn::power_grade::matrix_json() {
  local matrix_path="${1:-}"
  [[ -n $matrix_path ]] || matrix_path="$(cog::fn::power_grade::matrix_path)"
  [[ -e $matrix_path ]] || cog::fn::error_raise "InputNotFound" \
    "power grade matrix not found" "path: ${matrix_path}" "" \
    "check data/power-grade/matrix"

  cog::fn::data::load_dir "$matrix_path"
}

cog::fn::power_grade::tier_json() {
  local name="$1" matrix_path="${2:-}" matrix_json
  [[ -n $name ]] || cog::fn::error_raise "MissingArgument" \
    "missing tier name" "option: --name" "" "run 'cog power-grade --help'"
  [[ -n $matrix_path ]] || matrix_path="$(cog::fn::power_grade::matrix_path)"
  matrix_json="$(cog::fn::power_grade::matrix_json "$matrix_path")"

  jq -e -n \
    --arg schema "cog.power-grade.tier.v1" \
    --arg matrix_path "$matrix_path" \
    --arg name "$name" \
    --argjson matrix "$matrix_json" '
      def cell($id): ($matrix.model_cells | map(select(.id == $id)) | first)
        | if . == null then null else {id, model, effort, grade} end;
      ($matrix.model_tiers // [] | map(select(.name == $name)) | first) as $tier
      | {
          schema: $schema,
          ok: ($tier != null),
          matrix_path: $matrix_path,
          name: $name,
          tier: ($tier.name // null),
          use_when: ($tier.use_when // null),
          claude: (if $tier then cell($tier.claude_cell) else null end),
          codex: (if $tier then cell($tier.codex_cell) else null end)
        }'
}

# Resolve a Claude skill's expected vs actual model/effort tier. Reads the skill
# frontmatter (model/effort) and composes the skill tier helpers (fn_skill.sh).
cog::fn::power_grade::skill_tier_json() {
  local skill="$1" file="${2:-}" root name model effort expected actual source
  if [[ -z $file ]]; then
    [[ -n $skill ]] || cog::fn::error_raise "MissingArgument" \
      "missing skill identifier" "option: --skill or --file" "" "run 'cog power-grade --help'"
    root="$(realpath "${LIB_DIR}/..")"
    if [[ -f "${root}/skills/claude/${skill}/SKILL.md" ]]; then
      file="${root}/skills/claude/${skill}/SKILL.md"
    elif [[ -f "${root}/.claude/skills/${skill}/SKILL.md" ]]; then
      file="${root}/.claude/skills/${skill}/SKILL.md"
    else
      cog::fn::error_raise "InputNotFound" \
        "skill SKILL.md not found" "skill: ${skill}" "" \
        "pass --file <path> to point at the SKILL.md directly"
    fi
  fi
  [[ -f $file ]] || cog::fn::error_raise "InputNotFound" \
    "skill file not found" "path: ${file}" "" "pass a readable SKILL.md"

  name="$(cog::fn::skill::frontmatter_name "$file")"
  expected="$(cog::fn::skill::expected_tier "$name")"
  source="$(cog::fn::skill::expected_tier_source "$name")"
  model="$(cog::fn::skill::frontmatter_value "$file" model)"
  effort="$(cog::fn::skill::frontmatter_value "$file" effort)"
  actual="$(cog::fn::skill::tier_for_frontmatter "$model" "$effort")"

  jq -e -n \
    --arg schema "cog.power-grade.skill-tier.v1" \
    --arg skill "$name" \
    --arg file "$file" \
    --arg expected "$expected" \
    --arg actual "$actual" \
    --arg model "$model" \
    --arg effort "$effort" \
    --arg source "$source" '
      {
        schema: $schema,
        ok: ($expected == "exempt" or $expected == $actual),
        skill: $skill,
        file: $file,
        expected: $expected,
        actual: $actual,
        model: (if $model == "" then null else $model end),
        effort: (if $effort == "" then null else $effort end),
        reason: $source
      }'
}
