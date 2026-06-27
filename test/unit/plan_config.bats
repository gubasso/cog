# The cfg/src/line arrays are populated by namerefs inside
# cog::fn::plan_config_load, so shellcheck cannot see their use and reports
# false SC2034 "appears unused" for every test.
# shellcheck disable=SC2034

setup() {
  bats_require_minimum_version 1.5.0
  load '../test_helper/common-setup'
  _common_setup
  export HOME="${BATS_TEST_TMPDIR}/home"
  export XDG_DATA_HOME="${BATS_TEST_TMPDIR}/data"
  export XDG_STATE_HOME="${BATS_TEST_TMPDIR}/state"
  export XDG_CONFIG_HOME="${BATS_TEST_TMPDIR}/config"
  mkdir -p "$HOME" "$XDG_DATA_HOME" "$XDG_STATE_HOME" "$XDG_CONFIG_HOME/cog/conf.d"
  # shellcheck source=/dev/null
  source "${BATS_TEST_DIRNAME}/../../lib/helpers.sh"
  # shellcheck source=/dev/null
  source "${BATS_TEST_DIRNAME}/../../lib/functions/fn_ui_print.sh"
  # shellcheck source=/dev/null
  source "${BATS_TEST_DIRNAME}/../../lib/functions/fn_error_raise.sh"
  # shellcheck source=/dev/null
  source "${BATS_TEST_DIRNAME}/../../lib/functions/fn_plan_config.sh"
}

@test "plan config defaults to auto strict local dir" {
  local repo="${BATS_TEST_TMPDIR}/repo"
  mkdir -p "$repo"
  local -A cfg=() src=() line=()

  cog::fn::plan_config_load "$repo" cfg src line

  assert_equal "${cfg[COG_PLAN_STORE]}" "auto"
  assert_equal "${cfg[COG_PLAN_TRUST]}" "strict"
  assert_equal "${cfg[COG_PLAN_LOCAL_DIR]}" ".cog/plans"
}

@test "plan config precedence is user overlay project env" {
  local repo="${BATS_TEST_TMPDIR}/repo"
  mkdir -p "$repo/.cog"
  printf '%s\n' "COG_PLAN_STORE='global'" >"${XDG_CONFIG_HOME}/cog/config.sh"
  printf '%s\n' "COG_PLAN_STORE='auto'" >"${XDG_CONFIG_HOME}/cog/conf.d/10-overlay.sh"
  printf '%s\n' "COG_PLAN_STORE='local'" >"${repo}/.cog/config.sh"
  # shellcheck disable=SC2030 # Each bats @test runs in its own subshell; exporting the env layer here is intentional.
  export COG_PLAN_STORE=global
  local -A cfg=() src=() line=()

  cog::fn::plan_config_load "$repo" cfg src line

  assert_equal "${cfg[COG_PLAN_STORE]}" "global"
  assert_equal "${src[COG_PLAN_STORE]}" "env:COG_PLAN_STORE"
}

@test "plan config ceiling stops project walk" {
  local repo="${BATS_TEST_TMPDIR}/repo"
  mkdir -p "$repo/.cog" "$repo/sub"
  printf '%s\n' "COG_PLAN_STORE='local'" >"${repo}/.cog/config.sh"
  export COG_PLAN_CEILING="${repo}/sub"
  local -A cfg=() src=() line=()

  cog::fn::plan_config_load "${repo}/sub" cfg src line

  # shellcheck disable=SC2031 # COG_PLAN_STORE here is an array key, not the env var exported in another @test subshell.
  assert_equal "${cfg[COG_PLAN_STORE]}" "auto"
}

@test "plan config ceiling from user config stops project walk" {
  local repo="${BATS_TEST_TMPDIR}/repo"
  mkdir -p "$repo/.cog" "$repo/sub"
  printf '%s\n' "COG_PLAN_STORE='local'" >"${repo}/.cog/config.sh"
  printf '%s\n' "COG_PLAN_CEILING='${repo}/sub'" >"${XDG_CONFIG_HOME}/cog/config.sh"
  local -A cfg=() src=() line=()

  cog::fn::plan_config_load "${repo}/sub" cfg src line

  # shellcheck disable=SC2031 # COG_PLAN_STORE here is an array key, not the env var exported in another @test subshell.
  assert_equal "${cfg[COG_PLAN_STORE]}" "auto"
}

@test "bad COG_PLAN_STORE is InvalidConfigValue" {
  local repo="${BATS_TEST_TMPDIR}/repo"
  mkdir -p "$repo/.cog"
  printf '%s\n' "COG_PLAN_STORE='sideways'" >"${repo}/.cog/config.sh"
  local -A cfg=() src=() line=()

  run --separate-stderr cog::fn::plan_config_load "$repo" cfg src line

  assert_failure 78
  [[ $stderr == *"err.kind: InvalidConfigValue"* ]]
}

@test "scoped scanner rejects non-plan keys" {
  local repo="${BATS_TEST_TMPDIR}/repo"
  mkdir -p "$repo/.cog"
  printf '%s\n' "json=true" >"${repo}/.cog/config.sh"
  local -A cfg=() src=() line=()

  run --separate-stderr cog::fn::plan_config_load "$repo" cfg src line

  assert_failure 78
  [[ $stderr == *"err.kind: UnknownConfigKey"* ]]
}
