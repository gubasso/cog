setup() {
  bats_require_minimum_version 1.5.0
  load '../test_helper/common-setup'
  _common_setup
  mkdir -p "${BATS_TEST_TMPDIR}/run" "${BATS_TEST_TMPDIR}/run2"
}

@test "cog executor-prex-parse-args writes auto-review task state" {
  run cog executor-prex-parse-args --json "${BATS_TEST_TMPDIR}/run" "-ar Fix * [abc]"

  assert_success
  printf '%s\n' "$output" | jq -e '.mode == "auto-approve-review-loop"' >/dev/null
  assert_file_contains "${BATS_TEST_TMPDIR}/run/mode" "auto-approve-review-loop"
  grep -F "Fix * [abc]" "${BATS_TEST_TMPDIR}/run/task.txt"
}

@test "cog executor-prex-parse-args handles auto and unknown flags" {
  run cog executor-prex-parse-args --json "${BATS_TEST_TMPDIR}/run2" "--auto Task"
  assert_success
  printf '%s\n' "$output" | jq -e '.mode == "auto-approve"' >/dev/null

  run --separate-stderr cog executor-prex-parse-args --json "${BATS_TEST_TMPDIR}/run2" "--bad Task"
  assert_failure 2
  [[ $stderr == *"unknown executor-prex flag"* ]]
}

@test "cog executor-prex-parse-args rejects the removed tsk-impl flag" {
  run --separate-stderr cog executor-prex-parse-args --json "${BATS_TEST_TMPDIR}/run2" "-t ISSUE-1 Task"
  assert_failure 2
  [[ $stderr == *"unknown executor-prex flag"* ]]
}

@test "cog executor-prex-parse-args --help dispatches" {
  run cog executor-prex-parse-args --help

  assert_success
  [[ $output == *"executor-prex"* ]]
}
