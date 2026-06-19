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
  source "${LIB_DIR}/functions/fn_queue.sh"
  source "${LIB_DIR}/commands/cmd_queue_select.sh"
}

@test "queue-select result helper builds selected JSON" {
  run __cog_queue_select_result_json true rounds queue.yaml /repo false selected '{"item":"r"}' '["r"]' '[]' ""

  assert_success
  # shellcheck disable=SC2154 # Defined by sourced cmd_queue_select.sh.
  printf '%s\n' "$output" | jq -e "$__cog_queue_select_self_check" >/dev/null
  printf '%s\n' "$output" | jq -e '.ok == true and .schema == "rounds" and .state == "selected" and .selected.item == "r"' >/dev/null
}

@test "queue-select build reports blocked dependencies" {
  local queue="${BATS_TEST_TMPDIR}/queue-rounds.yaml"
  cat >"$queue" <<'EOF'
rounds:
  - item: blocked
    status: todo
    depends_on: [missing]
    prompt: /prex -ar blocked.md
    notes: note
EOF

  run __cog_queue_select_build_json rounds "$queue" /repo false

  assert_success
  printf '%s\n' "$output" | jq -e '.ok == false and .schema == "rounds" and .state == "blocked"' >/dev/null
}
