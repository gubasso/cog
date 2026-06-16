setup() {
  bats_require_minimum_version 1.5.0
  load '../test_helper/common-setup'
  _common_setup
  export LIB_DIR="${BATS_TEST_DIRNAME}/../../lib"
  # shellcheck source=/dev/null
  source "${LIB_DIR}/helpers.sh"
  # shellcheck source=/dev/null
  source "${LIB_DIR}/loader.sh"
}

@test "unknown command exits with usage and structured error" {
  run --separate-stderr cog::loader::dispatch nope

  assert_failure 64
  [[ $stderr == *"err.kind: UnknownCommand"* ]]
  [[ $stderr == *"command: nope"* ]]
}

@test "placeholder command dispatches successfully" {
  run cog::loader::dispatch noop

  assert_success
  assert_output "noop"
}
