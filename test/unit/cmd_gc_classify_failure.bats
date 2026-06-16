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
  source "${LIB_DIR}/functions/fn_git.sh"
  source "${LIB_DIR}/commands/cmd_gc_classify_failure.sh"
}

@test "gc-classify-failure requires log argument" {
  run --separate-stderr cog::cmd::gc_classify_failure --json

  assert_failure 64
  [[ $stderr == *"err.kind: MissingArgument"* ]]
}

@test "gc-classify-failure help works when sourced" {
  run cog::cmd::gc_classify_failure --help

  assert_success
  [[ $output == *"gc-classify-failure"* ]]
}
