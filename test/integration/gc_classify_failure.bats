setup() {
  bats_require_minimum_version 1.5.0
  load '../test_helper/common-setup'
  _common_setup
}

@test "cog gc-classify-failure classifies content fixes" {
  local log="${BATS_TEST_TMPDIR}/failure.log"
  printf '%s\n' "shellcheck SC2086" >"$log"

  run cog gc-classify-failure --log "$log" --json

  assert_success
  printf '%s\n' "$output" | jq -e '.class == "content-fix" and .retryable == true' >/dev/null
}

@test "cog gc-classify-failure rejects unreadable logs" {
  run --separate-stderr cog gc-classify-failure --log "${BATS_TEST_TMPDIR}/missing.log" --json

  assert_failure
  [[ $stderr == *"err.kind: InputUnreadable"* ]]
}

@test "cog gc-classify-failure writes fragments" {
  local log="${BATS_TEST_TMPDIR}/failure.log"
  local out="${BATS_TEST_TMPDIR}/class.json"
  printf '%s\n' "non-fast-forward" >"$log"

  run cog gc-classify-failure --log "$log" "$out"

  assert_success
  assert_output "RESOLVED $out"
  jq -e '.class == "push-non-hook"' "$out" >/dev/null
}

@test "cog gc-classify-failure --help dispatches" {
  run cog gc-classify-failure --help

  assert_success
  [[ $output == *"Classify commit or push"* ]]
}
