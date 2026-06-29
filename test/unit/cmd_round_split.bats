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
  source "${LIB_DIR}/functions/fn_round_split.sh"
  source "${LIB_DIR}/commands/cmd_round_split.sh"
}

@test "round-split coverage reports loss by id" {
  cat >"${BATS_TEST_TMPDIR}/parent.md" <<'EOF'
# Parent

## Acceptance Criteria

- [ ] (R1) Keep.
- [ ] (R2) Lose.
EOF
  cat >"${BATS_TEST_TMPDIR}/child.md" <<'EOF'
# Child

## Acceptance Criteria

- [ ] (R1) Keep.
EOF
  run cog::fn::round_split::coverage_json "${BATS_TEST_TMPDIR}/parent.md" "${BATS_TEST_TMPDIR}/child.md"
  assert_success
  printf '%s\n' "$output" | jq -e '.ok == false and .lost == ["R2"]' >/dev/null
}
