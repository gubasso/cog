setup() {
  bats_require_minimum_version 1.5.0
  load '../test_helper/common-setup'
  _common_setup
  export LIB_DIR="${BATS_TEST_DIRNAME}/../../lib"
  # shellcheck source=/dev/null
  source "${LIB_DIR}/helpers.sh"
  # shellcheck source=/dev/null
  source "${LIB_DIR}/functions/fn_ui_print.sh"
  # shellcheck source=/dev/null
  source "${LIB_DIR}/functions/fn_error_raise.sh"
  # shellcheck source=/dev/null
  source "${LIB_DIR}/commands/cmd_msg.sh"
}

@test "msg ok without detail has no trailing space" {
  run --separate-stderr cog::cmd::msg ok commit-push

  assert_success
  assert_output "COMMIT_PUSH_OK"
  [ -z "$stderr" ]
}

@test "msg failed normalizes context and keeps reason" {
  run --separate-stderr cog::cmd::msg failed commit-push denied

  assert_success
  assert_output "COMMIT_PUSH_FAILED denied"
  [ -z "$stderr" ]
}

@test "msg kv preserves key verbatim" {
  run --separate-stderr cog::cmd::msg kv Mixed-Key value

  assert_success
  assert_output "Mixed-Key=value"
  [ -z "$stderr" ]
}

@test "msg fatal exits 70 not 1" {
  run --separate-stderr cog::cmd::msg fatal build broken

  assert_failure 70
  [ -z "$output" ]
  [ "$stderr" = "❌ build: broken" ]
}

@test "msg kv without value is a usage error" {
  run --separate-stderr cog::cmd::msg kv KEY

  assert_failure "$EX_USAGE"
  [ -z "$output" ]
  [[ $stderr == *"err.kind: MissingArgument"* ]]
}

@test "msg error without text is a usage error" {
  run --separate-stderr cog::cmd::msg error build

  assert_failure "$EX_USAGE"
  [ -z "$output" ]
  [[ $stderr == *"err.kind: MissingArgument"* ]]
}

@test "msg fatal without operands reports usage not software failure" {
  run --separate-stderr cog::cmd::msg fatal

  assert_failure "$EX_USAGE"
  [ -z "$output" ]
  [[ $stderr == *"err.kind: MissingArgument"* ]]
}
