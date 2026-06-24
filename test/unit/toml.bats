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
  source "${LIB_DIR}/functions/fn_log.sh"
  # shellcheck source=/dev/null
  source "${LIB_DIR}/functions/fn_error_raise.sh"
  # shellcheck source=/dev/null
  source "${LIB_DIR}/functions/fn_toml.sh"
}

@test "toml require reports missing taplo with zypper hint" {
  local fakebin="${BATS_TEST_TMPDIR}/no-taplo"
  mkdir -p "$fakebin"

  # shellcheck disable=SC2016
  run --separate-stderr env PATH="$fakebin" "$BASH" -c '
    source "$1"
    source "$2"
    source "$3"
    source "$4"
    cog::fn::toml::require
  ' bash "${LIB_DIR}/helpers.sh" "${LIB_DIR}/functions/fn_ui_print.sh" \
    "${LIB_DIR}/functions/fn_log.sh" "${LIB_DIR}/functions/fn_toml.sh"

  assert_failure 69
  [[ $stderr == *"err.kind: MissingRequirement"* ]]
  [[ $stderr == *"command: taplo"* ]]
  [[ $stderr == *"sudo zypper install taplo"* ]]
}

@test "toml json converts fixture TOML to JSON" {
  command -v taplo >/dev/null 2>&1 || skip "taplo not installed"
  local fixture="${BATS_TEST_TMPDIR}/fixture.toml"
  printf '%s\n' \
    'name = "demo"' \
    'count = 3' \
    '' \
    '[nested]' \
    'enabled = true' >"$fixture"

  run cog::fn::toml::json "$fixture"

  assert_success
  printf '%s\n' "$output" | jq -e \
    '.name == "demo" and .count == 3 and .nested.enabled == true' >/dev/null
}
