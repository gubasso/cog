setup() {
  bats_require_minimum_version 1.5.0
  load '../test_helper/common-setup'
  _common_setup
  export LIB_DIR="${BATS_TEST_DIRNAME}/../../lib"
  export HOME="${BATS_TEST_TMPDIR}/home"
  export XDG_STATE_HOME="${BATS_TEST_TMPDIR}/state"
  export XDG_RUNTIME_DIR="${BATS_TEST_TMPDIR}/runtime"
  mkdir -p "$HOME" "$XDG_STATE_HOME" "$XDG_RUNTIME_DIR"
  # shellcheck source=/dev/null
  source "${LIB_DIR}/helpers.sh"
  # shellcheck source=/dev/null
  source "${LIB_DIR}/functions/fn_rundir.sh"
}

@test "rundir_base uses cog-owned state path" {
  run cog::fn::rundir_base

  assert_success
  assert_output "${XDG_STATE_HOME}/cog/runs"
}

@test "rundir_create creates prefixed run directory" {
  run cog::fn::rundir_create prex

  assert_success
  [[ $output == "${XDG_STATE_HOME}/cog/runs/prex-"* ]]
  [ -d "$output" ]
}

@test "rundir_path joins without creating files" {
  run cog::fn::rundir_path "${BATS_TEST_TMPDIR}/run" events.jsonl

  assert_success
  assert_output "${BATS_TEST_TMPDIR}/run/events.jsonl"
  [ ! -e "${BATS_TEST_TMPDIR}/run/events.jsonl" ]
}

@test "rundir_lock_name emits the prex lock prefix" {
  run cog::fn::rundir_lock_name

  assert_success
  assert_output "prex-active"
}

@test "rundir_lock_path defaults to the lock-name source of truth" {
  local run_dir="${BATS_TEST_TMPDIR}/run-prex-123"

  run cog::fn::rundir_lock_path "$run_dir"

  assert_success
  assert_output "${XDG_RUNTIME_DIR}/prex-active-123.lock"
}

@test "rundir_lock_path accepts an explicit lock name override" {
  local run_dir="${BATS_TEST_TMPDIR}/run-prex-123"

  run cog::fn::rundir_lock_path "$run_dir" alternate

  assert_success
  assert_output "${XDG_RUNTIME_DIR}/alternate-123.lock"
}

@test "rundir lock acquire is atomic and release removes lock" {
  local run_dir="${BATS_TEST_TMPDIR}/run-prex-123"
  mkdir -p "$run_dir"

  run cog::fn::rundir_lock_acquire "$run_dir" "$$"
  assert_success
  local lock_file="$output"
  [ -f "$lock_file" ]

  run --separate-stderr cog::fn::rundir_lock_acquire "$run_dir" "$$" "$lock_file"
  assert_failure 74
  [[ $stderr == *"err.kind: RunDirLockExists"* ]]

  run cog::fn::rundir_lock_release "$lock_file"
  assert_success
  [ ! -e "$lock_file" ]
}

@test "rundir_snapshot and diff write outputs" {
  local run_dir="${BATS_TEST_TMPDIR}/run"
  local pre="${BATS_TEST_TMPDIR}/pre.snap"
  local post="${BATS_TEST_TMPDIR}/post.snap"
  local diff="${BATS_TEST_TMPDIR}/snap.diff"
  mkdir -p "$run_dir"
  printf '%s\n' one >"$run_dir/a.txt"

  cog::fn::rundir_snapshot "$run_dir" "$pre"
  printf '%s\n' two >"$run_dir/b.txt"
  cog::fn::rundir_snapshot "$run_dir" "$post"
  run cog::fn::rundir_snapshot_diff "$pre" "$post" "$diff"

  assert_success
  [ -s "$diff" ]
}

@test "rundir_require_file rejects missing and empty files" {
  local empty="${BATS_TEST_TMPDIR}/empty"
  : >"$empty"

  run --separate-stderr cog::fn::rundir_require_file "$empty" output

  assert_failure 66
  [[ $stderr == *"err.kind: InputUnreadable"* ]]
}
