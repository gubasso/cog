setup() {
  bats_require_minimum_version 1.5.0
  load '../test_helper/common-setup'
  _common_setup
  export LIB_DIR="${BATS_TEST_DIRNAME}/../../lib"
  export HOME="${BATS_TEST_TMPDIR}/home"
  export XDG_STATE_HOME="${BATS_TEST_TMPDIR}/state"
  mkdir -p "$HOME" "$XDG_STATE_HOME"
  source "${LIB_DIR}/helpers.sh"
  source "${LIB_DIR}/functions/fn_ui_print.sh"
  source "${LIB_DIR}/functions/fn_log.sh"
  source "${LIB_DIR}/functions/fn_error_raise.sh"
  source "${LIB_DIR}/functions/fn_json_write.sh"
  source "${LIB_DIR}/functions/fn_rundir.sh"
  source "${LIB_DIR}/commands/cmd_rundir.sh"
}

@test "rundir JSON helper encodes null lock" {
  run __cog_rundir_emit_json /tmp/run ""

  assert_success
  printf '%s\n' "$output" | jq -e '.run_dir == "/tmp/run" and .lock_file == null' >/dev/null
}

@test "rundir rejects duplicate prefix" {
  run --separate-stderr cog::cmd::rundir one two

  assert_failure 64
  [[ $stderr == *"err.kind: TooManyArguments"* ]]
}

@test "rundir requires owner pid with lock" {
  run --separate-stderr cog::cmd::rundir one --lock

  assert_failure 64
  [[ $stderr == *"err.kind: MissingArgument"* ]]
}

@test "rundir --base prints the run base path" {
  run cog::cmd::rundir --base

  assert_success
  [[ $output == "${XDG_STATE_HOME}/cog/runs" ]]
}

@test "rundir --base --json emits the base as JSON" {
  run cog::cmd::rundir --base --json

  assert_success
  printf '%s\n' "$output" | jq -e --arg b "${XDG_STATE_HOME}/cog/runs" '.base == $b' >/dev/null
}

@test "rundir --base rejects a prefix" {
  run --separate-stderr cog::cmd::rundir --base foo

  assert_failure 65
  [[ $stderr == *"err.kind: InvalidInput"* ]]
}

@test "rundir --base rejects --lock" {
  run --separate-stderr cog::cmd::rundir --base --lock

  assert_failure 65
  [[ $stderr == *"err.kind: InvalidInput"* ]]
}
