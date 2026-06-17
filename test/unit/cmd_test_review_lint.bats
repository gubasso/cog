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
  source "${LIB_DIR}/commands/cmd_test_review_lint.sh"
}

@test "test-review-lint scan helper emits rule JSON" {
  local repo="${BATS_TEST_TMPDIR}/repo"
  mkdir -p "$repo/tests"
  printf '%s\n' 'time.sleep(1)' 'assert_called()' >"$repo/tests/test_app.py"

  run __cog_test_review_lint_scan_file "$repo" "tests/test_app.py"

  assert_success
  printf '%s\n' "$output" | jq -s -e '([.[].rule_id] | index("TR-SLEEP")) and ([.[].rule_id] | index("TR-MOCK-ONLY"))' >/dev/null
}
