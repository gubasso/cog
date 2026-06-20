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
  source "${LIB_DIR}/commands/cmd_executor_prex_parse_args.sh"
}

@test "executor-prex parser extracts auto review mode and task" {
  local mode task

  __cog_executor_prex_parse_args_parse "-ar Fix * now" mode task

  [ "$mode" = auto-approve-review-loop ]
  [ "$task" = "Fix * now" ]
}

@test "executor-prex parser rejects unknown flags with exit 2" {
  run --separate-stderr __cog_executor_prex_parse_args_parse "--bad Task" mode task

  assert_failure 2
  [[ $stderr == *"unknown executor-prex flag"* ]]
}

@test "executor-prex parser rejects the removed tsk-impl flag with exit 2" {
  run --separate-stderr __cog_executor_prex_parse_args_parse "-t TSK-1 Task" mode task

  assert_failure 2
  [[ $stderr == *"unknown executor-prex flag"* ]]
}
