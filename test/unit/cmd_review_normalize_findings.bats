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
  source "${LIB_DIR}/commands/cmd_review_normalize_findings.sh"
}

write_findings() {
  cat >"${BATS_TEST_TMPDIR}/findings.json" <<'JSON'
{"decision":"comment","summary":"s","strengths":[],"findings":[
{"severity":"nit","file":"b.sh","line_start":9,"line_end":9,"category":"style","headline":"Nit","evidence":"","reasoning":"","suggestion":"","confidence":"high"},
{"severity":"blocking","file":"z.sh","line_start":4,"line_end":4,"category":"correctness","headline":"Block","evidence":"","reasoning":"","suggestion":"","confidence":"high"},
{"severity":"important","file":"a.sh","line_start":2,"line_end":2,"category":"test","headline":"Important","evidence":"","reasoning":"","suggestion":"","confidence":"medium"}
]}
JSON
}

@test "review-normalize-findings sorts and filters by minimum severity" {
  write_findings

  run __cog_review_normalize_findings_build_json "${BATS_TEST_TMPDIR}/findings.json" important

  assert_success
  printf '%s\n' "$output" | jq -e '
    [.findings[].headline] == ["Block","Important"]
  ' >/dev/null
}

@test "review-normalize-findings supports in-place output" {
  write_findings

  run cog::cmd::review_normalize_findings --findings "${BATS_TEST_TMPDIR}/findings.json" --severity nit --out "${BATS_TEST_TMPDIR}/findings.json"

  assert_success
  jq -e '.findings[0].headline == "Block"' "${BATS_TEST_TMPDIR}/findings.json" >/dev/null
}

@test "review-normalize-findings rejects duplicate output mode" {
  write_findings

  run --separate-stderr cog::cmd::review_normalize_findings --findings "${BATS_TEST_TMPDIR}/findings.json" --json --out x

  assert_failure 65
  [[ $stderr == *"duplicate"* ]]
}
