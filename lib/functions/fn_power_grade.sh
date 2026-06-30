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

cog::fn::power_grade::allowlist_path() {
  local override="${COG_POWER_GRADE_ALLOWLIST:-}"
  if [[ -n $override ]]; then
    printf '%s\n' "$override"
    return 0
  fi
  cog::fn::data::path "power-grade/source-allowlist"
}

cog::fn::power_grade::allowlist_json() {
  local allowlist_path="${1:-}"
  [[ -n $allowlist_path ]] || allowlist_path="$(cog::fn::power_grade::allowlist_path)"
  [[ -e $allowlist_path ]] || cog::fn::error_raise "InputNotFound" \
    "power grade source allowlist not found" "path: ${allowlist_path}" "" \
    "check data/power-grade/source-allowlist"

  cog::fn::data::load_dir "$allowlist_path"
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
      def required_keys: ($matrix.validation.required_cell_keys // []);
      def missing_keys($p): required_keys | map(select($p[.] == null));
      def allowlist_tiers:
        ($allowlist.sources // [])
        | map({key: .id, value: .tier})
        | from_entries;
      def cell_source_ids($p): ($p.benchmark_source_ids // []);
      def required_errors:
        $matrix.model_cells
        | to_entries
        | map({index: .key, id: (.value.id // null), missing: missing_keys(.value)})
        | map(select(.missing | length > 0))
        | map({kind: "missing_required_cell_keys", cell_index: .index, cell_id: .id, missing: .missing});
      def duplicate_errors($field):
        ($matrix.model_cells | map(.[$field]) | group_by(.) | map(select(length > 1) | .[0])) as $dupes
        | $dupes
        | map({kind: ("duplicate_cell_" + $field), value: .});
      def grade_errors:
        $matrix.model_cells
        | map(select((.grade | type) != "number" or .grade < $matrix.scale.min or .grade > $matrix.scale.max)
          | {kind: "cell_grade_out_of_scale", cell_id: (.id // null), grade: (.grade // null)});
      def source_errors:
        $matrix.model_cells
        | map(select((.source_refs | type) != "array" or (.source_refs | length) == 0)
          | {kind: "missing_source_refs", cell_id: (.id // null)});
      def unknown_source_errors:
        allowlist_tiers as $tiers
        | $matrix.model_cells
        | to_entries
        | map(. as $entry
            | (cell_source_ids($entry.value) | map(select(($tiers[.] // null) == null))) as $unknown
            | select(($unknown | length) > 0)
            | {kind: "unknown_source_id", cell_index: .key, cell_id: (.value.id // null), source_ids: $unknown});
      def model_tier_errors:
        ($matrix.model_cells | map(.id)) as $ids
        | ($matrix.model_tiers // [])
        | map(select((.claude_cell as $c | $ids | index($c) | not) or
                     (.codex_cell as $g | $ids | index($g) | not))
          | {kind: "model_tier_unknown_reference", name: (.name // null),
             claude_cell: (.claude_cell // null), codex_cell: (.codex_cell // null)});
      def needs_verification_warnings:
        $matrix.model_cells
        | map(select(.evidence_status == "needs_verification")
          | {kind: "needs_verification", cell_id: .id, executable: .executable, caveats: .caveats});
      def tier3_source_warnings:
        allowlist_tiers as $tiers
        | $matrix.model_cells
        | map(. as $cell
            | (cell_source_ids($cell) | map(select(($tiers[.] // null) == 3))) as $tier3
            | select(($tier3 | length) > 0)
            | {kind: "tier3_source_cited", cell_id: (.id // null), source_ids: $tier3});
      def sourced_without_allowlisted_source_warnings:
        allowlist_tiers as $tiers
        | $matrix.model_cells
        | map(select((.evidence_status != "needs_verification") and
                     ((cell_source_ids(.) | map(select((($tiers[.] // 999) <= 2))) | length) == 0))
            | {kind: "sourced_without_allowlisted_source", cell_id: (.id // null),
               benchmark_source_ids: cell_source_ids(.)});
      def warnings:
        needs_verification_warnings + tier3_source_warnings + sourced_without_allowlisted_source_warnings;

      (required_errors + duplicate_errors("id") + duplicate_errors("slug") + grade_errors + source_errors + unknown_source_errors + model_tier_errors) as $errors
      | {
          schema: $schema,
          ok: ($errors | length == 0),
          matrix_path: $matrix_path,
          allowlist_path: $allowlist_path,
          model_cell_count: ($matrix.model_cells | length),
          model_tier_count: (($matrix.model_tiers // []) | length),
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
      ($matrix.model_cells | map(select(.model == $model and .effort == $effort)) | first) as $cell
      | {
          schema: $schema,
          ok: ($cell != null),
          matrix_path: $matrix_path,
          model: $model,
          effort: $effort,
          cell: $cell
        }'
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
        cells: (
          if $in_scale then
            $matrix.model_cells
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
      def cell_for($id):
        ($matrix.model_cells | map(select(.id == $id or .slug == $id)) | first);
      def pass_cell($id; $idx):
        (cell_for($id)) as $p
        | if $p == null then
            {ok: false, input: $id, index: $idx, error: "unknown_cell"}
          elif $p.executable != true then
            {ok: false, input: $id, index: $idx, cell: $p, error: "cell_not_executable"}
          else
            {ok: true, input: $id, index: $idx, cell: $p}
          end;

      "capped_max_plus_artifact_gain" as $supported_formula
      | (($matrix.compound.formula // $supported_formula) != $supported_formula) as $formula_unsupported
      | (if $formula_unsupported then
           [{ok: false, input: ($matrix.compound.formula // null), index: -1, error: "unknown_formula"}]
         else [] end) as $formula_errors
      | ($pass_ids | to_entries | map(pass_cell(.value; .key))) as $passes_resolved
      | ($formula_errors + ($passes_resolved | map(select(.ok != true)))) as $errors
      | ($passes_resolved | map(select(.ok == true) | .cell)) as $cells
      | ($cells | map(.grade) | max // 0) as $base_grade
      | ($matrix.compound.first_pass_gain // 0) as $first_gain
      | ($matrix.compound.subsequent_pass_artifact_gain // 1) as $gain
      | ([range(0; ($cells | length))] | map(if . == 0 then $first_gain else $gain end)) as $gains
      | ($gains | add // 0) as $artifact_gain
      | ($base_grade + $artifact_gain) as $raw_grade
      | (if ($matrix.compound.cap_to_scale_max // true)
         then [$matrix.scale.max, $raw_grade] | min
         else $raw_grade
         end) as $compound_grade
      | {
          schema: $schema,
          ok: (($errors | length) == 0 and ($cells | length) > 0),
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

cog::fn::power_grade::capability_path() {
  local override="${COG_POWER_GRADE_CAPABILITY:-}"
  if [[ -n $override ]]; then
    printf '%s\n' "$override"
    return 0
  fi
  cog::fn::data::path "power-grade/executor-capability"
}

cog::fn::power_grade::capability_json() {
  local capability_path="${1:-}"
  [[ -n $capability_path ]] || capability_path="$(cog::fn::power_grade::capability_path)"
  [[ -e $capability_path ]] || cog::fn::error_raise "InputNotFound" \
    "executor capability data not found" "path: ${capability_path}" "" \
    "check data/power-grade/executor-capability"

  cog::fn::data::load_dir "$capability_path"
}

# Derive each executor's capability power by summing per-stage folds over the
# pass composition (passes.yaml) against the matrix cell grades. Concurrent /
# sequential stages sum their members; route-alternative stages take the max.
# Powers are normalized to a percent of the strongest executor and laid out as
# contiguous bands (previous ceiling = next floor). Nothing is cached.
cog::fn::power_grade::executor_json() {
  local name="${1:-}" capability_path="${2:-}" matrix_path="${3:-}" capability_json matrix_json
  [[ -n $capability_path ]] || capability_path="$(cog::fn::power_grade::capability_path)"
  [[ -n $matrix_path ]] || matrix_path="$(cog::fn::power_grade::matrix_path)"
  capability_json="$(cog::fn::power_grade::capability_json "$capability_path")"
  matrix_json="$(cog::fn::power_grade::matrix_json "$matrix_path")"

  jq -n \
    --arg schema "cog.power-grade.executor.v1" \
    --arg capability_path "$capability_path" \
    --arg matrix_path "$matrix_path" \
    --arg name "$name" \
    --argjson capability "$capability_json" \
    --argjson matrix "$matrix_json" '
      def round1($n): (($n * 10) | round) / 10;
      def grade_for($id):
        ($matrix.model_cells | map(select(.id == $id or .slug == $id)) | first) as $c
        | if $c == null then null else $c.grade end;
      def stage_power($stage):
        ($stage.members | map(grade_for(.cell))) as $grades
        | if ($grades | any(. == null)) then null
          elif ($stage.combine == "max") then ($grades | max)
          else ($grades | add)
          end;
      def executor_power($ex):
        ($ex.stages | map(stage_power(.))) as $sp
        | if ($sp | any(. == null)) then null else ($sp | add) end;

      ($capability.executor_passes // []) as $all
      | ($all | map({
          executor: .executor,
          heaviest_route: (.heaviest_route // null),
          power: executor_power(.),
          stages: (.stages | map({
            role: .role,
            combine: .combine,
            power: stage_power(.),
            members: (.members | map({
              cell: .cell,
              grade: grade_for(.cell),
              runs_via: (.runs_via // null),
              basis: (.basis // null),
              note: (.note // null)
            }))
          }))
        })) as $resolved
      | ([$resolved[].power] | map(select(. != null)) | max // 0) as $maxpower
      | ($resolved | sort_by(.power // 0)) as $sorted
      | (reduce range(0; ($sorted | length)) as $i ({prev: 0, out: []};
            ($sorted[$i].power // 0) as $pw
            | (if $maxpower > 0 then ($pw / $maxpower * 100) else 0 end) as $ceil
            | {prev: $ceil, out: (.out + [$sorted[$i] + {
                  percent: round1($ceil),
                  floor_pct: round1(.prev),
                  ceil_pct: round1($ceil)
                }])}
         ) | .out) as $banded
      | ($banded | map(select($name == "" or .executor == $name))) as $selected
      | {
          schema: $schema,
          ok: (($selected | length) > 0 and ($selected | all(.power != null))),
          capability_path: $capability_path,
          matrix_path: $matrix_path,
          max_power: $maxpower,
          executors: $selected,
          errors: (
            [$resolved[] | select(.power == null) | {kind: "unresolved_cell", executor: .executor}]
            + (if ($name != "" and (($banded | map(.executor) | index($name)) == null))
               then [{kind: "unknown_executor", executor: $name}] else [] end)
          )
        }'
}

# Route a complexity score to the right-sized executor via the normalized-percent
# overlay: normalize the score to a percent of complexity_max_score, then pick the
# executor whose power band contains it. Scores above the extreme-reserved cutoff
# are non-executable as a single round (executor null, reserved true).
cog::fn::power_grade::match_json() {
  local score="$1" capability_path="${2:-}" matrix_path="${3:-}" exec_json capability_json
  [[ -n $score ]] || cog::fn::error_raise "MissingArgument" \
    "missing complexity score" "option: --score" "" "run 'cog power-grade --help'"
  [[ $score =~ ^[0-9]+([.][0-9]+)?$ ]] || cog::fn::error_raise "InvalidInput" \
    "invalid complexity score" "score: ${score}" "expected a non-negative number" \
    "run 'cog power-grade --help'"
  [[ -n $capability_path ]] || capability_path="$(cog::fn::power_grade::capability_path)"
  [[ -n $matrix_path ]] || matrix_path="$(cog::fn::power_grade::matrix_path)"
  exec_json="$(cog::fn::power_grade::executor_json "" "$capability_path" "$matrix_path")"
  capability_json="$(cog::fn::power_grade::capability_json "$capability_path")"

  jq -n \
    --arg schema "cog.power-grade.match.v1" \
    --arg capability_path "$capability_path" \
    --arg matrix_path "$matrix_path" \
    --argjson score "$score" \
    --argjson exec "$exec_json" \
    --argjson capability "$capability_json" '
      def round1($n): (($n * 10) | round) / 10;
      ($capability.calibration) as $cal
      | ($cal.complexity.max_score // 0) as $maxscore
      | ($cal.extreme_reserved.over_score // null) as $over
      | ($exec.max_power) as $maxpower
      | ($exec.executors | sort_by(.power)) as $sorted
      | (reduce range(0; ($sorted | length)) as $i ({prev: 0, out: []};
            ($sorted[$i].power) as $pw
            | (if $maxpower > 0 then ($pw / $maxpower * 100) else 0 end) as $ceil
            | {prev: $ceil, out: (.out + [{
                  executor: $sorted[$i].executor,
                  power: $pw,
                  floor_pct: .prev,
                  ceil_pct: $ceil
                }])}
         ) | .out) as $bands
      | (if $maxscore > 0 then ($score / $maxscore * 100) else 0 end) as $pct
      | (($over != null) and ($score > $over)) as $reserved
      | (if $reserved then null
         else (([$bands[] | select($pct <= .ceil_pct)] | first | .executor)
               // ($bands | last | .executor))
         end) as $chosen
      | {
          schema: $schema,
          ok: true,
          capability_path: $capability_path,
          matrix_path: $matrix_path,
          score: $score,
          max_score: $maxscore,
          percent: round1($pct),
          reserved: $reserved,
          executor: $chosen,
          bands: ($bands | map({
            executor: .executor,
            power: .power,
            floor_pct: round1(.floor_pct),
            ceil_pct: round1(.ceil_pct)
          })),
          errors: []
        }'
}

# Drift guard: every native executor-* skill must have a passes.yaml entry, every
# member cell must resolve in the matrix, and the calibration must stay coherent
# (bands contiguous and cover the strongest executor, complexity max present, the
# extreme cutoff's score and percent agree).
cog::fn::power_grade::executor_validate_json() {
  local capability_path="${1:-}" matrix_path="${2:-}" root capability_json matrix_json exec_json skills_json
  [[ -n $capability_path ]] || capability_path="$(cog::fn::power_grade::capability_path)"
  [[ -n $matrix_path ]] || matrix_path="$(cog::fn::power_grade::matrix_path)"
  capability_json="$(cog::fn::power_grade::capability_json "$capability_path")"
  matrix_json="$(cog::fn::power_grade::matrix_json "$matrix_path")"
  exec_json="$(cog::fn::power_grade::executor_json "" "$capability_path" "$matrix_path")"

  root="$(realpath "${LIB_DIR}/..")"
  local names=() d n
  if [[ -d "${root}/skills/claude" ]]; then
    for d in "${root}/skills/claude/"executor-*/; do
      [[ -d $d ]] || continue
      n="$(basename "$d")"
      [[ $n == *-codex ]] && continue # delegation launcher, not a native executor
      names+=("$n")
    done
  fi
  if ((${#names[@]} == 0)); then
    skills_json='[]'
  else
    skills_json="$(printf '%s\n' "${names[@]}" | jq -R . | jq -s '.')"
  fi

  jq -n \
    --arg schema "cog.power-grade.executor-validate.v1" \
    --arg capability_path "$capability_path" \
    --argjson capability "$capability_json" \
    --argjson matrix "$matrix_json" \
    --argjson exec "$exec_json" \
    --argjson skills "$skills_json" '
      ($capability.executor_passes // []) as $passes
      | ($passes | map(.executor)) as $graded
      | (($matrix.model_cells | map(.id)) + ($matrix.model_cells | map(.slug))) as $known_cells
      | ($capability.calibration) as $cal
      | ([$skills[] | select((. as $s | $graded | index($s)) == null)]) as $missing
      | ([$passes[] | .executor as $ex | .stages[].members[]
          | select((.cell as $c | $known_cells | index($c)) == null)
          | {executor: $ex, cell: .cell}]) as $unknown_cells
      | ($cal.complexity.max_score // 0) as $maxscore
      | ($exec.max_power) as $maxpower
      | ($exec.executors | sort_by(.power)) as $sorted
      | (reduce range(0; ($sorted | length)) as $i ({prev: 0, ok: true};
            (if $maxpower > 0 then ($sorted[$i].power / $maxpower * 100) else 0 end) as $ceil
            | {prev: $ceil, ok: (.ok and (.prev <= $ceil))}
         )) as $bandchain
      | (($maxpower > 0) and (($sorted | length) > 0) and (($sorted | last | .power) == $maxpower)) as $covers_top
      | ($maxscore > 0) as $score_ok
      | (($cal.extreme_reserved.over_score // null) as $os
         | ($cal.extreme_reserved.over_percent // null) as $op
         | if ($os == null or $op == null or $maxscore == 0) then false
           else ((($os / $maxscore * 100) - $op) | fabs) <= 0.2 end) as $extreme_ok
      | ($bandchain.ok and $covers_top and $score_ok and $extreme_ok) as $calib_ok
      | {
          schema: $schema,
          ok: (($missing | length) == 0 and ($unknown_cells | length) == 0 and $calib_ok),
          capability_path: $capability_path,
          checks: {
            completeness: (($missing | length) == 0),
            referential_integrity: (($unknown_cells | length) == 0),
            calibration_coherence: $calib_ok
          },
          missing_executors: $missing,
          unknown_cells: $unknown_cells,
          errors: (
            (if ($missing | length) > 0 then [{kind: "missing_executor_entry", executors: $missing}] else [] end)
            + (if ($unknown_cells | length) > 0 then [{kind: "unknown_cell", cells: $unknown_cells}] else [] end)
            + (if ($calib_ok | not) then [{kind: "calibration_incoherent"}] else [] end)
          )
        }'
}
