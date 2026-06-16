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
}

@test "error kinds map to sysexits" {
  [ "$(cog::fn::error_exit_for_kind MissingCommand)" -eq 64 ]
  [ "$(cog::fn::error_exit_for_kind InvalidJsonInput)" -eq 65 ]
  [ "$(cog::fn::error_exit_for_kind InputNotFound)" -eq 66 ]
  [ "$(cog::fn::error_exit_for_kind MissingRequirement)" -eq 69 ]
  [ "$(cog::fn::error_exit_for_kind InvalidJsonOutput)" -eq 70 ]
  [ "$(cog::fn::error_exit_for_kind JsonWriteFailed)" -eq 74 ]
  [ "$(cog::fn::error_exit_for_kind InvalidConfigValue)" -eq 78 ]
}

@test "error_raise renders four-part anatomy and exits mapped code" {
  run --separate-stderr cog::fn::error_raise UnknownCommand \
    "unknown command" "command: nope" "no readable command module was found" "check the command name and retry"

  assert_failure 64
  [ -z "$output" ]
  [[ $stderr == *"cog: unknown command"* ]]
  [[ $stderr == *"  err.kind: UnknownCommand"* ]]
  [[ $stderr == *"  where: command: nope"* ]]
  [[ $stderr == *"  why: no readable command module was found"* ]]
  [[ $stderr == *"  hint: check the command name and retry"* ]]
}
