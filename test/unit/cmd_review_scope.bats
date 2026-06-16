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
  source "${LIB_DIR}/commands/cmd_review_scope.sh"
}

@test "review-scope changed files include untracked status paths" {
  local staged='["b.txt"]'
  local unstaged='["a.txt"]'
  local status='[{"path":"z.txt","untracked":true},{"path":"a.txt","untracked":false}]'

  run __cog_review_scope_changed_files "$staged" "$unstaged" "$status"

  assert_success
  assert_output '["a.txt","b.txt","z.txt"]'
}

@test "review-scope rejects missing output mode" {
  run --separate-stderr cog::cmd::review_scope

  assert_failure 64
  [[ $stderr == *"err.kind: MissingArgument"* ]]
}
