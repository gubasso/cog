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
  source "${LIB_DIR}/functions/fn_toml.sh"
}

matrix_json() {
  local matrix="${REPO_ROOT}/docs/reference/power-grade-matrix.toml"
  command -v taplo >/dev/null 2>&1 || skip "taplo not installed"
  cog::fn::toml::json "$matrix"
}

@test "power grade matrix parses through cog toml runtime" {
  run matrix_json

  assert_success
  printf '%s\n' "$output" | jq -e '
    .schema_version == 1 and
    .scale.min == 1 and
    .scale.max == 10 and
    .compound.formula == "capped_max_plus_artifact_gain" and
    (.profiles | type == "array" and length > 0) and
    (.named_profiles | type == "array" and length == 3)
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
    (.profiles[] | select(.model == "gpt-5.3-codex-spark") |
      .executable == false and
      .evidence_status == "needs_verification" and
      .effort == "needs-verification")
  ' >/dev/null
}
