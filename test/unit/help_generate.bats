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
  source "${LIB_DIR}/functions/fn_help_generate.sh"
}

@test "root help includes usage flags and generated noop description" {
  run cog::fn::help_generate root

  assert_success
  [[ $output == *"Usage: cog"* ]]
  [[ $output == *"--json"* ]]
  [[ $output == *"noop"* ]]
  [[ $output == *"Exercise command dispatch without side effects."* ]]
}

@test "command help includes line two description" {
  run cog::fn::help_generate command noop

  assert_success
  [[ $output == *"Usage: cog noop [args]"* ]]
  [[ $output == *"Exercise command dispatch without side effects."* ]]
}

@test "unknown command help fails with usage" {
  run --separate-stderr cog::fn::help_generate command nope

  assert_failure 64
  [[ $stderr == *"err.kind: UnknownCommand"* ]]
}

@test "bad command slug fails with usage" {
  run --separate-stderr cog::fn::help_generate command ../nope

  assert_failure 64
  [[ $stderr == *"err.kind: BadCommandName"* ]]
}

@test "missing desc sentinel fails with software error" {
  local tmp_lib="${BATS_TEST_TMPDIR}/lib"
  mkdir -p "${tmp_lib}/commands"
  printf '%s\n' '# shellcheck shell=bash' 'cog::cmd::bad() { :; }' >"${tmp_lib}/commands/cmd_bad.sh"
  LIB_DIR="$tmp_lib"

  run --separate-stderr cog::fn::help_generate command bad

  assert_failure 70
  [[ $stderr == *"err.kind: CommandDescriptionMissing"* ]]
}
