setup() {
  bats_require_minimum_version 1.5.0
  load '../test_helper/common-setup'
  _common_setup
  export REPO_ROOT="${BATS_TEST_DIRNAME}/../.."
  export LIB_DIR="${REPO_ROOT}/lib"
  # shellcheck source=/dev/null
  source "${LIB_DIR}/helpers.sh"
  # shellcheck source=/dev/null
  source "${LIB_DIR}/functions/fn_ui_print.sh"
  # shellcheck source=/dev/null
  source "${LIB_DIR}/functions/fn_log.sh"
  # shellcheck source=/dev/null
  source "${LIB_DIR}/functions/fn_error_raise.sh"
  # shellcheck source=/dev/null
  source "${LIB_DIR}/functions/fn_data.sh"
  # shellcheck source=/dev/null
  source "${LIB_DIR}/functions/fn_power_grade.sh"
}

matrix_json() {
  local matrix="${REPO_ROOT}/data/power-grade/matrix"
  cog::fn::data::load_dir "$matrix"
}

allowlist_json() {
  local allowlist="${REPO_ROOT}/data/power-grade/source-allowlist"
  cog::fn::data::load_dir "$allowlist"
}

write_allowlist_fixture() {
  local path="$1"
  cat >"$path" <<'YAML'
schema_version: 1
data_collected: "2026-06-25"
revalidate_by: "2026-09-25"
policy:
  clears_rule: "tier <= 2"
  tier1_clears: true
  tier2_clears_with_caveat: true
  tier3_clears: false
  description: "fixture"
sources:
  - id: "tier1-source"
    name: "Tier 1 source"
    url: "https://example.test/tier1"
    tier: 1
    owner: "fixture"
    data_types: ["benchmark"]
    trusted_for: ["benchmark_score"]
    not_trusted_for: []
    methodology_transparency: "fixture"
    reproducible_auditable: "partial"
    update_cadence: "fixture"
    clears_needs_verification: true
    notes: "fixture"
    last_checked: "2026-06-25"
  - id: "tier3-source"
    name: "Tier 3 source"
    url: "https://example.test/tier3"
    tier: 3
    owner: "fixture"
    data_types: ["benchmark"]
    trusted_for: []
    not_trusted_for: ["benchmark_score"]
    methodology_transparency: "fixture"
    reproducible_auditable: "none"
    update_cadence: "fixture"
    clears_needs_verification: false
    notes: "fixture"
    last_checked: "2026-06-25"
YAML
}

write_matrix_fixture() {
  local path="$1" evidence_status="$2" source_ids="$3"
  cat >"$path" <<YAML
schema_version: 1
data_collected: "2026-06-25"
revalidate_by: "2026-09-25"
scale:
  min: 1
  max: 10
  description: "fixture"
  grade_rule: "fixture"
validation:
  required_profile_keys: ["id", "slug", "label", "provider", "model", "effort", "grade", "executable", "policy_selectable", "evidence_status", "confidence", "source_refs", "benchmark_source_ids", "description", "use_where", "caveats"]
compound:
  formula: "capped_max_plus_artifact_gain"
profiles:
  - id: "fixture-profile"
    slug: "fixture-profile"
    label: "fixture profile"
    provider: "codex"
    model: "fixture-model"
    effort: "medium"
    grade: 1
    executable: true
    policy_selectable: true
    evidence_status: "${evidence_status}"
    confidence: "medium"
    source_refs: ["data/model-effort/codex#fixture"]
    benchmark_source_ids: ${source_ids}
    description: "fixture"
    use_where: ["fixture"]
    caveats: []
YAML
}

validate_matrix_fixture() {
  COG_POWER_GRADE_MATRIX="$1" COG_POWER_GRADE_ALLOWLIST="$2" cog::fn::power_grade::validate_json
}

@test "power grade matrix parses through cog data runtime" {
  run matrix_json

  assert_success
  printf '%s\n' "$output" | jq -e '
    .schema_version == 1 and
    .scale.min == 1 and
    .scale.max == 10 and
    .compound.formula == "capped_max_plus_artifact_gain" and
    (.profiles | type == "array" and length > 0) and
    (.named_profiles | type == "array" and length == 5)
  ' >/dev/null
}

