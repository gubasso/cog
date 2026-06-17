setup() {
  bats_require_minimum_version 1.5.0
  load '../test_helper/common-setup'
  _common_setup
  export LIB_DIR="${BATS_TEST_DIRNAME}/../../lib"
  source "${LIB_DIR}/helpers.sh"
  source "${LIB_DIR}/functions/fn_ui_print.sh"
  source "${LIB_DIR}/functions/fn_log.sh"
  source "${LIB_DIR}/functions/fn_error_raise.sh"
  source "${LIB_DIR}/functions/fn_json_write.sh"
  source "${LIB_DIR}/commands/cmd_osc_probe_binary.sh"
}

@test "osc-probe-binary urlencode escapes reserved characters" {
  run __cog_osc_probe_binary_urlencode 'libstdc++6'
  assert_success
  assert_output 'libstdc%2B%2B6'

  run __cog_osc_probe_binary_urlencode 'openSUSE:Factory'
  assert_success
  assert_output 'openSUSE%3AFactory'
}

@test "osc-probe-binary parses binary XML matches" {
  local xml="${BATS_TEST_TMPDIR}/matches.xml"
  printf '%s\n' '<binary name="gcc-c++" package="gcc14" project="p"/>' '<binary name="ignored" project="p"/>' >"$xml"

  run __cog_osc_probe_binary_matches_json "$xml"

  assert_success
  printf '%s\n' "$output" | jq -e 'length == 1 and .[0].binary == "gcc-c++" and .[0].package == "gcc14"' >/dev/null
}
