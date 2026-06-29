setup() {
  bats_require_minimum_version 1.5.0
  load '../test_helper/common-setup'
  _common_setup
}

@test "cog plan-complexity --help dispatches" {
  run cog plan-complexity --help
  assert_success
  [[ $output == *"Extract and compare implementation plan complexity signals"* ]]
}

@test "cog plan-complexity extract and ceiling smoke through real binary" {
  cat >"${BATS_TEST_TMPDIR}/README.md" <<'EOF'
# Plan

Touches lib/commands/cmd_demo.sh and test/unit/demo.bats.

## Acceptance Criteria

- [ ] Tests pass.
EOF
  run cog plan-complexity extract "${BATS_TEST_TMPDIR}/README.md" --json
  assert_success
  printf '%s\n' "$output" | jq -e '.input_kind == "plan" and .signals.acceptance_criteria_count == 1' >/dev/null

  run cog plan-complexity ceiling --json
  assert_success
  printf '%s\n' "$output" | jq -e '.ceiling == "Very High"' >/dev/null

  run cog plan-complexity over-ceiling --grade "Extreme" --json
  assert_success
  printf '%s\n' "$output" | jq -e '.over == true' >/dev/null
}
