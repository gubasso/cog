setup() {
  bats_require_minimum_version 1.5.0
  load '../test_helper/common-setup'
  _common_setup
}

@test "cog plan-queue-runner-parse-commit extracts commit sha" {
  local out="${BATS_TEST_TMPDIR}/gc.out"
  printf '%s\n' "noise" "COMMIT_PUSH_OK abc1234 pushed" >"$out"

  run cog plan-queue-runner-parse-commit "$out" --json

  assert_success
  printf '%s\n' "$output" | jq -e '.commit_sha == "abc1234" and (.line | startswith("COMMIT_PUSH_OK"))' >/dev/null
}

@test "cog plan-queue-runner-parse-commit rejects failures and missing lines" {
  local out="${BATS_TEST_TMPDIR}/gc.out"
  printf '%s\n' "COMMIT_FAILED hook" >"$out"

  run --separate-stderr cog plan-queue-runner-parse-commit "$out" --json
  assert_failure
  [[ $stderr == *"gc commit failed"* ]]

  printf '%s\n' "no commit" >"$out"
  run --separate-stderr cog plan-queue-runner-parse-commit "$out" --json
  assert_failure
  [[ $stderr == *"missing COMMIT_* line"* ]]
}

@test "cog plan-queue-runner-parse-commit --help dispatches" {
  run cog plan-queue-runner-parse-commit --help

  assert_success
  [[ $output == *"Parse a plan-queue-runner"* ]]
}
