setup() {
  bats_require_minimum_version 1.5.0
  load '../test_helper/common-setup'
  _common_setup
}

@test "cog --version prints version" {
  run cog --version

  assert_success
  assert_output "0.1.0"
}

@test "cog noop dispatches placeholder command" {
  run cog noop

  assert_success
  assert_output "noop"
}

@test "cog unknown command reports structured error on stderr" {
  run --separate-stderr cog nope

  assert_failure 64
  [[ "$stderr" == *"err.kind: UnknownCommand"* ]]
}
