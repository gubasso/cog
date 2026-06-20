setup() {
  bats_require_minimum_version 1.5.0
  load '../test_helper/common-setup'
  _common_setup
  export LIB_DIR="${BATS_TEST_DIRNAME}/../../lib"
  export HOME="${BATS_TEST_TMPDIR}/home"
  export XDG_DATA_HOME="${BATS_TEST_TMPDIR}/xdg"
  export XDG_STATE_HOME="${BATS_TEST_TMPDIR}/state"
  mkdir -p "$HOME" "$XDG_STATE_HOME"
  # shellcheck source=/dev/null
  source "${LIB_DIR}/helpers.sh"
  # shellcheck source=/dev/null
  source "${LIB_DIR}/functions/fn_ui_print.sh"
  # shellcheck source=/dev/null
  source "${LIB_DIR}/functions/fn_log.sh"
  # shellcheck source=/dev/null
  source "${LIB_DIR}/functions/fn_error_raise.sh"
  # shellcheck source=/dev/null
  source "${LIB_DIR}/functions/fn_skill_refs.sh"
  # shellcheck source=/dev/null
  source "${LIB_DIR}/commands/cmd_skill_refs.sh"
}

normalize_path() {
  cd -P "$1" && pwd
}

@test "skill-refs root command emits resolved root" {
  local xdg_root="${XDG_DATA_HOME}/cog/skill-refs"
  mkdir -p "$xdg_root"

  run cog::cmd::skill_refs root

  assert_success
  assert_output "$(normalize_path "$xdg_root")"
}

@test "skill-refs path command emits resolved path" {
  local xdg_root="${XDG_DATA_HOME}/cog/skill-refs"
  mkdir -p "$xdg_root/foo"
  printf '%s\n' "ref" >"${xdg_root}/foo/bar.md"

  run cog::cmd::skill_refs path foo/bar.md

  assert_success
  assert_output "$(normalize_path "$xdg_root")/foo/bar.md"
}

@test "skill-refs root command fails closed when unresolved" {
  export LIB_DIR="${BATS_TEST_TMPDIR}/app/lib"

  run --separate-stderr cog::cmd::skill_refs root

  assert_failure
  [[ $stderr == *"err.kind: InputNotFound"* ]]
}

@test "skill-refs path validates missing rel and unknown subcommand" {
  run --separate-stderr cog::cmd::skill_refs path
  assert_failure
  [[ $stderr == *"err.kind: MissingArgument"* ]]

  run --separate-stderr cog::cmd::skill_refs bogus
  assert_failure
  [[ $stderr == *"err.kind: InvalidInput"* ]]
}

@test "skill-refs reports missing subcommand as MissingArgument" {
  run --separate-stderr cog::cmd::skill_refs
  assert_failure
  [[ $stderr == *"err.kind: MissingArgument"* ]]
}

@test "skill-refs rejects surplus positional arguments" {
  run --separate-stderr cog::cmd::skill_refs path foo/bar.md extra
  assert_failure
  [[ $stderr == *"err.kind: TooManyArguments"* ]]

  run --separate-stderr cog::cmd::skill_refs root extra
  assert_failure
  [[ $stderr == *"err.kind: TooManyArguments"* ]]
}
