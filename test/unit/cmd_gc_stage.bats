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

@test "gc-stage session parser dedupes valid paths" {
  local file="${BATS_TEST_TMPDIR}/session.txt"
  printf '%s\n' a.txt a.txt dir/b.txt >"$file"
  local -a paths=()

  __cog_gc_stage_read_session_files paths "$file"

  [ "${#paths[@]}" -eq 2 ]
  [ "${paths[1]}" = "dir/b.txt" ]
}

@test "gc-stage parser rejects parent traversal" {
  local file="${BATS_TEST_TMPDIR}/session.txt"
  printf '%s\n' dir/../bad >"$file"

  run --separate-stderr __cog_gc_stage_read_session_files paths "$file"

  assert_failure 65
  [[ $stderr == *"must not contain .."* ]]
}

@test "gc-stage command object is structured" {
  run __cog_gc_stage_command_object stage a.txt

  assert_success
  assert_output '{"action":"stage","path":"a.txt"}'
}
