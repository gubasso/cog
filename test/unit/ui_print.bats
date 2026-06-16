# Arrays passed to cog::fn::ui_init are consumed via namerefs, so shellcheck
# cannot see their use in tests.
# shellcheck disable=SC2034

setup() {
  bats_require_minimum_version 1.5.0
  load '../test_helper/common-setup'
  _common_setup
  export LIB_DIR="${BATS_TEST_DIRNAME}/../../lib"
  # shellcheck source=/dev/null
  source "${LIB_DIR}/functions/fn_ui_print.sh"
}

@test "ui_data writes to stdout only" {
  run --separate-stderr cog::fn::ui_data "VALUE"

  assert_success
  assert_output "VALUE"
  [ -z "$stderr" ]
}

@test "ui_human writes to stderr only" {
  run --separate-stderr cog::fn::ui_human "hello"

  assert_success
  [ -z "$output" ]
  [ "$stderr" = "hello" ]
}

@test "NO_COLOR disables color" {
  # shellcheck disable=SC2034 # Nameref arguments are read by cog::fn::ui_init.
  local -A ctx=([json]=false)
  # shellcheck disable=SC2034 # Nameref arguments are read by cog::fn::ui_init.
  local -A config=([json]=false)
  export NO_COLOR=1

  cog::fn::ui_init ctx config

  run cog::fn::ui_color_enabled stdout
  assert_failure
}

@test "captured non-tty streams do not enable color" {
  local -A ctx=([json]=false)
  local -A config=([json]=false)
  unset NO_COLOR FORCE_COLOR CLICOLOR_FORCE CLICOLOR

  cog::fn::ui_init ctx config

  [ "${COG_UI_COLOR_STDOUT}" = "false" ]
  [ "${COG_UI_COLOR_STDERR}" = "false" ]
}
