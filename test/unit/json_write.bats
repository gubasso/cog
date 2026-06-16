setup() {
  bats_require_minimum_version 1.5.0
  load '../test_helper/common-setup'
  _common_setup
  export LIB_DIR="${BATS_TEST_DIRNAME}/../../lib"
  export HOME="${BATS_TEST_TMPDIR}/home"
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
  source "${LIB_DIR}/functions/fn_json_write.sh"
}

@test "json_emit validates and emits unchanged JSON" {
  run --separate-stderr cog::fn::json_emit '.ok == true' '{"ok":true}'

  assert_success
  assert_output '{"ok":true}'
  [ -z "$stderr" ]
}

@test "json_emit invalid generated JSON exits software not catch-all" {
  run --separate-stderr cog::fn::json_emit '.ok == true' '{"ok":false}'

  assert_failure 70
  [[ $stderr == *"err.kind: InvalidJsonOutput"* ]]
}

@test "json_validate malformed user JSON returns data error mapping" {
  [ "$(cog::fn::error_exit_for_kind InvalidJsonInput)" -eq 65 ]
  run cog::fn::json_validate '.' '{'
  assert_failure
}

@test "json_write_fragment writes file and emits RESOLVED line" {
  local out="${BATS_TEST_TMPDIR}/fragment.json"

  run --separate-stderr cog::fn::json_write_fragment "$out" '.ok == true' '{"ok":true}'

  assert_success
  assert_output "RESOLVED ${out}"
  [ -z "$stderr" ]
  jq -e '.ok == true' "$out" >/dev/null
}