@test "power grade matrix profiles satisfy committed schema" {
  run matrix_json

  assert_success
  printf '%s\n' "$output" | jq -e '
    def has_required:
      .id and .slug and .label and .provider and .model and .effort and
      (.grade | type == "number") and
      (.executable | type == "boolean") and
      (.policy_selectable | type == "boolean") and
	      ((.evidence_status == "sourced") or (.evidence_status == "needs_verification")) and
	      (.confidence | type == "string" and length > 0) and
	      (.source_refs | type == "array" and length > 0) and
	      (.benchmark_source_ids | type == "array") and
	      (.description | type == "string" and length > 0) and
      (.use_where | type == "array" and length > 0) and
      (.caveats | type == "array");

    . as $root |
    ([.profiles[].id] | length) == ([.profiles[].id] | unique | length) and
    ([.profiles[].slug] | length) == ([.profiles[].slug] | unique | length) and
    all(.profiles[]; has_required and (.grade >= $root.scale.min and .grade <= $root.scale.max))
  ' >/dev/null
}

@test "power grade matrix keeps unsupported and unknown efforts non-fabricated" {
  run matrix_json

  assert_success
  printf '%s\n' "$output" | jq -e '
	    ([.profiles[] | select(.model == "claude-haiku-4-5")] | length) == 1 and
	    (.profiles[] | select(.model == "claude-haiku-4-5") | .effort == "none") and
	    ([.profiles[] | select(.evidence_status == "needs_verification")] | length) == 1 and
	    (.profiles[] | select(.model == "gpt-5.3-codex-spark") |
	      .executable == false and
	      .evidence_status == "needs_verification" and
	      .effort == "needs-verification")
	  ' >/dev/null
}

@test "power grade source allowlist satisfies committed schema" {
  run allowlist_json

  assert_success
  printf '%s\n' "$output" | jq -e '
    .schema_version == 1 and
    (.policy.clears_rule | type == "string" and length > 0) and
    ([.sources[].id] | length) == ([.sources[].id] | unique | length) and
    all(.sources[]; (
      (.id | type == "string" and length > 0) and
      (.name | type == "string" and length > 0) and
      (.url | type == "string" and length > 0) and
      (.tier | IN(1,2,3)) and
      (.owner | type == "string" and length > 0) and
      (.data_types | type == "array") and
      (.trusted_for | type == "array") and
      (.not_trusted_for | type == "array") and
      (.methodology_transparency | type == "string" and length > 0) and
      (.reproducible_auditable | type == "string" and length > 0) and
      (.update_cadence | type == "string" and length > 0) and
      (.clears_needs_verification | type == "boolean") and
      (.notes | type == "string") and
      (.last_checked | type == "string" and length > 0)
    ))
  ' >/dev/null
}

@test "power grade validator rejects unknown benchmark source ids" {
  local matrix="${BATS_TEST_TMPDIR}/matrix.yaml"
  local allowlist="${BATS_TEST_TMPDIR}/allowlist.yaml"
  write_allowlist_fixture "$allowlist"
  write_matrix_fixture "$matrix" "sourced" '["missing-source"]'

  run validate_matrix_fixture "$matrix" "$allowlist"

  assert_success
  printf '%s\n' "$output" | jq -e '
    .ok == false and
    (.errors | map(.kind) | index("unknown_source_id") != null)
  ' >/dev/null
}

@test "power grade validator warns on tier-3 benchmark source ids" {
  local matrix="${BATS_TEST_TMPDIR}/matrix.yaml"
  local allowlist="${BATS_TEST_TMPDIR}/allowlist.yaml"
  write_allowlist_fixture "$allowlist"
  write_matrix_fixture "$matrix" "sourced" '["tier3-source"]'

  run validate_matrix_fixture "$matrix" "$allowlist"

  assert_success
  printf '%s\n' "$output" | jq -e '
    .ok == true and
    (.warnings | map(.kind) | index("tier3_source_cited") != null)
  ' >/dev/null
}

@test "power grade validator warns when sourced profile lacks clearing source" {
  local matrix="${BATS_TEST_TMPDIR}/matrix.yaml"
  local allowlist="${BATS_TEST_TMPDIR}/allowlist.yaml"
  write_allowlist_fixture "$allowlist"
  write_matrix_fixture "$matrix" "sourced" '[]'

  run validate_matrix_fixture "$matrix" "$allowlist"

  assert_success
  printf '%s\n' "$output" | jq -e '
    .ok == true and
    (.warnings | map(.kind) | index("sourced_without_allowlisted_source") != null)
  ' >/dev/null
}
