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

@test "executor-prex parser extracts auto review tsk id and task" {
  local mode impl id task

  __cog_executor_prex_parse_args_parse "-ar -t TSK-1 Fix * now" mode impl id task

  [ "$mode" = auto-approve-review-loop ]
  [ "$impl" = 1 ]
  [ "$id" = TSK-1 ]
  [ "$task" = "Fix * now" ]
}

@test "executor-prex parser rejects unknown flags with exit 2" {
  run --separate-stderr __cog_executor_prex_parse_args_parse "--bad Task" mode impl id task

  assert_failure 2
  [[ $stderr == *"unknown executor-prex flag"* ]]
}
