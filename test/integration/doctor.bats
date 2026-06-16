setup() {
  bats_require_minimum_version 1.5.0
  load '../test_helper/common-setup'
  _common_setup
  export HOME="${BATS_TEST_TMPDIR}/home"
  export XDG_STATE_HOME="${BATS_TEST_TMPDIR}/state"
  mkdir -p "$HOME" "$XDG_STATE_HOME"
}

@test "cog doctor --json emits structured diagnostics on stdout only" {
  run --separate-stderr cog --json doctor

  assert_success
  [ -z "$stderr" ]
  printf '%s\n' "$output" | jq -e '.schema=="cog.doctor.v1" and (.checks|length>0)' >/dev/null
}
