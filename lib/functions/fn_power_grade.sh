# shellcheck shell=bash

cog::fn::power_grade::matrix_path() {
  local override="${COG_POWER_GRADE_MATRIX:-}"
  if [[ -n $override ]]; then
    printf '%s\n' "$override"
    return 0
  fi
  realpath "${LIB_DIR}/../docs/reference/power-grade-matrix.toml"
}

cog::fn::power_grade::matrix_json() {
  local matrix_path="${1:-}"
  [[ -n $matrix_path ]] || matrix_path="$(cog::fn::power_grade::matrix_path)"
  [[ -f $matrix_path ]] || cog::fn::error_raise "InputNotFound" \
    "power grade matrix not found" "path: ${matrix_path}" "" \
    "check docs/reference/power-grade-matrix.toml"

  cog::fn::toml::json "$matrix_path"
}

cog::fn::power_grade::allowlist_path() {
  local override="${COG_POWER_GRADE_ALLOWLIST:-}"
  if [[ -n $override ]]; then
    printf '%s\n' "$override"
    return 0
  fi
  realpath "${LIB_DIR}/../docs/reference/power-grade-source-allowlist.toml"
}

cog::fn::power_grade::allowlist_json() {
  local allowlist_path="${1:-}"
  [[ -n $allowlist_path ]] || allowlist_path="$(cog::fn::power_grade::allowlist_path)"
  [[ -f $allowlist_path ]] || cog::fn::error_raise "InputNotFound" \
    "power grade source allowlist not found" "path: ${allowlist_path}" "" \
    "check docs/reference/power-grade-source-allowlist.toml"

  cog::fn::toml::json "$allowlist_path"
}

