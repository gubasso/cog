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
  source "${LIB_DIR}/commands/cmd_test_review_manifest.sh"
}

@test "test-review-manifest exposes yq expression helpers" {
  run __cog_test_review_manifest_phase_expr
  assert_success
  assert_output '.phase = strenv(PHASE)'

  run __cog_test_review_manifest_log_expr
  assert_success
  [[ $output == *'implementation-log'* ]]

  run __cog_test_review_manifest_tooling_expr
  assert_success
  assert_output '.tooling.delta = load(strenv(UPDATE_FILE)).tooling_delta'

  run __cog_test_review_manifest_summary_expr
  assert_success
  [[ $output == *'final-summary'* ]]
}
