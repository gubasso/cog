setup() {
  bats_require_minimum_version 1.5.0
  load '../test_helper/common-setup'
  _common_setup
}

@test "cog runner-commit-parse extracts commit sha" {
  local out="${BATS_TEST_TMPDIR}/gc.out"
  printf '%s\n' "noise" "COMMIT_PUSH_OK abc1234 pushed" >"$out"

  run cog runner-commit-parse "$out" --json

  assert_success
  printf '%s\n' "$output" | jq -e '.ok == true and .commits[0].sha == "abc1234" and (.commits[0].line | startswith("COMMIT_PUSH_OK"))' >/dev/null
}

@test "cog runner-commit-parse emits a single bare line as one commit" {
  local out="${BATS_TEST_TMPDIR}/gc.out"
  printf '%s\n' "COMMIT_OK abc1234" >"$out"

  run cog runner-commit-parse "$out"

  assert_success
  assert_output "COMMIT_SHA=abc1234"

  run cog runner-commit-parse "$out" --json

  assert_success
  printf '%s\n' "$output" | jq -e '.ok == true and (.commits | type == "array") and .commits[0].sha == "abc1234" and .commits[0].repo == "" and .commits[0].line == "COMMIT_OK abc1234"' >/dev/null
}

@test "cog runner-commit-parse emits multi-repo lines and json" {
  local out="${BATS_TEST_TMPDIR}/gc.out"
  printf '%s\n' \
    "COMMIT_OK abc1234 repo=/repo/a" \
    "COMMIT_PUSH_OK def4567 repo=/repo/b" >"$out"

  run cog runner-commit-parse "$out"

  assert_success
  assert_line "COMMIT_SHA=abc1234 repo=/repo/a"
  assert_line "COMMIT_SHA=def4567 repo=/repo/b"

  run cog runner-commit-parse "$out" --json

  assert_success
  printf '%s\n' "$output" | jq -e '
    .ok == true and
    (.commits | type == "array") and
    (.commits[] | select(.repo == "/repo/a" and .sha == "abc1234")) and
    (.commits[] | select(.repo == "/repo/b" and .sha == "def4567"))
  ' >/dev/null
}

@test "cog runner-commit-parse fails if any repo failed" {
  local out="${BATS_TEST_TMPDIR}/gc.out"
  printf '%s\n' "COMMIT_OK abc1234 repo=/repo/a" "COMMIT_FAILED hook repo=/repo/b log=/tmp/log" >"$out"

  run --separate-stderr cog runner-commit-parse "$out" --json

  assert_failure
  [[ $stderr == *"gc commit failed"* ]]
}

@test "cog runner-commit-parse rejects failures and missing lines" {
  local out="${BATS_TEST_TMPDIR}/gc.out"
  printf '%s\n' "COMMIT_FAILED hook" >"$out"

  run --separate-stderr cog runner-commit-parse "$out" --json
  assert_failure
  [[ $stderr == *"gc commit failed"* ]]

  printf '%s\n' "no commit" >"$out"
  run --separate-stderr cog runner-commit-parse "$out" --json
  assert_failure
  [[ $stderr == *"missing COMMIT_* line"* ]]
}

@test "cog runner-commit-parse --help dispatches" {
  run cog runner-commit-parse --help

  assert_success
  [[ $output == *"Parse runner commit"* ]]
}

@test "cog runner-commit-parse recognizes the COMMIT_OK empty marker" {
  local out="${BATS_TEST_TMPDIR}/gc.out"
  printf '%s\n' "COMMIT_OK empty" >"$out"

  run cog runner-commit-parse "$out" --json
  assert_success
  printf '%s\n' "$output" | jq -e '.ok == true and .empty == true and (.commits == [])' >/dev/null

  run cog runner-commit-parse "$out"
  assert_success
}

@test "cog runner-commit-parse reports empty:false for a real commit" {
  local out="${BATS_TEST_TMPDIR}/gc.out"
  printf '%s\n' "COMMIT_OK abc1234" >"$out"

  run cog runner-commit-parse "$out" --json
  assert_success
  printf '%s\n' "$output" | jq -e '.ok == true and .empty == false and (.commits[0].sha == "abc1234")' >/dev/null
}