cog::fn::power_grade::validate_json() {
  local matrix_path="${1:-}" allowlist_path matrix_json allowlist_json
  [[ -n $matrix_path ]] || matrix_path="$(cog::fn::power_grade::matrix_path)"
  matrix_json="$(cog::fn::power_grade::matrix_json "$matrix_path")"
  allowlist_path="$(cog::fn::power_grade::allowlist_path)"
  allowlist_json="$(cog::fn::power_grade::allowlist_json "$allowlist_path")"

  jq -n \
    --arg schema "cog.power-grade.validate.v1" \
    --arg matrix_path "$matrix_path" \
    --arg allowlist_path "$allowlist_path" \
    --argjson matrix "$matrix_json" \
    --argjson allowlist "$allowlist_json" '
      def required_keys: ($matrix.validation.required_profile_keys // []);
      def missing_keys($p): required_keys | map(select($p[.] == null));
      def allowlist_tiers:
        ($allowlist.sources // [])
        | map({key: .id, value: .tier})
        | from_entries;
      def profile_source_ids($p): ($p.benchmark_source_ids // []);
      def required_errors:
        $matrix.profiles
        | to_entries
        | map({index: .key, id: (.value.id // null), missing: missing_keys(.value)})
        | map(select(.missing | length > 0))
        | map({kind: "missing_required_profile_keys", profile_index: .index, profile_id: .id, missing: .missing});
      def duplicate_errors($field):
        ($matrix.profiles | map(.[$field]) | group_by(.) | map(select(length > 1) | .[0])) as $dupes
        | $dupes
        | map({kind: ("duplicate_profile_" + $field), value: .});
      def grade_errors:
        $matrix.profiles
        | map(select((.grade | type) != "number" or .grade < $matrix.scale.min or .grade > $matrix.scale.max)
          | {kind: "profile_grade_out_of_scale", profile_id: (.id // null), grade: (.grade // null)});
      def source_errors:
        $matrix.profiles
        | map(select((.source_refs | type) != "array" or (.source_refs | length) == 0)
          | {kind: "missing_source_refs", profile_id: (.id // null)});
      def unknown_source_errors:
        allowlist_tiers as $tiers
        | $matrix.profiles
        | to_entries
        | map(. as $entry
            | (profile_source_ids($entry.value) | map(select(($tiers[.] // null) == null))) as $unknown
            | select(($unknown | length) > 0)
            | {kind: "unknown_source_id", profile_index: .key, profile_id: (.value.id // null), source_ids: $unknown});
      def named_profile_errors:
        ($matrix.profiles | map(.id)) as $ids
        | ($matrix.named_profiles // [])
        | map(select((.claude_profile as $c | $ids | index($c) | not) or
                     (.codex_profile as $g | $ids | index($g) | not))
          | {kind: "named_profile_unknown_reference", name: (.name // null),
             claude_profile: (.claude_profile // null), codex_profile: (.codex_profile // null)});
      def needs_verification_warnings:
        $matrix.profiles
        | map(select(.evidence_status == "needs_verification")
          | {kind: "needs_verification", profile_id: .id, executable: .executable, caveats: .caveats});
      def tier3_source_warnings:
        allowlist_tiers as $tiers
        | $matrix.profiles
        | map(. as $profile
            | (profile_source_ids($profile) | map(select(($tiers[.] // null) == 3))) as $tier3
            | select(($tier3 | length) > 0)
            | {kind: "tier3_source_cited", profile_id: (.id // null), source_ids: $tier3});
      def sourced_without_allowlisted_source_warnings:
        allowlist_tiers as $tiers
        | $matrix.profiles
        | map(select((.evidence_status != "needs_verification") and
                     ((profile_source_ids(.) | map(select((($tiers[.] // 999) <= 2))) | length) == 0))
            | {kind: "sourced_without_allowlisted_source", profile_id: (.id // null),
               benchmark_source_ids: profile_source_ids(.)});
      def warnings:
        needs_verification_warnings + tier3_source_warnings + sourced_without_allowlisted_source_warnings;

      (required_errors + duplicate_errors("id") + duplicate_errors("slug") + grade_errors + source_errors + unknown_source_errors + named_profile_errors) as $errors
      | {
          schema: $schema,
          ok: ($errors | length == 0),
          matrix_path: $matrix_path,
          allowlist_path: $allowlist_path,
          profile_count: ($matrix.profiles | length),
          named_profile_count: (($matrix.named_profiles // []) | length),
          scale: $matrix.scale,
          validation: $matrix.validation,
          errors: $errors,
          warnings: warnings
        }'
}

cog::fn::power_grade::cell_json() {
  local model="$1" effort="$2" matrix_path="${3:-}" matrix_json
  [[ -n $model && -n $effort ]] || cog::fn::error_raise "MissingArgument" \
    "missing power-grade cell argument" "model: ${model}; effort: ${effort}" "" \
    "run 'cog power-grade --help'"
  [[ -n $matrix_path ]] || matrix_path="$(cog::fn::power_grade::matrix_path)"
  matrix_json="$(cog::fn::power_grade::matrix_json "$matrix_path")"

  jq -e -n \
    --arg schema "cog.power-grade.cell.v1" \
    --arg matrix_path "$matrix_path" \
    --arg model "$model" \
    --arg effort "$effort" \
    --argjson matrix "$matrix_json" '
      ($matrix.profiles | map(select(.model == $model and .effort == $effort)) | first) as $profile
      | {
          schema: $schema,
          ok: ($profile != null),
          matrix_path: $matrix_path,
          model: $model,
          effort: $effort,
          profile: $profile
        }'
}

cog::fn::power_grade::profile_json() {
  local name="$1" matrix_path="${2:-}" matrix_json
  [[ -n $name ]] || cog::fn::error_raise "MissingArgument" \
    "missing named-profile name" "option: --name" "" "run 'cog power-grade --help'"
  [[ -n $matrix_path ]] || matrix_path="$(cog::fn::power_grade::matrix_path)"
  matrix_json="$(cog::fn::power_grade::matrix_json "$matrix_path")"

  jq -e -n \
    --arg schema "cog.power-grade.profile.v1" \
    --arg matrix_path "$matrix_path" \
    --arg name "$name" \
    --argjson matrix "$matrix_json" '
      def cell($id): ($matrix.profiles | map(select(.id == $id)) | first)
        | if . == null then null else {id, model, effort, grade} end;
      ($matrix.named_profiles // [] | map(select(.name == $name)) | first) as $np
      | {
          schema: $schema,
          ok: ($np != null),
          matrix_path: $matrix_path,
          name: $name,
          tier: ($np.name // null),
          use_when: ($np.use_when // null),
          claude: (if $np then cell($np.claude_profile) else null end),
          codex: (if $np then cell($np.codex_profile) else null end)
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

cog::fn::power_grade::classify_json() {
  local grade="$1" matrix_path="${2:-}" matrix_json
  [[ $grade =~ ^[0-9]+$ ]] || cog::fn::error_raise "InvalidInput" \
    "invalid power grade" "grade: ${grade}" "expected an integer" \
    "run 'cog power-grade --help'"
  [[ -n $matrix_path ]] || matrix_path="$(cog::fn::power_grade::matrix_path)"
  matrix_json="$(cog::fn::power_grade::matrix_json "$matrix_path")"

  jq -n \
    --arg schema "cog.power-grade.classify.v1" \
    --arg matrix_path "$matrix_path" \
    --argjson grade "$grade" \
    --argjson matrix "$matrix_json" '
      ($grade >= $matrix.scale.min and $grade <= $matrix.scale.max) as $in_scale
      | {
        schema: $schema,
        ok: $in_scale,
        matrix_path: $matrix_path,
        grade: $grade,
        scale: $matrix.scale,
        profiles: (
          if $in_scale then
            $matrix.profiles
            | map(select(.executable == true and .policy_selectable == true and .grade >= $grade))
            | sort_by(.grade, .id)
          else
            []
          end
        )
      }'
}

cog::fn::power_grade::passes_json() {
  local passes="$1"
  jq -Rc 'split(",") | map(gsub("^[[:space:]]+|[[:space:]]+$"; "")) | map(select(length > 0))' <<<"$passes"
}

cog::fn::power_grade::compound_json() {
  local passes="$1" matrix_path="${2:-}" matrix_json pass_json
  [[ -n $passes ]] || cog::fn::error_raise "MissingArgument" \
    "missing power-grade compound passes" "option: --passes" "" \
    "run 'cog power-grade --help'"
  [[ -n $matrix_path ]] || matrix_path="$(cog::fn::power_grade::matrix_path)"
  matrix_json="$(cog::fn::power_grade::matrix_json "$matrix_path")"
  pass_json="$(cog::fn::power_grade::passes_json "$passes")"

  jq -e -n \
    --arg schema "cog.power-grade.compound.v1" \
    --arg matrix_path "$matrix_path" \
    --arg passes "$passes" \
    --argjson pass_ids "$pass_json" \
    --argjson matrix "$matrix_json" '
      def profile_for($id):
        ($matrix.profiles | map(select(.id == $id or .slug == $id)) | first);
      def pass_profile($id; $idx):
        (profile_for($id)) as $p
        | if $p == null then
            {ok: false, input: $id, index: $idx, error: "unknown_profile"}
          elif $p.executable != true then
            {ok: false, input: $id, index: $idx, profile: $p, error: "profile_not_executable"}
          else
            {ok: true, input: $id, index: $idx, profile: $p}
          end;

      "capped_max_plus_artifact_gain" as $supported_formula
      | (($matrix.compound.formula // $supported_formula) != $supported_formula) as $formula_unsupported
      | (if $formula_unsupported then
           [{ok: false, input: ($matrix.compound.formula // null), index: -1, error: "unknown_formula"}]
         else [] end) as $formula_errors
      | ($pass_ids | to_entries | map(pass_profile(.value; .key))) as $passes_resolved
      | ($formula_errors + ($passes_resolved | map(select(.ok != true)))) as $errors
      | ($passes_resolved | map(select(.ok == true) | .profile)) as $profiles
      | ($profiles | map(.grade) | max // 0) as $base_grade
      | ($matrix.compound.first_pass_gain // 0) as $first_gain
      | ($matrix.compound.subsequent_pass_artifact_gain // 1) as $gain
      | ([range(0; ($profiles | length))] | map(if . == 0 then $first_gain else $gain end)) as $gains
      | ($gains | add // 0) as $artifact_gain
      | ($base_grade + $artifact_gain) as $raw_grade
      | (if ($matrix.compound.cap_to_scale_max // true)
         then [$matrix.scale.max, $raw_grade] | min
         else $raw_grade
         end) as $compound_grade
      | {
          schema: $schema,
          ok: (($errors | length) == 0 and ($profiles | length) > 0),
          matrix_path: $matrix_path,
          input: $passes,
          formula: $matrix.compound,
          scale: $matrix.scale,
          passes: $passes_resolved,
          base_grade: $base_grade,
          artifact_gain: $artifact_gain,
          compound_grade: $compound_grade,
          errors: $errors
        }'
}
