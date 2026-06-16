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
  source "${LIB_DIR}/commands/cmd_require.sh"
}

@test "require command path derives underscores" {
  run __cog_require_command_path gc-stage

  assert_success
  assert_output "${LIB_DIR}/commands/cmd_gc_stage.sh"
}

@test "require JSON preserves present and missing partitions" {
  run __cog_require_build_json false 1 msg missing

  assert_success
  printf '%s\n' "$output" | jq -e '.ok == false and .present == ["msg"] and .missing == ["missing"]' >/dev/null
}

@test "require rejects empty args" {
  run --separate-stderr cog::cmd::require

  assert_failure 64
  [[ $stderr == *"err.kind: MissingArgument"* ]]
}
