setup() {
  bats_require_minimum_version 1.5.0
  load '../test_helper/common-setup'
  _common_setup
  # shellcheck source=/dev/null
  source "${BATS_TEST_DIRNAME}/../../lib/helpers.sh"
}

@test "die renders structured error to stderr and exits with requested code" {
  run --separate-stderr cog::helpers::die "$EX_USAGE" "UnknownCommand" \
    "unknown command" "command: nope" \
    "no readable command module was found" "check the command name and retry"

  assert_failure 64
  [[ "$stderr" == *"cog: unknown command"* ]]
  [[ "$stderr" == *"  err.kind: UnknownCommand"* ]]
  [[ "$stderr" == *"  where: command: nope"* ]]
  [[ "$stderr" == *"  why: no readable command module was found"* ]]
  [[ "$stderr" == *"  hint: check the command name and retry"* ]]
}

@test "__require succeeds for available commands" {
  run __require printf

  assert_success
}

@test "__require reports missing commands with sysexit unavailable" {
  run --separate-stderr __require __definitely_not_a_real_cmd_xyz

  assert_failure 69
  [[ "$stderr" == *"err.kind: MissingRequirement"* ]]
}

@test "sysexits constants have expected values" {
  [ "$EX_OK" -eq 0 ]
  [ "$EX_USAGE" -eq 64 ]
  [ "$EX_DATAERR" -eq 65 ]
  [ "$EX_NOINPUT" -eq 66 ]
  [ "$EX_UNAVAILABLE" -eq 69 ]
  [ "$EX_SOFTWARE" -eq 70 ]
  [ "$EX_IOERR" -eq 74 ]
  [ "$EX_CONFIG" -eq 78 ]
}
