setup() {
  bats_require_minimum_version 1.5.0
  load '../test_helper/common-setup'
  _common_setup
  export LIB_DIR="${BATS_TEST_DIRNAME}/../../lib"
  export HOME="${BATS_TEST_TMPDIR}/home"
  export XDG_STATE_HOME="${BATS_TEST_TMPDIR}/state"
  mkdir -p "$HOME" "$XDG_STATE_HOME"
  source "${LIB_DIR}/helpers.sh"
  source "${LIB_DIR}/functions/fn_ui_print.sh"
  source "${LIB_DIR}/functions/fn_log.sh"
  source "${LIB_DIR}/functions/fn_error_raise.sh"
  source "${LIB_DIR}/functions/fn_json_write.sh"
  source "${LIB_DIR}/functions/fn_refs.sh"
  source "${LIB_DIR}/functions/fn_git.sh"
  source "${LIB_DIR}/functions/fn_codex.sh"
  source "${LIB_DIR}/commands/cmd_preflight.sh"
}

@test "preflight JSON array helper encodes lines" {
  run __cog_preflight_json_array_from_lines one two

  assert_success
  printf '%s\n' "$output" | jq -e '. == ["one","two"]' >/dev/null
}

@test "preflight cache path is empty without session" {
  unset CLAUDE_CODE_SESSION_ID

  run __cog_preflight_agents_cache_path

  assert_success
  assert_output ""
}

@test "preflight rejects unknown agents option" {
  run --separate-stderr __cog_preflight_agents --bad

  assert_failure 65
  [[ $stderr == *"err.kind: InvalidInput"* ]]
}
