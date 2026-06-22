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
  source "${LIB_DIR}/functions/fn_review.sh"
  source "${LIB_DIR}/commands/cmd_review_comment.sh"
}

write_findings() {
  cat >"${BATS_TEST_TMPDIR}/findings.json" <<'JSON'
{"decision":"comment","summary":"s","strengths":[],"findings":[
{"severity":"important","file":"a.sh","line_start":1,"line_end":2,"category":"correctness","headline":"Same","evidence":"","reasoning":"Bad behavior.","suggestion":"Fix it.","confidence":"high"},
{"severity":"praise","file":"b.sh","line_start":1,"line_end":1,"category":"style","headline":"Good","evidence":"","reasoning":"","suggestion":"","confidence":"high"}
]}
JSON
}

@test "review-comment dry-run plans actionable comments only" {
  write_findings

  run __cog_review_comment_build_json "${BATS_TEST_TMPDIR}/findings.json" 12 true

  assert_success
  printf '%s\n' "$output" | jq -e '
    .dry_run == true and (.planned_comments | length) == 1
    and (.planned_comments[0].body | contains("<!-- cog-review-finding:"))
  ' >/dev/null
}

@test "review-comment command honors dry-run flag" {
  write_findings

  run cog::cmd::review_comment --findings "${BATS_TEST_TMPDIR}/findings.json" --pr 12 --dry-run --json

  assert_success
  printf '%s\n' "$output" | jq -e '.dry_run == true and (.planned_comments | length) == 1' >/dev/null
}
