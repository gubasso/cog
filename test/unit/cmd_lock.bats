setup() {
  bats_require_minimum_version 1.5.0
  load '../test_helper/common-setup'
  _common_setup
  export LIB_DIR="${BATS_TEST_DIRNAME}/../../lib"
  export HOME="${BATS_TEST_TMPDIR}/home"
  export XDG_STATE_HOME="${BATS_TEST_TMPDIR}/state"
  export XDG_RUNTIME_DIR="${BATS_TEST_TMPDIR}/runtime"
  mkdir -p "$HOME" "$XDG_STATE_HOME" "$XDG_RUNTIME_DIR"
  source "${LIB_DIR}/helpers.sh"
  source "${LIB_DIR}/functions/fn_ui_print.sh"
  source "${LIB_DIR}/functions/fn_log.sh"
  source "${LIB_DIR}/functions/fn_error_raise.sh"
  source "${LIB_DIR}/functions/fn_json_write.sh"
  source "${LIB_DIR}/functions/fn_rundir.sh"
  source "${LIB_DIR}/commands/cmd_lock.sh"
}

@test "lock rejects unknown mode" {
  run --separate-stderr cog::cmd::lock nope

  assert_failure 65
  [[ $stderr == *"err.kind: InvalidInput"* ]]
}

@test "lock acquire requires owner pid" {
  run --separate-stderr cog::cmd::lock acquire "${BATS_TEST_TMPDIR}/run"

  assert_failure 64
  [[ $stderr == *"err.kind: MissingArgument"* ]]
}

@test "lock release requires exactly one path" {
  run --separate-stderr cog::cmd::lock release

  assert_failure 64
  [[ $stderr == *"err.kind: MissingArgument"* ]]
}
