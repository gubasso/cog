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
  source "${LIB_DIR}/functions/fn_queue.sh"
  source "${LIB_DIR}/commands/cmd_queue_append.sh"
}

@test "queue-append dependency CSV becomes array" {
  run __cog_queue_append_depends_json "one,two"

  assert_success
  printf '%s\n' "$output" | jq -e '. == ["one","two"]' >/dev/null
}

@test "queue-append entry JSON matches queue schema" {
  local entry
  entry="$(__cog_queue_append_entry_json item todo "/executor-prex -ar item.md" "base" "note")"

  run cog::fn::queue_entry_json_validate "$entry"

  assert_success
}

@test "queue-append emits self-checked JSON" {
  local queue="${BATS_TEST_TMPDIR}/queue-rounds.yaml"
  printf '%s\n' "rounds: []" >"$queue"

  run cog::cmd::queue_append --schema rounds --queue "$queue" --item one --status todo --prompt "/executor-prex -ar one.md" --json

  assert_success
  # shellcheck disable=SC2154 # Defined by sourced cmd_queue_append.sh.
  printf '%s\n' "$output" | jq -e "$__cog_queue_append_self_check" >/dev/null
}
