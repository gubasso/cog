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
  source "${LIB_DIR}/functions/fn_round_req.sh"
  source "${LIB_DIR}/commands/cmd_round_req.sh"
}

write_round() {
  cat >"$1" <<'EOF'
# Round

## Acceptance Criteria

- [ ] First criterion.
- [ ] This plan's `queue-rounds.yaml` shows round `alpha` as `done`. {{If this is the final implementation-plan round, also mark the plan done.}}
- [ ] The top-level .implementation-plans/queue-plans.yaml shows this plan as done.
EOF
}

@test "round-req stamp skips realized Template-A boilerplate" {
  write_round "${BATS_TEST_TMPDIR}/alpha.md"
  run cog::fn::round_req::stamp_json "${BATS_TEST_TMPDIR}/alpha.md" false
  assert_success
  printf '%s\n' "$output" | jq -e '(.assigned | length) == 1 and .assigned[0].id == "R1"' >/dev/null
}

@test "round-req list reports duplicate and malformed ids" {
  cat >"${BATS_TEST_TMPDIR}/bad.md" <<'EOF'
# Bad

## Acceptance Criteria

- [ ] (R1) One.
- [ ] (R1) Duplicate.
- [ ] (RX) Bad.
EOF
  run cog::fn::round_req::list_json "${BATS_TEST_TMPDIR}/bad.md"
  assert_success
  printf '%s\n' "$output" | jq -e '.ok == false and (.duplicates | index("R1")) and (.invalid | length == 1)' >/dev/null
}
