setup() {
  bats_require_minimum_version 1.5.0
  load '../test_helper/common-setup'
  _common_setup
  export LIB_DIR="${BATS_TEST_DIRNAME}/../../lib"
  export HOME="${BATS_TEST_TMPDIR}/home"
  mkdir -p "$HOME"
  unset XDG_CONFIG_HOME XDG_STATE_HOME XDG_CACHE_HOME XDG_DATA_HOME
  # shellcheck source=/dev/null
  source "${LIB_DIR}/helpers.sh"
  # shellcheck source=/dev/null
  source "${LIB_DIR}/functions/fn_ui_print.sh"
  # shellcheck source=/dev/null
  source "${LIB_DIR}/functions/fn_log.sh"
  # shellcheck source=/dev/null
  source "${LIB_DIR}/functions/fn_error_raise.sh"
  # shellcheck source=/dev/null
  source "${LIB_DIR}/functions/fn_json_write.sh"
  # shellcheck source=/dev/null
  source "${LIB_DIR}/functions/fn_prereq.sh"
}

@test "prereq_xdg_homes returns fallback homes" {
  local -A homes=()

  cog::fn::prereq_xdg_homes homes

  [ "${homes[config_home]}" = "${HOME}/.config" ]
  [ "${homes[state_home]}" = "${HOME}/.local/state" ]
  [ "${homes[cache_home]}" = "${HOME}/.cache" ]
  [ "${homes[data_home]}" = "${HOME}/.local/share" ]
}

@test "prereq_runtime_dirs returns cog-owned runtime dirs" {
  local -A dirs=()

  cog::fn::prereq_runtime_dirs dirs

  [ "${dirs[config]}" = "${HOME}/.config/cog" ]
  [ "${dirs[state]}" = "${HOME}/.local/state/cog" ]
  [ "${dirs[cache]}" = "${HOME}/.cache/cog" ]
  [ "${dirs[data]}" = "${HOME}/.local/share/cog" ]
}

@test "prereq_add_check omits empty optional fields" {
  local -a checks=()

  cog::fn::prereq_add_check checks "demo" "ok"

  printf '%s\n' "${checks[0]}" | jq -e '. == {"name":"demo","status":"ok"}' >/dev/null
}

@test "prereq_add_check includes non-empty optional fields" {
  local -a checks=()

  cog::fn::prereq_add_check checks "demo" "error" "broken" "/tmp/demo"

  printf '%s\n' "${checks[0]}" | jq -e \
    '. == {"name":"demo","status":"error","detail":"broken","path":"/tmp/demo"}' >/dev/null
}

@test "prereq_worst_status preserves status precedence" {
  run cog::fn::prereq_worst_status ok warn
  assert_success
  assert_output "warn"

  run cog::fn::prereq_worst_status warn error
  assert_success
  assert_output "error"

  run cog::fn::prereq_worst_status ok ok
  assert_success
  assert_output "ok"
}
