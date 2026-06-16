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
  source "${LIB_DIR}/functions/fn_rundir.sh"
  source "${LIB_DIR}/functions/fn_git.sh"
  source "${LIB_DIR}/commands/cmd_plan_writer_multi_setup.sh"
}

@test "plan-writer-multi parser extracts executor solo orientation" {
  local executor solo orientation

  __cog_plan_writer_multi_setup_parse "--executor=limited --solo Do work" executor solo orientation

  [ "$executor" = limited ]
  [ "$solo" = true ]
  [ "$orientation" = "Do work" ]
}

@test "plan-writer-multi effort factor helper validates executors" {
  run __cog_plan_writer_multi_setup_ef prex
  assert_success
  assert_output "1.5"

  run __cog_plan_writer_multi_setup_ef bad
  assert_failure
}
