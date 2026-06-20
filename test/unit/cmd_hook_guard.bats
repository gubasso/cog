setup() {
  bats_require_minimum_version 1.5.0
  load '../test_helper/common-setup'
  _common_setup
  export LIB_DIR="${BATS_TEST_DIRNAME}/../../lib"
  export HOME="${BATS_TEST_TMPDIR}/home"
  export XDG_STATE_HOME="${BATS_TEST_TMPDIR}/state"
  unset XDG_RUNTIME_DIR
  mkdir -p "$HOME" "$XDG_STATE_HOME"
  source "${LIB_DIR}/helpers.sh"
  source "${LIB_DIR}/functions/fn_ui_print.sh"
  source "${LIB_DIR}/functions/fn_log.sh"
  source "${LIB_DIR}/functions/fn_error_raise.sh"
  source "${LIB_DIR}/functions/fn_json_write.sh"
  source "${LIB_DIR}/functions/fn_rundir.sh"
  source "${LIB_DIR}/commands/cmd_hook_guard.sh"
}

guard_stop_direct() {
  printf '{}' | cog::cmd::hook_guard executor-prex-stop --owner-pid "$1"
}

@test "hook_guard rejects unknown action with hook usage status" {
  run --separate-stderr cog::cmd::hook_guard nope

  assert_failure 1
}

@test "hook_guard executor-prex-stop rejects unknown option with hook usage status" {
  run --separate-stderr cog::cmd::hook_guard executor-prex-stop --bogus

  assert_failure 1
}

@test "hook_guard direct help lists stop hook action only" {
  run cog::cmd::hook_guard --help

  assert_success
  [[ $output == *"executor-prex-stop"* ]]
  [[ $output != *"codex-foreground"* ]]
}

@test "hook_guard executor-prex-stop returns hook block status directly" {
  local run_dir="${BATS_TEST_TMPDIR}/executor-prex-123"
  local lock_file
  mkdir -p "$run_dir"
  lock_file="$(cog::fn::rundir_lock_acquire "$run_dir" "$$")"

  run --separate-stderr guard_stop_direct "$$"

  assert_failure 2
  [[ $stderr == *'"decision":"block"'* ]]
  rm -rf "$run_dir" "$lock_file"
}

@test "hook_guard executor-prex-stop blocks when stage3 artifact is missing" {
  local run_dir="${BATS_TEST_TMPDIR}/executor-prex-stage3-missing"
  local lock_file
  mkdir -p "$run_dir"
  lock_file="$(cog::fn::rundir_lock_acquire "$run_dir" "$$")"
  printf '%s\n' x >"$run_dir/stage1-plan.txt"
  printf '%s\n' x >"$run_dir/stage2-reviewed-plan.md"
  printf '%s\n' x >"$run_dir/stage4-review.md"

  run --separate-stderr guard_stop_direct "$$"

  assert_failure 2
  [[ $stderr == *"Stage 3: Implementation report"* ]]
  rm -rf "$run_dir" "$lock_file"
}

@test "hook_guard executor-prex-stop allows when all required artifacts exist" {
  local run_dir="${BATS_TEST_TMPDIR}/executor-prex-complete"
  local lock_file
  mkdir -p "$run_dir"
  lock_file="$(cog::fn::rundir_lock_acquire "$run_dir" "$$")"
  printf '%s\n' x >"$run_dir/stage1-plan.txt"
  printf '%s\n' x >"$run_dir/stage2-reviewed-plan.md"
  printf '%s\n' x >"$run_dir/stage3-impl-report.txt"
  printf '%s\n' x >"$run_dir/stage4-review.md"

  run guard_stop_direct "$$"

  assert_success
  rm -rf "$run_dir" "$lock_file"
}
