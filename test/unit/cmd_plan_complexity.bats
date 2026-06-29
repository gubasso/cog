setup() {
  bats_require_minimum_version 1.5.0
  load '../test_helper/common-setup'
  _common_setup
  export LIB_DIR="${BATS_TEST_DIRNAME}/../../lib"
  source "${LIB_DIR}/helpers.sh"
  source "${LIB_DIR}/functions/fn_ui_print.sh"
  source "${LIB_DIR}/functions/fn_log.sh"
  source "${LIB_DIR}/functions/fn_error_raise.sh"
  source "${LIB_DIR}/functions/fn_json_write.sh"
  source "${LIB_DIR}/functions/fn_plan_complexity.sh"
  source "${LIB_DIR}/commands/cmd_plan_complexity.sh"
}

@test "plan-complexity ceiling defaults to Very High" {
  unset COG_PLAN_COMPLEXITY_CEILING
  run cog::fn::plan_complexity::ceiling_json
  assert_success
  printf '%s\n' "$output" | jq -e '.ceiling == "Very High" and .rank == 5' >/dev/null
}

@test "plan-complexity over-ceiling ranks grades and Unscorable" {
  unset COG_PLAN_COMPLEXITY_CEILING
  run cog::fn::plan_complexity::over_ceiling_json "Extreme"
  assert_success
  printf '%s\n' "$output" | jq -e '.over == true' >/dev/null

  run cog::fn::plan_complexity::over_ceiling_json "Very High"
  assert_success
  printf '%s\n' "$output" | jq -e '.over == false' >/dev/null

  run cog::fn::plan_complexity::over_ceiling_json "Unscorable"
  assert_success
  printf '%s\n' "$output" | jq -e '.over == true' >/dev/null
}

@test "plan-complexity honors env ceiling override" {
  export COG_PLAN_COMPLEXITY_CEILING=High
  run cog::fn::plan_complexity::over_ceiling_json "Very High"
  assert_success
  printf '%s\n' "$output" | jq -e '.ceiling == "High" and .over == true' >/dev/null
}
