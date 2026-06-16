setup() {
  bats_require_minimum_version 1.5.0
  load '../test_helper/common-setup'
  _common_setup
  export HOME="${BATS_TEST_TMPDIR}/home"
  export XDG_STATE_HOME="${BATS_TEST_TMPDIR}/state"
  export XDG_RUNTIME_DIR="${BATS_TEST_TMPDIR}/runtime"
  mkdir -p "$HOME" "$XDG_STATE_HOME" "$XDG_RUNTIME_DIR" "${BATS_TEST_TMPDIR}/run-review-123"
}

@test "cog lock acquire emits lock file" {
  run cog lock acquire "${BATS_TEST_TMPDIR}/run-review-123" --owner-pid 123

  assert_success
  assert_line --regexp '^LOCK_FILE='
  [ -f "${output#LOCK_FILE=}" ]
}

@test "cog lock acquire rejects held lock" {
  run cog lock acquire "${BATS_TEST_TMPDIR}/run-review-123" --owner-pid 123
  assert_success

  run --separate-stderr cog lock acquire "${BATS_TEST_TMPDIR}/run-review-123" --owner-pid 123
  assert_failure
  [[ $stderr == *"err.kind: RunDirLockExists"* ]]
}

@test "cog lock release removes lock" {
  run cog lock acquire "${BATS_TEST_TMPDIR}/run-review-123" --owner-pid 123
  assert_success
  local lock_file="${output#LOCK_FILE=}"

  run cog lock release "$lock_file"
  assert_success
  [ ! -e "$lock_file" ]
}

@test "cog lock --help dispatches" {
  run cog lock --help

  assert_success
  [[ $output == *"Acquire or release"* ]]
}
