setup() {
  bats_require_minimum_version 1.5.0
  load '../test_helper/common-setup'
  _common_setup
}

@test "cog require succeeds quietly for present commands" {
  run --separate-stderr cog require msg doctor

  assert_success
  [ -z "$output" ]
  [ -z "$stderr" ]
}

@test "cog require reports missing commands" {
  run --separate-stderr cog require missing-command

  assert_failure
  [ "$stderr" = "MISSING missing-command" ]
}

@test "cog require --json partitions present and missing" {
  run --separate-stderr cog require --json msg missing-command

  assert_failure
  [ -z "$stderr" ]
  printf '%s\n' "$output" | jq -e '.ok == false and .present == ["msg"] and .missing == ["missing-command"]' >/dev/null
}

@test "cog require --help dispatches" {
  run cog require --help

  assert_success
  [[ $output == *"Assert required cog subcommands"* ]]
}
