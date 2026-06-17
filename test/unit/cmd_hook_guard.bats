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

guard_fg_direct() {
  printf '%s' "$1" | cog::cmd::hook_guard codex-foreground
}

guard_stop_direct() {
  printf '{}' | cog::cmd::hook_guard prex-stop --owner-pid "$1"
}

@test "hook_guard rejects unknown action with hook usage status" {
  run --separate-stderr cog::cmd::hook_guard nope

  assert_failure 1
}

@test "hook_guard prex-stop rejects unknown option with hook usage status" {
  run --separate-stderr cog::cmd::hook_guard prex-stop --bogus

  assert_failure 1
}

@test "hook_guard direct help lists both hook actions" {
  run cog::cmd::hook_guard --help

  assert_success
  [[ $output == *"codex-foreground"* ]]
  [[ $output == *"prex-stop"* ]]
}

@test "hook_guard codex-foreground returns hook block status directly" {
  run --separate-stderr guard_fg_direct '{"tool_input":{"command":"cog codex-runner run-resume","run_in_background":true,"timeout":600000}}'

  assert_failure 2
  [[ $stderr == *"BLOCKED"* ]]
}

@test "hook_guard codex-foreground allows codex-session package path mentions" {
  run guard_fg_direct '{"tool_input":{"command":"git diff -- lib/commands codex-session","run_in_background":true,"timeout":120000}}'
  assert_success

  run guard_fg_direct '{"tool_input":{"command":"cat codex-session/foo","run_in_background":true,"timeout":120000}}'
  assert_success
}

@test "hook_guard codex-foreground allows fast codex-runner probes" {
  run guard_fg_direct '{"tool_input":{"command":"cog codex-runner gate sandbox out.json","timeout":120000}}'

  assert_success
}

@test "hook_guard codex-foreground allows quoted or echoed wrapper mentions" {
  run guard_fg_direct '{"tool_input":{"command":"echo cog codex-runner run-exec","timeout":120000}}'

  assert_success
}

@test "hook_guard codex-foreground matches multiline wrapper command position" {
  run --separate-stderr guard_fg_direct '{"tool_input":{"command":"RUNNER_MODE=native\ncog codex-runner run-exec","run_in_background":true,"timeout":600000}}'

  assert_failure 2
  [[ $stderr == *"BLOCKED"* ]]
}

@test "hook_guard codex-foreground matches separator wrapper command position" {
  run --separate-stderr guard_fg_direct '{"tool_input":{"command":"foo && cog codex-runner run-exec","timeout":120000}}'

  assert_failure 2
  [[ $stderr == *"600000"* ]]
}

@test "hook_guard codex-foreground matches subshell and trailing ampersand wrapper forms" {
  run --separate-stderr guard_fg_direct '{"tool_input":{"command":"(cog codex-runner run-exec)","timeout":120000}}'
  assert_failure 2

  run --separate-stderr guard_fg_direct '{"tool_input":{"command":"cog codex-runner run-exec&","timeout":120000}}'
  assert_failure 2
}

@test "hook_guard prex-stop returns hook block status directly" {
  local run_dir="${BATS_TEST_TMPDIR}/prex-123"
  local lock_file
  mkdir -p "$run_dir"
  lock_file="$(cog::fn::rundir_lock_acquire "$run_dir" "$$")"

  run --separate-stderr guard_stop_direct "$$"

  assert_failure 2
  [[ $stderr == *'"decision":"block"'* ]]
  rm -rf "$run_dir" "$lock_file"
}
