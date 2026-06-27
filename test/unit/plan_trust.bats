setup() {
  bats_require_minimum_version 1.5.0
  load '../test_helper/common-setup'
  _common_setup
  export HOME="${BATS_TEST_TMPDIR}/home"
  export XDG_DATA_HOME="${BATS_TEST_TMPDIR}/data"
  export XDG_STATE_HOME="${BATS_TEST_TMPDIR}/state"
  export XDG_CONFIG_HOME="${BATS_TEST_TMPDIR}/config"
  mkdir -p "$HOME" "$XDG_DATA_HOME" "$XDG_STATE_HOME" "$XDG_CONFIG_HOME"
  # shellcheck source=/dev/null
  source "${BATS_TEST_DIRNAME}/../../lib/helpers.sh"
  # shellcheck source=/dev/null
  source "${BATS_TEST_DIRNAME}/../../lib/functions/fn_ui_print.sh"
  # shellcheck source=/dev/null
  source "${BATS_TEST_DIRNAME}/../../lib/functions/fn_error_raise.sh"
  # shellcheck source=/dev/null
  source "${BATS_TEST_DIRNAME}/../../lib/functions/fn_json_write.sh"
  # shellcheck source=/dev/null
  source "${BATS_TEST_DIRNAME}/../../lib/functions/fn_queue.sh"
  # shellcheck source=/dev/null
  source "${BATS_TEST_DIRNAME}/../../lib/functions/fn_plan_slug.sh"
  # shellcheck source=/dev/null
  source "${BATS_TEST_DIRNAME}/../../lib/functions/fn_plan_store.sh"
  # shellcheck source=/dev/null
  source "${BATS_TEST_DIRNAME}/../../lib/functions/fn_plan_config.sh"
  # shellcheck source=/dev/null
  source "${BATS_TEST_DIRNAME}/../../lib/functions/fn_plan_trust.sh"
  # shellcheck source=/dev/null
  source "${BATS_TEST_DIRNAME}/../../lib/functions/fn_plan_resolve.sh"
}

@test "trust status is absent with missing DB" {
  local repo="${BATS_TEST_TMPDIR}/repo"
  mkdir -p "$repo"

  run cog::fn::plan_trust_status_json "$repo"

  assert_success
  assert_equal "$(jq -r '.status' <<<"$output")" "absent"
}

@test "trust allow and revoke round-trip with valid JSON DB" {
  local repo="${BATS_TEST_TMPDIR}/repo"
  mkdir -p "$repo"

  run cog::fn::plan_trust_allow "$repo"
  assert_success
  assert_equal "$(jq -r '.status' <<<"$output")" "trusted"
  jq -e '.schema == "cog.plan-trust.v1"' "$(cog::fn::plan_trust_db_path)"

  run cog::fn::plan_trust_revoke "$repo"
  assert_success
  assert_equal "$(jq -r '.status' <<<"$output")" "absent"
  jq -e '.schema == "cog.plan-trust.v1"' "$(cog::fn::plan_trust_db_path)"
}

@test "strict explicit local resolve fails closed while untrusted" {
  local repo="${BATS_TEST_TMPDIR}/repo"
  mkdir -p "$repo/.cog/plans"

  run --separate-stderr cog::fn::plan_resolve_json "$repo" "local" ""

  assert_failure 65
  [[ $stderr == *"err.kind: InvalidInput"* ]]
  [[ $stderr == *"local plan root is not trusted"* ]]
}

@test "global resolve is implicitly trusted" {
  local repo="${BATS_TEST_TMPDIR}/repo"
  mkdir -p "$repo"

  run cog::fn::plan_resolve_json "$repo" "global" ""

  assert_success
  assert_equal "$(jq -r '.store' <<<"$output")" "global"
  assert_equal "$(jq -r '.trust.status' <<<"$output")" "implicitly-trusted-global"
}

@test "trust key fingerprints the configured local dir, not hardcoded .cog/plans" {
  local repo="${BATS_TEST_TMPDIR}/repo"
  mkdir -p "$repo/.cog/plans" "$repo/alt/plans"

  # Baseline key under the configured alt dir.
  local key_before
  key_before="$(COG_PLAN_LOCAL_DIR='alt/plans' cog::fn::plan_trust_key "$repo")"

  # Changing the hardcoded .cog/plans/project.sh must NOT affect the key when the
  # configured local dir is alt/plans.
  printf '%s\n' "COG_PLAN_PROJECT_KEY='x'" >"$repo/.cog/plans/project.sh"
  local key_other_dir
  key_other_dir="$(COG_PLAN_LOCAL_DIR='alt/plans' cog::fn::plan_trust_key "$repo")"
  assert_equal "$key_before" "$key_other_dir"

  # Changing the CONFIGURED dir's project.sh MUST change the key.
  printf '%s\n' "COG_PLAN_PROJECT_KEY='y'" >"$repo/alt/plans/project.sh"
  local key_after
  key_after="$(COG_PLAN_LOCAL_DIR='alt/plans' cog::fn::plan_trust_key "$repo")"
  [ "$key_before" != "$key_after" ]
}
