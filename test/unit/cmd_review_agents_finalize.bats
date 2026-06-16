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
  source "${LIB_DIR}/functions/fn_refs.sh"
  source "${LIB_DIR}/commands/cmd_review_agents_finalize.sh"
}

@test "review-agents-finalize delegates argv to review-refs" {
  printf '%s\n' '{"is_cli":false,"languages":[]}' >"${BATS_TEST_TMPDIR}/classification.json"

  run cog::cmd::review_agents_finalize "${BATS_TEST_TMPDIR}/classification.json" --json

  assert_success
  printf '%s\n' "$output" | jq -e '.classification.is_cli == false' >/dev/null
}

@test "review-agents-finalize help comes from review-refs" {
  run cog::cmd::review_agents_finalize --help

  assert_success
  [[ $output == *"review-refs"* ]]
}
