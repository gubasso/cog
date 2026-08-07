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
  source "${LIB_DIR}/commands/cmd_gc_stage.sh"
}

# The session-files parser and the membership/JSON helpers are shared and live
# in fn_git.sh; test/unit/git.bats owns their cases.

@test "gc-stage command object is structured" {
  run __cog_gc_stage_command_object stage a.txt
  assert_success
  assert_output '{"action":"stage","path":"a.txt"}'

  run __cog_gc_stage_command_object restage a.txt
  assert_success
  assert_output '{"action":"restage","path":"a.txt"}'
}

@test "gc-stage append_unique dedupes and drops blanks" {
  local -a acc=()

  __cog_gc_stage_append_unique acc a.txt "" b.txt a.txt

  [ "${#acc[@]}" -eq 2 ]
  [ "${acc[0]}" = "a.txt" ]
  [ "${acc[1]}" = "b.txt" ]
}
