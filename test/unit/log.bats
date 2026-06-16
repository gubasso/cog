setup() {
  bats_require_minimum_version 1.5.0
  load '../test_helper/common-setup'
  _common_setup
  export LIB_DIR="${BATS_TEST_DIRNAME}/../../lib"
  export HOME="${BATS_TEST_TMPDIR}/home"
  export XDG_STATE_HOME="${BATS_TEST_TMPDIR}/state"
  mkdir -p "$HOME" "$XDG_STATE_HOME"
  # shellcheck source=/dev/null
  source "${LIB_DIR}/functions/fn_ui_print.sh"
  # shellcheck source=/dev/null
  source "${LIB_DIR}/functions/fn_log.sh"
}

@test "log writes structured record without ANSI" {
  local -A ctx=([log_level]=warn)
  local -A config=([log_level]=warn)
  local log_file="${XDG_STATE_HOME}/cog/cog.log"

  cog::fn::log_init ctx config
  cog::fn::log_warn "cog::test" "op=unit.test" "status=ok" "msg=hello world"

  [ -f "$log_file" ]
  run cat "$log_file"
  assert_success
  [[ $output == ts=* ]]
  [[ $output == *" level=warn "* ]]
  [[ $output == *" target=cog::test "* ]]
  [[ $output == *" op=unit.test "* ]]
  [[ $output != *$'\033['* ]]
}

@test "log keeps one record per line for newline-bearing values" {
  local -A ctx=([log_level]=warn)
  local -A config=([log_level]=warn)
  local log_file="${XDG_STATE_HOME}/cog/cog.log"

  cog::fn::log_init ctx config
  cog::fn::log_warn "cog::test" "msg=line one"$'\n'"line two"

  [ -f "$log_file" ]
  run wc -l <"$log_file"
  assert_success
  [ "$output" -eq 1 ]
  run cat "$log_file"
  assert_success
  [[ $output == *'msg="line one\nline two"'* ]]
}

@test "log append failure emits exactly one warning and no raw diagnostic" {
  [ "$(id -u)" -ne 0 ] || skip "root bypasses directory permissions"

  local -A ctx=([log_level]=warn)
  local -A config=([log_level]=warn)
  local log_dir="${XDG_STATE_HOME}/cog"

  mkdir -p "$log_dir"
  chmod 555 "$log_dir"

  cog::fn::log_init ctx config
  run --separate-stderr cog::fn::log_warn "cog::test" "msg=hello"

  chmod 755 "$log_dir"

  assert_success
  [ -z "$output" ]
  [ "$stderr" = "Warning: could not write program log" ]
}

@test "log level threshold filters lower-priority records" {
  # shellcheck disable=SC2034 # Nameref arguments are read by cog::fn::log_init.
  local -A ctx=([log_level]=warn)
  # shellcheck disable=SC2034 # Nameref arguments are read by cog::fn::log_init.
  local -A config=([log_level]=warn)
  local log_file="${XDG_STATE_HOME}/cog/cog.log"

  cog::fn::log_init ctx config
  cog::fn::log_info "cog::test" "msg=hidden"
  cog::fn::log_error "cog::test" "msg=shown"

  run cat "$log_file"
  assert_success
  [[ $output == *"level=error"* ]]
  [[ $output != *"hidden"* ]]
}
