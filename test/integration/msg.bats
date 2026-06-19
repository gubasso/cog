setup() {
  bats_require_minimum_version 1.5.0
  load '../test_helper/common-setup'
  _common_setup
}

@test "cog msg machine lines use stdout only" {
  run --separate-stderr cog msg resolved /tmp/out
  assert_success
  assert_output "RESOLVED /tmp/out"
  [ -z "$stderr" ]

  run --separate-stderr cog msg ok commit-push "done"
  assert_success
  assert_output "COMMIT_PUSH_OK done"
  [ -z "$stderr" ]

  run --separate-stderr cog msg failed commit-push denied
  assert_success
  assert_output "COMMIT_PUSH_FAILED denied"
  [ -z "$stderr" ]

  run --separate-stderr cog msg kv Mixed-Key value
  assert_success
  assert_output "Mixed-Key=value"
  [ -z "$stderr" ]
}

@test "cog msg warn and error use stderr" {
  run --separate-stderr cog msg warn careful
  assert_success
  [ -z "$output" ]
  [ "$stderr" = "Warning: careful" ]

  run --separate-stderr cog msg error build broken
  assert_failure 70
  [ -z "$output" ]
  [ "$stderr" = "build: broken" ]
}

@test "cog msg stage and info are unknown kinds" {
  run --separate-stderr cog msg stage working
  assert_failure
  [ -z "$output" ]
  [[ $stderr == *"err.kind: BadMsgKind"* ]]

  run --separate-stderr cog msg info hello
  assert_failure
  [ -z "$output" ]
  [[ $stderr == *"err.kind: BadMsgKind"* ]]
}
