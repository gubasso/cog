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
  [[ $stderr == *"err.kind: UnknownCommand"* ]]
}

@test "cog -vv --print-config shows cli log level provenance" {
  run cog -vv --print-config

  assert_success
  [[ $output == *"log_level=debug source=cli:-vv"* ]]
}

@test "cog --print-config shows env provenance" {
  run env COG_JSON=true cog --print-config

  assert_success
  [[ $output == *"json=true source=env:COG_JSON"* ]]
}

@test "cog print-config dispatches discoverable command" {
  run cog print-config

  assert_success
  [[ $output == *"dry_run=false source=default"* ]]
  [[ $output == *"json=false source=default"* ]]
  [[ $output == *"log_level=warn source=default"* ]]
}

@test "cog --json noop still dispatches placeholder command" {
  run cog --json noop

  assert_success
  assert_output "noop"
}

@test "cog --help noop shows command help instead of dispatching" {
  run cog --help noop

  assert_success
  [[ $output == *"Usage: cog noop [args]"* ]]
  [[ $output != "noop" ]]
}

@test "cog -h noop shows command help instead of dispatching" {
  run cog -h noop

  assert_success
  [[ $output == *"Usage: cog noop [args]"* ]]
}

@test "exported-but-empty COG_* env var is treated as unset" {
  run env COG_LOG_LEVEL= COG_JSON= cog --print-config

  assert_success
  [[ $output == *"json=false source=default"* ]]
  [[ $output == *"log_level=warn source=default"* ]]
}
