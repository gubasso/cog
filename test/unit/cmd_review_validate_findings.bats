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
  source "${LIB_DIR}/commands/cmd_review_validate_findings.sh"
}

write_valid_findings() {
  cat >"${BATS_TEST_TMPDIR}/findings.json" <<'JSON'
{"decision":"approve","summary":"ok","strengths":[],"findings":[]}
JSON
}

@test "review-validate-findings accepts minimal valid JSON" {
  write_valid_findings

  run __cog_review_validate_findings_build_json "${BATS_TEST_TMPDIR}/findings.json"

  assert_success
  printf '%s\n' "$output" | jq -e '.ok == true and .findings_count == 0' >/dev/null
}

@test "review-validate-findings reports first useful reason" {
  printf '%s\n' '{"decision":"bad","summary":"ok","strengths":[],"findings":[]}' >"${BATS_TEST_TMPDIR}/bad.json"

  run --separate-stderr __cog_review_validate_findings_validate "${BATS_TEST_TMPDIR}/bad.json"

  assert_failure 65
  [[ $stderr == *"decision must be one of"* ]]
}

@test "review-validate-findings requires findings flag" {
  run --separate-stderr cog::cmd::review_validate_findings --json

  assert_failure 64
  [[ $stderr == *"err.kind: MissingArgument"* ]]
}
