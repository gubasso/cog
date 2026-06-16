setup() {
  bats_require_minimum_version 1.5.0
  load '../test_helper/common-setup'
  _common_setup
  export HOME="${BATS_TEST_TMPDIR}/home"
  export XDG_STATE_HOME="${BATS_TEST_TMPDIR}/state"
  export XDG_RUNTIME_DIR="${BATS_TEST_TMPDIR}/runtime"
  mkdir -p "$HOME" "$XDG_STATE_HOME" "$XDG_RUNTIME_DIR"
}

@test "cog rundir creates a run directory" {
  run cog rundir review

  assert_success
  assert_line --regexp '^RUN_DIR=.*review-'
  local run_dir="${output#RUN_DIR=}"
  [ -d "$run_dir" ]
}

@test "cog rundir locks and emits JSON" {
  run cog rundir review --lock --owner-pid 123 --json

  assert_success
  printf '%s\n' "$output" | jq -e '.run_dir and .lock_file' >/dev/null
  [ -f "$(printf '%s\n' "$output" | jq -r '.lock_file')" ]
}

@test "cog rundir requires owner pid when locking" {
  run --separate-stderr cog rundir review --lock

  assert_failure
  [[ $stderr == *"err.kind: MissingArgument"* ]]
}

@test "cog rundir --help dispatches" {
  run cog rundir --help

  assert_success
  [[ $output == *"Create a workflow run directory"* ]]
}
