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
  source "${LIB_DIR}/commands/cmd_review_loop_progress.sh"
}

write_rounds() {
  cat >"${BATS_TEST_TMPDIR}/previous.json" <<'JSON'
{"decision":"comment","summary":"s","strengths":[],"findings":[
{"severity":"important","file":"a.sh","line_start":1,"line_end":1,"category":"correctness","headline":"Same","evidence":"","reasoning":"","suggestion":"","confidence":"high"},
{"severity":"nit","file":"old.sh","line_start":2,"line_end":2,"category":"style","headline":"Old","evidence":"","reasoning":"","suggestion":"","confidence":"high"}
]}
JSON
  cat >"${BATS_TEST_TMPDIR}/current.json" <<'JSON'
{"decision":"comment","summary":"s","strengths":[],"findings":[
{"severity":"important","file":"a.sh","line_start":1,"line_end":1,"category":"correctness","headline":" Same ","evidence":"","reasoning":"","suggestion":"","confidence":"high"},
{"severity":"blocking","file":"new.sh","line_start":3,"line_end":3,"category":"test","headline":"New","evidence":"","reasoning":"","suggestion":"","confidence":"medium"}
]}
JSON
}

@test "review-loop-progress reports recurring new and resolved" {
  write_rounds

  run __cog_review_loop_progress_build_json "${BATS_TEST_TMPDIR}/current.json" "${BATS_TEST_TMPDIR}/previous.json"

  assert_success
  printf '%s\n' "$output" | jq -e '
    .counts.recurring == 1 and .counts.new == 1 and .counts.resolved == 1
  ' >/dev/null
}

@test "review-loop-progress requires both files" {
  run --separate-stderr cog::cmd::review_loop_progress --json

  assert_failure 64
  [[ $stderr == *"MissingArgument"* ]]
}
